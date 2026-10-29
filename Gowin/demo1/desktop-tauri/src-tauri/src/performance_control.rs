use super::*;
use crate::performance::{LiveEdit, normalized, valid_owner};
impl Engine {
    pub(super) fn resource_ready(&self, index: usize, p: &Value) -> Result<()> {
        if p["mode"] == "采样钢琴" && !self.pcm_available {
            return Err("请先上传 PCM 采样包。".into());
        }
        if model::custom(p) {
            let bound = &self.config["tauri_bindings"][index.to_string()];
            if self.active_resource.is_null()
                || (!bound.is_null() && *bound != self.active_resource)
            {
                return Err("此键的波表未驻留，请先同步或上传波表。".into());
            }
        }
        Ok(())
    }
    pub(super) fn start_note(
        &mut self,
        index: usize,
        owner: &str,
        velocity: Option<u8>,
        internal: bool,
    ) -> Result<()> {
        if !valid_owner(owner) && !(internal && owner.starts_with("midi:")) {
            return Err("无效演奏来源".into());
        }
        if !self.performance.armed {
            return Err("演奏输入已暂停。".into());
        }
        if internal && self.last_ui.elapsed().as_secs_f64() > 1.5 {
            return Err("界面心跳中断，MIDI 演奏已暂停。".into());
        }
        if !self.online {
            return Err("请先连接 FPGA。".into());
        }
        if self.transfer.is_some() && self.live.inflight.is_none() {
            return Err("资源传输中，请稍候。".into());
        }
        if !self.synced.contains(&index) || self.live.pending.contains_key(&index) {
            return Err("此音键参数尚未确认，请等待同步。".into());
        }
        let key = &self.config["keys"][index];
        let profile = self.live.applied.get(&index).unwrap_or(&key["synth"]);
        self.resource_ready(index, profile)?;
        let note = key["note"].as_i64().unwrap() + self.performance.transpose as i64;
        if !(0..=127).contains(&note) {
            return Err("移调后音高超出 MIDI 0–127 范围。".into());
        }
        let velocity = velocity
            .or(self.performance.velocity)
            .unwrap_or(key["velocity"].as_u64().unwrap() as u8);
        if velocity == 0 || velocity > 127 {
            return Err("演奏力度必须为 1–127。".into());
        }
        let retrigger = self.held.get(&index).is_some_and(|owners| {
            !owners.is_empty() && owners.iter().all(|s| s.starts_with("sustain:"))
        });
        if retrigger {
            self.send(vec![protocol::packet(2, 32 + index as u8, 0, 0, 0)]);
            self.held.remove(&index);
        }
        if self.held.get(&index).is_none_or(BTreeSet::is_empty)
            && !self.send(vec![protocol::packet(
                1,
                32 + index as u8,
                note as u8,
                velocity,
                0,
            )])
        {
            return Err("音符发送队列不可用。".into());
        }
        self.held.entry(index).or_default().insert(owner.into());
        if !internal {
            self.last_ui = Instant::now();
            if let Some(l) = &self.link {
                l.touch_ui();
            }
        }
        Ok(())
    }
    fn sustain(&mut self, down: bool, source: String) {
        if down {
            self.performance.pedals.insert(source);
        } else {
            self.performance.pedals.remove(&source);
        }
        let mut released = Vec::new();
        for (index, owners) in &mut self.held {
            owners.retain(|owner| {
                owner
                    .strip_prefix("sustain:")
                    .is_none_or(|o| self.performance.sustain(o))
            });
            if owners.is_empty() {
                released.push(*index);
            }
        }
        for i in released {
            self.held.remove(&i);
            if self.online {
                self.send(vec![protocol::packet(2, 32 + i as u8, 0, 0, 0)]);
            }
        }
    }
    fn queue_live(&mut self, index: usize, profile: Value, restore: bool) -> Result<()> {
        if !self.online {
            return Err("请先连接 FPGA，再开启实时同步。".into());
        }
        if self.transfer.is_some() && self.live.inflight.is_none() {
            return Err("请等待资源上传结束。".into());
        }
        model::validate_profile(&profile)?;
        self.resource_ready(index, &profile)?;
        let profile = normalized(profile);
        let current = self
            .live
            .applied
            .get(&index)
            .cloned()
            .unwrap_or_else(|| normalized(self.config["keys"][index]["synth"].clone()));
        let same = current == profile
            && self.synced.contains(&index)
            && self.live.inflight.as_ref().is_none_or(|e| e.index != index);
        if same {
            self.live.pending.remove(&index);
            if restore {
                self.live.applied.remove(&index);
            }
            return Ok(());
        }
        self.live.pending.insert(
            index,
            LiveEdit {
                index,
                profile,
                restore,
            },
        );
        self.live.error.clear();
        Ok(())
    }
    pub(super) fn performance_command(&mut self, method: &str, p: &Value) -> Option<Result<Value>> {
        if ![
            "performance_settings",
            "performance_arm",
            "set_sustain",
            "set_live_volume",
            "live_mode",
            "live_edit",
            "live_discard",
            "perform_note_on",
            "midi_ports",
            "midi_connect",
            "midi_disconnect",
        ]
        .contains(&method)
        {
            return None;
        }
        Some((|| -> Result<Value> {
            match method {
                "perform_note_on" => {
                    let v = p
                        .get("velocity")
                        .map(|_| model::integer(p, "velocity", 1, 127))
                        .transpose()?
                        .map(|n| n as u8);
                    self.start_note(Self::index(p)?, model::text(p, "owner")?, v, false)?;
                }
                "performance_settings" => {
                    let transpose = p
                        .get("transpose")
                        .map(|v| {
                            v.as_i64()
                                .filter(|n| (-24..=24).contains(n))
                                .ok_or("移调必须为 -24..24 的整数")
                        })
                        .transpose()?;
                    let velocity = if p.get("velocity").is_some() {
                        Some(if p["velocity"].is_null() {
                            None
                        } else {
                            Some(model::integer(p, "velocity", 1, 127)? as u8)
                        })
                    } else {
                        None
                    };
                    let channel = p
                        .get("channel")
                        .map(|_| model::integer(p, "channel", 0, 16))
                        .transpose()?;
                    if transpose.is_some_and(|n| n as i32 != self.performance.transpose)
                        || channel.is_some_and(|n| n as u8 != self.performance.channel)
                    {
                        self.release_all();
                    }
                    if let Some(v) = transpose {
                        self.performance.transpose = v as i32;
                    }
                    if let Some(v) = velocity {
                        self.performance.velocity = v;
                    }
                    if let Some(v) = channel {
                        self.performance.channel = v as u8;
                    }
                }
                "performance_arm" => {
                    let enabled = p["enabled"].as_bool().ok_or("enabled 必须为布尔值")?;
                    if !enabled {
                        self.release_all();
                    }
                    self.performance.armed = enabled;
                }
                "set_sustain" => {
                    let down = p["down"].as_bool().ok_or("down 必须为布尔值")?;
                    if down && !self.performance.armed {
                        return Err("演奏输入已暂停。".into());
                    }
                    self.sustain(down, "ui".into());
                }
                "set_live_volume" => {
                    let volume = model::num(p, "volume", 0.0, 100.0)?;
                    if !self.online {
                        return Err("主音量实时控制需要连接 FPGA。".into());
                    }
                    self.performance.volume = volume;
                    self.performance.pending_volume = Some(volume);
                }
                "live_mode" => {
                    let enabled = p["enabled"].as_bool().ok_or("enabled 必须为布尔值")?;
                    if enabled && !self.online {
                        return Err("请先连接 FPGA。".into());
                    }
                    self.live.enabled = enabled;
                    self.live.error.clear();
                    if !enabled {
                        self.live.pending.clear();
                        self.tell("已停止自动同步；硬件保留最后确认的参数。", "info");
                    }
                }
                "live_edit" => {
                    if !self.live.enabled {
                        return Err("实时参数同步尚未开启。".into());
                    }
                    self.queue_live(Self::index(p)?, p["profile"].clone(), false)?;
                }
                "live_discard" => {
                    let i = Self::index(p)?;
                    let affected = self.live.applied.contains_key(&i)
                        || self.live.inflight.as_ref().is_some_and(|e| e.index == i)
                        || self.live.pending.contains_key(&i);
                    self.live.pending.remove(&i);
                    if affected && self.online {
                        self.queue_live(i, self.config["keys"][i]["synth"].clone(), true)?;
                    }
                }
                "midi_ports" => return midi::ports(),
                "midi_connect" => {
                    self.release_all();
                    self.midi_link = None;
                    let id = model::integer(p, "id", 0, 1023)? as usize;
                    let name = model::text(p, "name")?;
                    self.midi_link = Some(midi::Connection::open(id, name)?);
                    self.midi_message =
                        format!("已连接 {name}；按音键 MIDI 音高匹配，CC7 音量 / CC64 延音。");
                    self.midi_checked = Instant::now();
                }
                "midi_disconnect" => {
                    self.release_all();
                    self.midi_link = None;
                    self.midi_message = "MIDI 输入已断开。".into();
                }
                _ => {}
            }
            Ok(Value::Null)
        })())
    }
    pub(super) fn performance_tick(&mut self) {
        if self.performance.last_volume_send.elapsed().as_millis() >= 50
            && let Some(v) = self.performance.pending_volume.take()
        {
            if self.online
                && !self.send(vec![protocol::packet(
                    3,
                    0,
                    0,
                    0,
                    (v * 65535.0 / 100.0).round_ties_even() as u16,
                )])
            {
                self.tell("主音量发送失败，请检查设备。", "error");
            }
            self.performance.last_volume_send = Instant::now();
        }
        let messages = self.midi_link.as_ref().map(|m| m.poll());
        if let Some(result) = messages {
            match result {
                Ok(messages) => {
                    for message in messages {
                        self.handle_midi(message);
                    }
                }
                Err(e) => {
                    self.release_all();
                    self.midi_link = None;
                    self.midi_message = e;
                }
            }
        }
        if self.midi_checked.elapsed().as_secs() >= 1 {
            self.midi_checked = Instant::now();
            if let Some(link) = &self.midi_link
                && !link.present().unwrap_or(false)
            {
                self.release_all();
                self.midi_link = None;
                self.midi_message = "MIDI 设备已移除，已释放全部音符。".into();
            }
        }
        if self.online
            && self.transfer.is_none()
            && self.live.last_send.elapsed().as_millis() >= 150
            && let Some((_, edit)) = self.live.pending.pop_first()
        {
            let index = edit.index;
            let result =
                Transfer::profiles(&[(32 + index as u8, edit.profile.clone())], 0.0, token())
                    .and_then(|t| {
                        if self.link.as_mut().is_some_and(|l| l.upload(t)) {
                            Ok(())
                        } else {
                            Err("实时参数发送失败。".into())
                        }
                    });
            match result {
                Ok(()) => {
                    self.live.inflight = Some(edit);
                    self.live.last_send = Instant::now();
                    self.synced.remove(&index);
                    self.transfer = Some("profiles");
                    self.progress = 0;
                    self.total = 1;
                    self.tell("实时参数正在确认；持音保持，下一次起音使用新参数。", "info");
                }
                Err(e) => {
                    self.synced.remove(&index);
                    self.live.inflight = Some(edit);
                    self.live_failure(&e);
                    self.tell(e, "error");
                }
            }
        }
    }
    pub(super) fn live_failure(&mut self, error: &str) {
        if self.live.inflight.is_some() || !self.live.pending.is_empty() {
            if let Some(edit) = self.live.inflight.take() {
                self.synced.remove(&edit.index);
                self.live.applied.remove(&edit.index);
            }
            self.live.pending.clear();
            self.live.enabled = false;
            self.live.error = error.into();
        }
    }
    pub(super) fn finish_live(&mut self) -> bool {
        if let Some(edit) = self.live.inflight.take() {
            if edit.restore {
                self.live.applied.remove(&edit.index);
            } else {
                self.live.applied.insert(edit.index, edit.profile);
            }
            self.synced.insert(edit.index);
            self.transfer = None;
            self.progress = 1;
            self.tell(
                "实时参数已确认，下一次起音生效；保存可保留到电脑。",
                "success",
            );
            true
        } else {
            false
        }
    }
    pub(super) fn handle_midi(&mut self, message: midi::Message) {
        use midi::Message::*;
        let channel = match message {
            On { channel, .. } | Off { channel, .. } | Control { channel, .. } => channel,
        };
        if self.performance.channel != 0 && self.performance.channel != channel + 1 {
            return;
        }
        if !self.performance.armed {
            return;
        }
        match message {
            On {
                channel,
                note,
                velocity,
            } => {
                let owner = format!("midi:{channel}:{note}");
                if let Some(old) = self.performance.routes.remove(&(channel, note)) {
                    self.note_off(old, &owner);
                }
                if let Some(index) = self.config["keys"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .position(|k| k["note"].as_u64() == Some(note as u64))
                {
                    match self.start_note(index, &owner, Some(velocity), true) {
                        Ok(()) => {
                            self.performance.routes.insert((channel, note), index);
                            self.midi_message = format!(
                                "MIDI 通道 {} · 音符 {note} · 力度 {velocity}",
                                channel + 1
                            );
                        }
                        Err(e) => self.midi_message = e,
                    }
                } else {
                    self.midi_message = format!("MIDI 音符 {note} 未分配音键。");
                }
            }
            Off { channel, note } => {
                if let Some(index) = self.performance.routes.remove(&(channel, note)) {
                    self.note_off(index, &format!("midi:{channel}:{note}"));
                }
            }
            Control {
                channel,
                cc: 64,
                value,
            } => self.sustain(value >= 64, format!("midi:{channel}")),
            Control { cc: 7, value, .. } if self.online => {
                self.performance.volume = value as f64 * 100.0 / 127.0;
                self.performance.pending_volume = Some(self.performance.volume);
            }
            Control { cc: 120 | 123, .. } => self.release_all(),
            _ => {}
        }
    }
}
