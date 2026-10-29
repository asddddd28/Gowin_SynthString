//! Byte-compatible UART codec and deterministic acknowledged transfer state machines.
use crate::{Result, model};
use serde_json::{Value, json};

pub type Frame = [u8; 8];
pub fn packet(op: u8, id: u8, note: u8, velocity: u8, value: u16) -> Frame {
    let mut b = [
        0xa5,
        op,
        id,
        note,
        velocity,
        value as u8,
        (value >> 8) as u8,
        0,
    ];
    b[7] = b[..7].iter().fold(0, |a, v| a ^ v);
    b
}
pub fn command(op: u8) -> Frame {
    packet(op, 0, 0, 0, 0)
}
pub fn crc(words: &[u16]) -> u16 {
    let mut c = 0xffffu16;
    for b in words.iter().flat_map(|w| w.to_le_bytes()) {
        c ^= (b as u16) << 8;
        for _ in 0..8 {
            c = if c & 0x8000 != 0 {
                (c << 1) ^ 0x1021
            } else {
                c << 1
            };
        }
    }
    c
}
pub fn sound_packets(s: &Value) -> Vec<Frame> {
    let n = |f: &str| s[f].as_f64().unwrap();
    let sustain = (n("sustain") * 65535.0 / 100.0).round_ties_even() as u16;
    let level = sustain as u64 * 4;
    let step = |d: u64, ms: f64| {
        if d == 0 || ms == 0.0 {
            0
        } else {
            (d as f64 / (ms * model::SAMPLE_RATE / 1000.0))
                .round_ties_even()
                .clamp(1.0, 65535.0) as u16
        }
    };
    let piano = s["wave"] == model::PIANO;
    let values = [
        (n("volume") * 65535.0 / 100.0).round_ties_even() as u16,
        step(262143, n("attack")),
        step(262143 - level, n("decay")),
        sustain,
        step(
            if piano || s["wave"] == model::CUSTOM {
                262143
            } else {
                level
            },
            n("release"),
        ),
        model::wave(&s["wave"]).unwrap(),
        0,
        if piano { 52428 } else { 65535 },
        if piano { 13107 } else { 0 },
        0,
        32,
        0,
        s["output_boost"].as_u64().unwrap_or(0) as u16,
    ];
    values
        .iter()
        .enumerate()
        .map(|(i, v)| packet(3, i as u8, 0, 0, *v))
        .collect()
}
#[derive(Default)]
pub struct Parser {
    buffer: Vec<u8>,
}
impl Parser {
    pub fn feed(&mut self, data: &[u8]) -> Vec<Value> {
        self.buffer.extend_from_slice(data);
        let mut out = Vec::new();
        let mut cursor = 0;
        while self.buffer.len() - cursor >= 2 {
            let b = &self.buffer[cursor..];
            if b[0] != 0xa5 || !(0x85..=0x88).contains(&b[1]) {
                cursor += 1;
                continue;
            }
            if b.len() < 16 {
                break;
            }
            if b[..16].iter().fold(0, |a, v| a ^ v) != 0 {
                cursor += 1;
                continue;
            }
            let u = |i| u16::from_le_bytes([b[i], b[i + 1]]);
            let mut v =
                json!({"result":b[2],"count":u(4),"crc":u(6),"token":u(8),"generation":u(10)});
            match b[1] {
                0x86 => {
                    v["table"] = json!(true);
                    v["available"] = json!(b[3] & 1 != 0);
                    v["two_frames"] = json!(b[3] & 2 != 0);
                    v["pair_capable"] = json!(b[12] & 128 != 0);
                    v["query_key"] = json!(32 + (b[12] & 31));
                    v["frame_position"] = json!(u(13));
                }
                0x87 => {
                    v["profile"] = json!(true);
                    v["key"] = json!(b[3]);
                    v["profile_version"] = json!(b[12]);
                }
                0x88 => {
                    v["pcm"] = json!(true);
                    v["available"] = json!(b[3] & 1 != 0);
                    v["metadata"] = json!(b[12]);
                }
                _ => {
                    v = json!({"flags":b[2],"voices":b[3],"oscillators":b[4],"cycles":u(5),"clips":u32::from_le_bytes(b[7..11].try_into().unwrap()),"samples":u32::from_le_bytes(b[11..15].try_into().unwrap())});
                }
            }
            out.push(v);
            cursor += 16;
        }
        self.buffer.drain(..cursor);
        out
    }
}
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Kind {
    Table,
    Pair,
    Pcm,
    Profiles,
}
#[derive(Clone, Copy, PartialEq, Debug)]
enum Stage {
    Probe,
    Begin,
    Block,
    Commit,
    PositionProbe,
    PositionWrite,
}
pub struct Transfer {
    pub kind: Kind,
    pub count: usize,
    pub done: bool,
    pub error: Option<String>,
    stage: Stage,
    data: Vec<u16>,
    meta: Vec<u16>,
    profiles: Vec<(u8, Vec<u16>)>,
    positions: Vec<(u8, u16)>,
    position_index: usize,
    expected: usize,
    token: u16,
    generation: u16,
    deadline: f64,
    query_at: f64,
}
fn n(v: &Value, k: &str) -> u64 {
    v[k].as_u64().unwrap_or(u64::MAX)
}
impl Transfer {
    pub fn activate(&mut self, now: f64) {
        self.deadline = now + 5.0;
        self.query_at = 0.0;
    }
    fn new(kind: Kind, now: f64, token: u16) -> Self {
        Self {
            kind,
            count: 0,
            done: false,
            error: None,
            stage: Stage::Probe,
            data: vec![],
            meta: vec![],
            profiles: vec![],
            positions: vec![],
            position_index: 0,
            expected: 0,
            token: token.max(1),
            generation: 0,
            deadline: now + if kind == Kind::Pcm { 5.0 } else { 3.0 },
            query_at: 0.0,
        }
    }
    pub fn table(frames: &[Vec<i16>], now: f64, token: u16) -> Result<Self> {
        if !(1..=2).contains(&frames.len()) || frames.iter().any(|f| f.len() != 1024) {
            return Err("波表需要一个或两个 1024 点周期".into());
        }
        let mut t = Self::new(
            if frames.len() == 2 {
                Kind::Pair
            } else {
                Kind::Table
            },
            now,
            token,
        );
        t.data = frames.iter().flatten().map(|v| *v as u16).collect();
        Ok(t)
    }
    pub fn pcm(meta: [u16; 4], samples: Vec<i16>, now: f64, token: u16) -> Result<Self> {
        if samples.len() != meta[0] as usize
            || !(512..=16384).contains(&samples.len())
            || meta[1] >= meta[2]
            || meta[2] > meta[0]
            || meta[2] - meta[1] < 512
            || meta[3] > 127
        {
            return Err("PCM 元数据无效".into());
        }
        let mut t = Self::new(Kind::Pcm, now, token);
        t.meta = meta.to_vec();
        t.data = samples.into_iter().map(|v| v as u16).collect();
        Ok(t)
    }
    pub fn profiles(profiles: &[(u8, Value)], now: f64, token: u16) -> Result<Self> {
        if profiles.is_empty()
            || profiles.len() > 32
            || profiles.iter().any(|(k, _)| !(32..64).contains(k))
        {
            return Err("无效按键配置".into());
        }
        let mut t = Self::new(Kind::Profiles, now, token);
        for (key, p) in profiles {
            t.profiles.push((*key, model::words(p)?));
        }
        if profiles
            .iter()
            .any(|(_, p)| p.get("frame_position").is_some())
        {
            t.positions = profiles
                .iter()
                .map(|(k, p)| {
                    (
                        *k,
                        (p["frame_position"].as_f64().unwrap_or(0.0) * 65535.0 / 100.0)
                            .round_ties_even() as u16,
                    )
                })
                .collect();
        }
        Ok(t)
    }
    fn ops(&self) -> (u8, u8, u8, u8, u8) {
        match self.kind {
            Kind::Table => (0x10, 0x11, 0x12, 0x13, 0x16),
            Kind::Pair => (0x40, 0x41, 0x42, 0x43, 0x16),
            Kind::Pcm => (0x30, 0x31, 0x32, 0x33, 0x36),
            Kind::Profiles => (0x20, 0x21, 0x22, 0x23, 0x27),
        }
    }
    fn refresh(&mut self, now: f64) {
        self.deadline = now + if self.kind == Kind::Pcm { 5.0 } else { 3.0 };
        self.query_at = now + 0.2;
    }
    pub fn accepts(&self, s: &Value) -> bool {
        if matches!(self.stage, Stage::PositionProbe | Stage::PositionWrite) {
            s["table"] == true
        } else {
            match self.kind {
                Kind::Table | Kind::Pair => s["table"] == true,
                Kind::Pcm => s["pcm"] == true,
                Kind::Profiles => s["profile"] == true,
            }
        }
    }
    fn fail(&mut self, message: &str, abort: bool) -> Vec<Frame> {
        self.error = Some(message.into());
        if abort {
            vec![command(self.ops().3)]
        } else {
            vec![]
        }
    }
    pub fn advance(&mut self, now: f64, status: Option<&Value>) -> Vec<Frame> {
        if self.done || self.error.is_some() {
            return vec![];
        }
        if now > self.deadline {
            return self.fail(
                "上传应答超时，最终状态未确认，请重新同步。",
                !matches!(
                    self.stage,
                    Stage::Probe | Stage::PositionProbe | Stage::PositionWrite
                ),
            );
        }
        let status = status.filter(|s| self.accepts(s));
        if matches!(self.stage, Stage::PositionProbe | Stage::PositionWrite) {
            return self.advance_position(now, status);
        }
        let (begin, data, commit, abort, query) = self.ops();
        let key = if self.kind == Kind::Profiles {
            self.profiles[self.count].0
        } else {
            0
        };
        if let Some(s) = status {
            if self.stage == Stage::Probe {
                if self.kind == Kind::Pair && s["pair_capable"] != true {
                    return self.fail(
                        "当前固件不支持双帧波表，请烧录 pair 版本；尚未发送资源数据。",
                        false,
                    );
                }
                if self.kind == Kind::Profiles && n(s, "profile_version") < 2 {
                    return self.fail("当前固件不支持高精度包络，请烧录 precision 版本。", true);
                }
                self.generation = n(s, "generation") as u16;
                self.stage = Stage::Begin;
                self.refresh(now);
                return vec![
                    packet(begin, key, 0, 0, self.token),
                    packet(query, key, 0, 0, 0),
                ];
            }
            if n(s, "token") != self.token as u64
                || (self.kind == Kind::Profiles && n(s, "key") != key as u64)
            {
                return vec![];
            }
            if n(s, "result") == 4 {
                self.error = Some("FPGA 拒绝上传（顺序、长度或 CRC 错误），请重传。".into());
                return vec![command(abort)];
            }
            if self.kind == Kind::Profiles {
                let words = &self.profiles[self.count].1;
                if self.stage == Stage::Begin && n(s, "result") == 1 && n(s, "count") == 0 {
                    let mut out: Vec<_> = words
                        .iter()
                        .enumerate()
                        .map(|(i, v)| packet(data, key, i as u8, 0, *v))
                        .collect();
                    out.extend([
                        packet(
                            commit,
                            key,
                            self.token as u8,
                            (self.token >> 8) as u8,
                            crc(words),
                        ),
                        packet(query, key, 0, 0, 0),
                    ]);
                    self.stage = Stage::Commit;
                    self.refresh(now);
                    return out;
                }
                if self.stage == Stage::Commit
                    && n(s, "result") == 3
                    && n(s, "count") == 18
                    && n(s, "crc") == crc(words) as u64
                    && n(s, "generation") == self.generation.wrapping_add(1) as u64
                {
                    self.count += 1;
                    if self.count == self.profiles.len() {
                        if self.positions.is_empty() {
                            self.done = true;
                            return vec![];
                        }
                        self.stage = Stage::PositionProbe;
                        self.deadline = now + 3.0;
                        self.query_at = 0.0;
                        return self.advance_position(now, None);
                    }
                    self.generation = n(s, "generation") as u16;
                    self.token = self.token % 65535 + 1;
                    self.stage = Stage::Begin;
                    self.refresh(now);
                    let key = self.profiles[self.count].0;
                    return vec![
                        packet(begin, key, 0, 0, self.token),
                        packet(query, key, 0, 0, 0),
                    ];
                }
            } else {
                if self.kind == Kind::Pcm
                    && self.stage == Stage::Begin
                    && n(s, "result") == 1
                    && n(s, "count") == 0
                    && n(s, "metadata") == 0
                {
                    let mut out: Vec<_> = self
                        .meta
                        .iter()
                        .enumerate()
                        .map(|(i, v)| packet(0x34, i as u8, 0, 0, *v))
                        .collect();
                    out.push(command(query));
                    self.stage = Stage::Block;
                    self.refresh(now);
                    return out;
                }
                if matches!(self.stage, Stage::Begin | Stage::Block)
                    && n(s, "result") == 1
                    && n(s, "count") == self.expected as u64
                    && (self.kind != Kind::Pcm || n(s, "metadata") == 4)
                {
                    let mut prefix = self.meta.clone();
                    prefix.extend_from_slice(&self.data[..self.expected]);
                    if n(s, "crc") != crc(&prefix) as u64 {
                        return self.fail("FPGA CRC 与电脑不一致，请重传。", true);
                    }
                    self.count = self.expected;
                    self.refresh(now);
                    if self.count == self.data.len() {
                        self.stage = Stage::Commit;
                        return vec![
                            packet(
                                commit,
                                self.token as u8,
                                (self.token >> 8) as u8,
                                0,
                                crc(&prefix),
                            ),
                            command(query),
                        ];
                    }
                    let end = (self.count + 32).min(self.data.len());
                    let mut out: Vec<_> = (self.count..end)
                        .map(|i| packet(data, i as u8, (i >> 8) as u8, 0, self.data[i]))
                        .collect();
                    out.push(command(query));
                    self.expected = end;
                    self.stage = Stage::Block;
                    return out;
                }
                if self.stage == Stage::Commit
                    && n(s, "result") == 3
                    && s["available"] == true
                    && n(s, "count") == self.data.len() as u64
                    && n(s, "generation") == self.generation.wrapping_add(1) as u64
                    && (self.kind != Kind::Pair || s["two_frames"] == true)
                {
                    let mut all = self.meta.clone();
                    all.extend_from_slice(&self.data);
                    if n(s, "crc") == crc(&all) as u64 {
                        self.done = true;
                        return vec![];
                    }
                }
            }
        }
        if now >= self.query_at {
            self.query_at = now + 0.2;
            return vec![packet(query, key, 0, 0, 0)];
        }
        vec![]
    }
    fn advance_position(&mut self, now: f64, status: Option<&Value>) -> Vec<Frame> {
        let (key, value) = self.positions[self.position_index];
        if let Some(s) = status {
            if self.stage == Stage::PositionProbe {
                if s["pair_capable"] != true {
                    if self.positions.iter().all(|(_, v)| *v == 0) {
                        self.done = true;
                    } else {
                        self.error = Some("逐键参数已上传，但当前固件不支持帧位置。".into());
                    }
                    return vec![];
                }
                self.stage = Stage::PositionWrite;
                self.refresh(now);
                return vec![packet(0x44, key, 0, 0, value), packet(0x46, key, 0, 0, 0)];
            }
            if n(s, "query_key") == key as u64 && n(s, "frame_position") == value as u64 {
                self.position_index += 1;
                if self.position_index == self.positions.len() {
                    self.done = true;
                    return vec![];
                }
                let (k, v) = self.positions[self.position_index];
                self.refresh(now);
                return vec![packet(0x44, k, 0, 0, v), packet(0x46, k, 0, 0, 0)];
            }
        }
        if now >= self.query_at {
            self.query_at = now + 0.2;
            return vec![if self.stage == Stage::PositionProbe {
                command(0x16)
            } else {
                packet(0x46, key, 0, 0, 0)
            }];
        }
        vec![]
    }
}
