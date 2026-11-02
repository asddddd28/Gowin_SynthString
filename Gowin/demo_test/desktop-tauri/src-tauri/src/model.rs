use crate::{
    audio::AudioView,
    calibration::{Calibration, CalibrationView, Profile},
    protocol::*,
};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct JoystickMapping {
    pub swap: bool,
    pub flip_x: bool,
    pub flip_y: bool,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PadMapping {
    pub swap_boards: bool,
    pub transpose: bool,
    pub flip_x: bool,
    pub flip_y: bool,
}
impl Default for PadMapping {
    fn default() -> Self {
        Self {
            swap_boards: false,
            transpose: true,
            flip_x: false,
            flip_y: false,
        }
    }
}
#[derive(Clone, Serialize, Deserialize)]
pub struct Settings {
    pub joystick: JoystickMapping,
    pub pad: PadMapping,
    pub effect: u8,
    pub direction: u8,
    pub volume: f32,
    pub guitar_enabled: bool,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            joystick: JoystickMapping::default(),
            pad: PadMapping::default(),
            effect: 1,
            direction: 0,
            volume: 0.3,
            guitar_enabled: true,
        }
    }
}
impl Settings {
    pub fn validate(&self) -> Result<(), String> {
        if ![0, 1, 2, 3, 4, 6].contains(&self.effect)
            || self.direction > 1
            || !self.volume.is_finite()
            || !(0.0..=1.).contains(&self.volume)
        {
            Err("设置超出有效范围".into())
        } else {
            Ok(())
        }
    }
}
#[derive(Clone, Default, Serialize)]
pub struct KeyView {
    pub raw: Option<u16>,
    pub filtered: Option<f64>,
    pub depth: Option<f64>,
    pub fresh: bool,
    pub pressed: bool,
    pub updated: f64,
}
#[derive(Clone, Default, Serialize)]
pub struct EncoderView {
    pub record: Option<Encoder>,
    pub edges: i64,
    pub positive: u64,
    pub negative: u64,
    pub invalid: u64,
    pub discontinuities: u64,
    pub fresh: bool,
    pub updated: f64,
    pub moved: f64,
    pub motion: i8,
}
impl EncoderView {
    pub fn update(&mut self, r: Encoder, now: f64) {
        if let Some(old) = &self.record {
            let dt = now - self.updated;
            let p = r.positive.wrapping_sub(old.positive) as u64;
            let n = r.negative.wrapping_sub(old.negative) as u64;
            let x = r.invalid.wrapping_sub(old.invalid) as u64;
            if !(0.0..=0.6).contains(&dt) || p.max(n).max(x) > (dt * 2000.).max(256.) as u64 {
                self.discontinuities += 1;
                self.motion = 0;
            } else {
                self.edges += p as i64 - n as i64;
                self.positive += p;
                self.negative += n;
                self.invalid += x;
                if p + n > 0 {
                    self.moved = now;
                    self.motion = if p > n {
                        1
                    } else if n > p {
                        -1
                    } else {
                        2
                    };
                }
            }
        }
        self.updated = now;
        self.record = Some(r);
        self.fresh = true;
    }
}
#[derive(Clone, Default, Serialize)]
pub struct JoyView {
    pub record: Option<Joystick>,
    pub x: Option<i8>,
    pub y: Option<i8>,
    pub pressed: bool,
    pub fresh: bool,
    pub updated: f64,
}
#[derive(Clone, Default, Serialize)]
pub struct ButtonsView {
    pub record: Option<Buttons>,
    pub fresh: bool,
    pub updated: f64,
}
#[derive(Clone, Default, Serialize)]
pub struct PadView {
    pub record: Option<Pad>,
    pub position: Option<[f64; 2]>,
    pub fresh: bool,
    pub updated: f64,
    pub advanced: f64,
}
#[derive(Clone, Default, Serialize)]
pub struct GuitarView {
    pub records: [Option<Guitar>; 2],
    pub received: [f64; 2],
    pub sample_hz: [f64; 2],
    pub event_age_ms: [f64; 2],
    pub counts: [u64; 6],
    pub last_hits: [f64; 6],
    pub packet_gaps: u64,
    pub stale_events: u64,
    pub duplicates: u64,
}
#[derive(Clone, Default, Serialize)]
pub struct Transfer {
    pub busy: bool,
    pub completed: usize,
    pub total: usize,
    pub failures: u64,
    pub message: String,
}
#[derive(Clone, Serialize)]
pub struct Log {
    pub time: f64,
    pub kind: String,
    pub text: String,
}
#[derive(Clone, Serialize)]
pub struct View {
    pub now: f64,
    pub connection: String,
    pub port: String,
    pub protocol: String,
    pub message: String,
    pub identity: Option<Identity>,
    pub identity_updated: f64,
    pub keys: Vec<KeyView>,
    pub encoders: Vec<EncoderView>,
    pub joystick: JoyView,
    pub buttons: ButtonsView,
    pub pads: Vec<PadView>,
    pub guitar: GuitarView,
    pub board: Option<Board>,
    pub board_updated: f64,
    pub game: Option<Game>,
    pub game_updated: f64,
    pub profile: Profile,
    pub settings: Settings,
    pub calibration: Option<CalibrationView>,
    pub transfer: Transfer,
    pub counts: [u64; 9],
    pub rates: [f64; 9],
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub errors: u64,
    pub sequence_errors: u64,
    pub discarded: u64,
    pub fresh_count: usize,
    pub recording: Option<String>,
    pub replay_progress: f64,
    pub audio: AudioView,
    pub logs: VecDeque<Log>,
    pub settings_path: String,
}
pub struct Model {
    pub view: View,
    pub calibration: Option<Calibration>,
    pub histories: Vec<VecDeque<[f64; 2]>>,
    anchors: [Option<(u32, f64)>; 2],
    previous_key: Option<usize>,
    previous_encoder: Option<u8>,
    previous_joystick: Option<u16>,
    rate_time: f64,
    rate_counts: [u64; 9],
}
impl Model {
    pub fn new(profile: Profile, settings: Settings) -> Self {
        Self {
            view: View {
                now: 0.,
                connection: "disconnected".into(),
                port: String::new(),
                protocol: "unknown".into(),
                message: "选择 DEBUG 串口开始".into(),
                identity: None,
                identity_updated: -100.,
                keys: vec![KeyView::default(); 32],
                encoders: vec![EncoderView::default(); 5],
                joystick: JoyView::default(),
                buttons: ButtonsView::default(),
                pads: vec![PadView::default(); 2],
                guitar: GuitarView::default(),
                board: None,
                board_updated: -100.,
                game: None,
                game_updated: -100.,
                profile,
                settings,
                calibration: None,
                transfer: Transfer::default(),
                counts: [0; 9],
                rates: [0.; 9],
                rx_bytes: 0,
                tx_bytes: 0,
                errors: 0,
                sequence_errors: 0,
                discarded: 0,
                fresh_count: 0,
                recording: None,
                replay_progress: 0.,
                audio: AudioView::default(),
                logs: VecDeque::new(),
                settings_path: String::new(),
            },
            calibration: None,
            histories: vec![VecDeque::with_capacity(160); 32],
            anchors: [None, None],
            previous_key: None,
            previous_encoder: None,
            previous_joystick: None,
            rate_time: 0.,
            rate_counts: [0; 9],
        }
    }
    pub fn log(&mut self, kind: &str, text: impl Into<String>, now: f64) {
        self.view.logs.push_front(Log {
            time: now,
            kind: kind.into(),
            text: text.into(),
        });
        self.view.logs.truncate(80);
    }
    pub fn reset(&mut self) {
        let profile = self.view.profile.clone();
        let settings = self.view.settings.clone();
        let path = self.view.settings_path.clone();
        let logs = self.view.logs.clone();
        *self = Self::new(profile, settings);
        self.view.settings_path = path;
        self.view.logs = logs;
    }
    pub fn frame(&mut self, frame: Frame, now: f64) -> Vec<(usize, f64)> {
        self.view.counts[frame.kind()] += 1;
        let mut notes = vec![];
        match frame {
            Frame::Buttons(r) => {
                if self.view.protocol == "unknown" {
                    self.view.protocol = "buttons".into();
                    self.view.message = "六键独立调试 · FPGA 去抖 · RGB 关闭".into();
                    self.log("ok", "已识别 B1 六键开关遥测", now);
                }
                if let Some(old) = &self.view.buttons.record {
                    if r.sequence != old.sequence.wrapping_add(1) {
                        self.view.sequence_errors += 1;
                    }
                }
                self.view.buttons.record = Some(r);
                self.view.buttons.updated = now;
            }
            Frame::Identity(r) => {
                if self.view.protocol != "hub" {
                    self.log("ok", &format!("已识别综合硬件固件 · H1 / 0x{:04X}", r.capabilities), now);
                }
                self.view.identity = Some(r);
                self.view.identity_updated = now;
                self.view.protocol = "hub".into();
                self.view.message = "综合固件已识别 · 所有模块独立持续采集".into();
            }
            Frame::Key(i, value) => {
                if self.view.protocol == "unknown" {
                    self.view.protocol = "keyboard".into();
                }
                if self.previous_key.is_some_and(|p| i != (p + 1) % 32) {
                    self.view.sequence_errors += 1;
                }
                self.previous_key = Some(i);
                let k = &mut self.view.keys[i];
                k.filtered = Some(if k.raw.is_none() || now - k.updated > 0.6 {
                    f64::from(value)
                } else {
                    k.filtered.unwrap() + 0.4 * (f64::from(value) - k.filtered.unwrap())
                });
                k.raw = Some(value);
                k.updated = now;
                let h = &mut self.histories[i];
                h.push_back([now, f64::from(value)]);
                if h.len() > 160 {
                    h.pop_front();
                }
                if let Some(c) = &mut self.calibration {
                    c.feed(i, value, now);
                }
            }
            Frame::Board(r) => {
                self.view.board = Some(r);
                self.view.board_updated = now;
            }
            Frame::Game(r) => {
                self.view.game = Some(r);
                self.view.game_updated = now;
            }
            Frame::Encoder(r) => {
                if self.view.protocol == "unknown" {
                    self.view.protocol = "encoder".into();
                }
                if self
                    .previous_encoder
                    .is_some_and(|p| r.channel != p % 5 + 1)
                {
                    self.view.sequence_errors += 1;
                }
                self.previous_encoder = Some(r.channel);
                let i = r.channel as usize - 1;
                self.view.encoders[i].update(r, now);
            }
            Frame::Joystick(r) => {
                if self.view.protocol == "unknown" {
                    self.view.protocol = "joystick".into();
                }
                if self
                    .previous_joystick
                    .is_some_and(|p| r.sequence != p.wrapping_add(1))
                {
                    self.view.sequence_errors += 1;
                }
                self.previous_joystick = Some(r.sequence);
                self.view.joystick.record = Some(r);
                self.view.joystick.updated = now;
            }
            Frame::Pad(r) => {
                if self.view.protocol == "unknown" {
                    self.view.protocol = "touchpad".into();
                }
                let p = &mut self.view.pads[r.board as usize - 1];
                if p.record
                    .as_ref()
                    .is_none_or(|old| old.sequence != r.sequence)
                {
                    p.advanced = now;
                }
                p.record = Some(r);
                p.updated = now;
            }
            Frame::Guitar(r) => {
                if self.view.protocol == "unknown" {
                    self.view.protocol = "touchpad".into();
                }
                notes = self.guitar(r, now);
            }
        }
        notes
    }
    fn guitar(&mut self, r: Guitar, now: f64) -> Vec<(usize, f64)> {
        let b = r.board as usize - 1;
        let g = &mut self.view.guitar;
        if let Some(old) = &g.records[b] {
            if old.packet == r.packet {
                g.duplicates += 1;
                return vec![];
            }
            if r.packet.wrapping_sub(old.packet) != 1 {
                g.packet_gaps += 1;
            }
            let dt = r.milliseconds.wrapping_sub(old.milliseconds);
            if dt > 0 && dt < 1000 {
                g.sample_hz[b] =
                    f64::from(r.sample.wrapping_sub(old.sample)) * 1000. / f64::from(dt);
            }
            if dt > 0x7fffffff {
                self.anchors[b] = None;
            }
        }
        g.received[b] = now;
        g.records[b] = Some(r.clone());
        let Some((tick, time)) = self.anchors[b] else {
            self.anchors[b] = Some((r.milliseconds, now));
            return vec![];
        };
        let expected = time + f64::from(r.milliseconds.wrapping_sub(tick)) / 1000.;
        g.event_age_ms[b] = ((now - expected) * 1000.).max(0.);
        if now < expected {
            self.anchors[b] = Some((r.milliseconds, now));
        }
        if now - expected > 0.15 {
            if r.mask != 0 {
                g.stale_events += 1;
            }
            return vec![];
        }
        if r.flags & 3 != 3 {
            return vec![];
        }
        let mapping = &self.view.settings.pad;
        let axis = if mapping.transpose { 0 } else { 1 };
        let mask = (r.mask >> (axis * 3)) & 7;
        let forward = (r.flags & (4 << axis) != 0) ^ mapping.flip_x;
        let mut slots: Vec<_> = (0..3)
            .filter(|i| mask & (1 << i) != 0)
            .map(|i| if mapping.flip_x { 2 - i } else { i })
            .collect();
        slots.sort();
        if !forward {
            slots.reverse();
        }
        let side = if mapping.swap_boards { 1 - b } else { b };
        slots
            .iter()
            .enumerate()
            .map(|(index, slot)| (side * 3 + slot, index as f64 * 0.0015))
            .collect()
    }
    pub fn tick(&mut self, now: f64) {
        self.view.now = now;
        let active = matches!(self.view.connection.as_str(), "live" | "replay");
        let boardfresh =
            active && self.view.board.is_some() && now - self.view.board_updated <= 0.6;
        let mut fresh = 0;
        for (i, k) in self.view.keys.iter_mut().enumerate() {
            k.fresh = active && k.raw.is_some() && now - k.updated <= 0.6;
            k.depth = if k.fresh {
                k.filtered.and_then(|f| self.view.profile.depth(i, f))
            } else {
                None
            };
            k.pressed = k.fresh
                && boardfresh
                && self
                    .view
                    .board
                    .as_ref()
                    .is_some_and(|b| b.configured && b.pressed & (1 << i) != 0);
            fresh += usize::from(k.fresh);
        }
        for e in &mut self.view.encoders {
            e.fresh = active && e.record.is_some() && now - e.updated <= 0.6;
            if !e.fresh || now - e.moved > 0.6 {
                e.motion = 0;
            }
            fresh += usize::from(e.fresh);
        }
        let j = &mut self.view.joystick;
        j.fresh = active && j.record.is_some() && now - j.updated <= 0.6;
        j.x = None;
        j.y = None;
        j.pressed = false;
        if let Some(r) = &j.record {
            if j.fresh {
                let region = |bits| match bits {
                    0 => Some(-1),
                    1 => Some(0),
                    3 => Some(1),
                    _ => None,
                };
                let (mut x, mut y) = (region(r.filtered & 3), region((r.filtered >> 2) & 3));
                let m = &self.view.settings.joystick;
                if m.swap {
                    std::mem::swap(&mut x, &mut y);
                }
                j.x = x.map(|n| if m.flip_x { -n } else { n });
                j.y = y.map(|n| if m.flip_y { -n } else { n });
                j.pressed = r.filtered & 16 == 0;
            }
        }
        fresh += usize::from(j.fresh);
        for (i, p) in self.view.pads.iter_mut().enumerate() {
            p.fresh = active
                && p.record.as_ref().is_some_and(|r| r.error == 0 && !r.fault)
                && now - p.updated <= 0.6
                && now - p.advanced <= 0.6;
            p.position = None;
            if p.fresh {
                let m = &self.view.settings.pad;
                let raw = if let Some(g) = &self.view.guitar.records[i] {
                    if now - self.view.guitar.received[i] <= 0.15 && g.flags & 3 == 3 {
                        Some(if m.transpose {
                            [f64::from(g.x) / 1023., f64::from(g.y) / 1023.]
                        } else {
                            [f64::from(g.y) / 1023., f64::from(g.x) / 1023.]
                        })
                    } else {
                        None
                    }
                } else {
                    p.record.as_ref().and_then(pad_position).map(|v| {
                        if m.transpose {
                            [v[1], v[0]]
                        } else {
                            v
                        }
                    })
                };
                p.position = raw.map(|v| {
                    [
                        if m.flip_x { 1. - v[0] } else { v[0] },
                        if m.flip_y { 1. - v[1] } else { v[1] },
                    ]
                });
            }
            fresh += usize::from(p.fresh);
        }
        self.view.buttons.fresh = active && self.view.buttons.record.is_some()
            && now - self.view.buttons.updated <= 0.6;
        fresh += if self.view.buttons.fresh { 6 } else { 0 };
        self.view.fresh_count = fresh;
        if let Some(c) = &mut self.calibration {
            c.tick(now);
            self.view.calibration = Some(c.view.clone());
        } else {
            self.view.calibration = None;
        }
        if now - self.rate_time >= 1. {
            let dt = now - self.rate_time;
            for i in 0..9 {
                self.view.rates[i] = (self.view.counts[i] - self.rate_counts[i]) as f64 / dt;
            }
            self.rate_time = now;
            self.rate_counts = self.view.counts;
        }
    }
}
fn pad_position(r: &Pad) -> Option<[f64; 2]> {
    let centroid = |start: usize, len: usize| -> Option<f64> {
        let picked: Vec<_> = (0..len)
            .filter(|i| r.mask & (1 << (start + i)) != 0)
            .collect();
        if picked.is_empty() || picked[picked.len() - 1] - picked[0] + 1 != picked.len() {
            return None;
        }
        let weights: Vec<_> = picked
            .iter()
            .map(|i| f64::from(r.delta[start + i].max(1)))
            .collect();
        Some(
            picked
                .iter()
                .zip(&weights)
                .map(|(i, w)| *i as f64 * w)
                .sum::<f64>()
                / weights.iter().sum::<f64>()
                / (len - 1) as f64,
        )
    };
    Some([centroid(5, 7)?, centroid(0, 5)?])
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn guitar_only_fpga_events_and_order() {
        let mut m = Model::new(Profile::default(), Settings::default());
        let mut r = Guitar {
            board: 1,
            packet: 0,
            sample: 0,
            milliseconds: 0,
            flags: 7,
            mask: 0,
            x: 900,
            y: 500,
            dropped: 0,
        };
        assert!(m.frame(Frame::Guitar(r.clone()), 1.).is_empty());
        r.packet = 1;
        r.sample = 5;
        r.milliseconds = 25;
        r.mask = 7;
        assert_eq!(
            m.frame(Frame::Guitar(r.clone()), 1.025)
                .iter()
                .map(|v| v.0)
                .collect::<Vec<_>>(),
            vec![0, 1, 2]
        );
        assert!(m.frame(Frame::Guitar(r.clone()), 1.026).is_empty());
        r.packet = 2;
        r.milliseconds = 50;
        assert!(m.frame(Frame::Guitar(r), 2.).is_empty());
        assert_eq!(m.view.guitar.stale_events, 1);
    }
    #[test]
    fn guitar_rejects_backlog_then_accepts_current_events() {
        let mut m = Model::new(Profile::default(), Settings::default());
        let mut r = Guitar {
            board: 1,
            packet: 0,
            sample: 0,
            milliseconds: 10_000,
            flags: 7,
            mask: 0,
            x: 500,
            y: 500,
            dropped: 0,
        };
        m.frame(Frame::Guitar(r.clone()), 1.);
        // A blocked reader receives an old event: retain the 150 ms guard.
        r.packet += 1;
        r.milliseconds += 100;
        r.mask = 1;
        assert!(m.frame(Frame::Guitar(r.clone()), 1.5).is_empty());
        assert_eq!(m.view.guitar.stale_events, 1);
        assert!((m.view.guitar.event_age_ms[0] - 400.).abs() < 0.001);
        // Once caught up, receipt time must be measured after the read.
        // Reusing the loop's pre-block 1.0 timestamp here would poison the
        // anchor and incorrectly reject the next fresh event at 1.6.
        r.packet += 1;
        r.milliseconds = 10_500;
        assert_eq!(m.frame(Frame::Guitar(r.clone()), 1.5).len(), 1);
        r.packet += 1;
        r.milliseconds = 10_600;
        assert_eq!(m.frame(Frame::Guitar(r), 1.6).len(), 1);
        assert!(m.view.guitar.event_age_ms[0] < 0.001);
        assert_eq!(m.view.guitar.stale_events, 1);
    }
    #[test]
    fn guitar_clock_wrap_and_board_restart_reanchor_silently() {
        let mut m = Model::new(Profile::default(), Settings::default());
        let mut r = Guitar {
            board: 2,
            packet: 65535,
            sample: 65535,
            milliseconds: u32::MAX - 49,
            flags: 7,
            mask: 1,
            x: 500,
            y: 500,
            dropped: 0,
        };
        assert!(m.frame(Frame::Guitar(r.clone()), 10.).is_empty());
        r.packet = 0;
        r.sample = 20;
        r.milliseconds = 50;
        assert_eq!(m.frame(Frame::Guitar(r.clone()), 10.1)[0].0, 3);
        r.packet = 1;
        r.milliseconds = 10; // FPGA restarted, not the natural u32 wrap.
        assert!(m.frame(Frame::Guitar(r.clone()), 12.).is_empty());
        r.packet = 2;
        r.milliseconds = 110;
        assert_eq!(m.frame(Frame::Guitar(r), 12.1)[0].0, 3);
        assert_eq!(m.view.guitar.stale_events, 0);
    }
    #[test]
    fn encoder_wrap_and_timeout() {
        let mut e = EncoderView::default();
        let mut r = Encoder {
            channel: 1,
            raw: 3,
            filtered: 3,
            q: -2,
            positive: 65534,
            negative: 0,
            invalid: 0,
        };
        e.update(r.clone(), 0.);
        r.positive = 2;
        r.q = 2;
        e.update(r.clone(), 0.1);
        assert_eq!(e.edges, 4);
        r.positive = 30;
        r.q = 30;
        e.update(r, 2.);
        assert_eq!(e.edges, 4);
        assert_eq!(e.discontinuities, 1);
    }
    #[test]
    fn disconnect_clears_active_inputs() {
        let mut m = Model::new(Profile::default(), Settings::default());
        m.view.connection = "live".into();
        m.frame(Frame::Key(0, 900), 1.);
        m.tick(1.);
        assert!(m.view.keys[0].fresh);
        m.view.connection = "disconnected".into();
        m.tick(1.1);
        assert!(!m.view.keys[0].fresh);
        assert!(!m.view.keys[0].pressed);
    }
}
