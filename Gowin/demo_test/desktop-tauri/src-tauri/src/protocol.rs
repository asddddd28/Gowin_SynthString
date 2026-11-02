//! The existing FPGA wire contract. No browser or Python dependency.
use serde::{Deserialize, Serialize};

pub fn crc8(data: &[u8]) -> u8 {
    data.iter().fold(0, |mut crc, b| {
        crc ^= b;
        for _ in 0..8 {
            crc = (crc << 1) ^ if crc & 128 != 0 { 7 } else { 0 };
        }
        crc
    })
}
fn hex(s: &[u8]) -> Option<u64> {
    if s.is_empty()
        || s.len() > 16
        || !s
            .iter()
            .all(|c| c.is_ascii_digit() || (b'A'..=b'F').contains(c))
    {
        return None;
    }
    u64::from_str_radix(std::str::from_utf8(s).ok()?, 16).ok()
}
fn bytes(s: &[u8]) -> Option<Vec<u8>> {
    if s.len() % 2 != 0 {
        return None;
    }
    s.chunks(2).map(|p| Some(hex(p)? as u8)).collect()
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Board {
    pub seq: u8,
    pub result: u8,
    pub configured: bool,
    pub mode: u8,
    pub direction: u8,
    pub generation: u8,
    pub pressed: u32,
}
#[derive(Clone, Debug, Serialize)]
pub struct Game {
    pub game: u8,
    pub phase: u8,
    pub seconds: u8,
    pub reason: u8,
    pub score: u16,
    pub misses: u8,
    pub epoch: u8,
    pub colors: Vec<u8>,
}
#[derive(Clone, Debug, Serialize)]
pub struct Encoder {
    pub channel: u8,
    pub raw: u8,
    pub filtered: u8,
    pub q: i16,
    pub positive: u16,
    pub negative: u16,
    pub invalid: u16,
}
#[derive(Clone, Debug, Serialize)]
pub struct Joystick {
    pub sequence: u16,
    pub raw: u8,
    pub filtered: u8,
    pub presses: u16,
}
#[derive(Clone, Debug, Serialize)]
pub struct Pad {
    pub board: u8,
    pub sequence: u16,
    pub address: u8,
    pub error: u8,
    pub lines: u8,
    pub mask: u16,
    pub fault: bool,
    pub filtered: Vec<u16>,
    pub baseline: Vec<u16>,
    pub delta: Vec<i32>,
}
#[derive(Clone, Debug, Serialize)]
pub struct Guitar {
    pub board: u8,
    pub packet: u16,
    pub sample: u16,
    pub milliseconds: u32,
    pub flags: u8,
    pub mask: u8,
    pub x: u16,
    pub y: u16,
    pub dropped: u16,
}
#[derive(Clone, Debug, Serialize)]
pub struct Identity {
    pub capabilities: u16,
    pub build: u16,
}
#[derive(Clone, Debug, Serialize)]
pub struct Buttons {
    pub sequence: u16,
    pub raw: u8,
    pub filtered: u8,
    pub presses: [u16; 6],
    pub releases: [u16; 6],
    pub edges: [u16; 6],
}
#[derive(Clone, Debug)]
pub enum Frame {
    Key(usize, u16),
    Board(Board),
    Game(Game),
    Encoder(Encoder),
    Joystick(Joystick),
    Pad(Pad),
    Guitar(Guitar),
    Identity(Identity),
    Buttons(Buttons),
}
impl Frame {
    pub fn kind(&self) -> usize {
        match self {
            Self::Key(..) => 0,
            Self::Board(_) => 1,
            Self::Game(_) => 2,
            Self::Encoder(_) => 3,
            Self::Joystick(_) => 4,
            Self::Pad(_) => 5,
            Self::Guitar(_) => 6,
            Self::Identity(_) => 7,
            Self::Buttons(_) => 8,
        }
    }
}

pub fn decode(s: &[u8]) -> Option<Frame> {
    match *s.first()? {
        b'B' if s.len() == 87 && &s[..2] == b"B1" && s[82] == b'*' && &s[85..] == b"\r\n" => {
            if crc8(&s[..82]) != hex(&s[83..85])? as u8 { return None; }
            let raw = hex(&s[6..8])? as u8;
            let filtered = hex(&s[8..10])? as u8;
            if raw > 63 || filtered > 63 { return None; }
            let mut presses = [0; 6];
            let mut releases = [0; 6];
            let mut edges = [0; 6];
            for i in 0..6 {
                presses[i] = hex(&s[10+i*4..14+i*4])? as u16;
                releases[i] = hex(&s[34+i*4..38+i*4])? as u16;
                edges[i] = hex(&s[58+i*4..62+i*4])? as u16;
            }
            Some(Frame::Buttons(Buttons { sequence: hex(&s[2..6])? as u16, raw, filtered, presses, releases, edges }))
        }
        b'K' if s.len() == 9 && s[3] == b':' && &s[7..] == b"\r\n" => {
            if !s[1..3].iter().all(u8::is_ascii_digit) {
                return None;
            }
            let k = std::str::from_utf8(&s[1..3]).ok()?.parse::<usize>().ok()?;
            if !(1..=32).contains(&k) {
                return None;
            }
            Some(Frame::Key(k - 1, hex(&s[4..7])? as u16))
        }
        b'@' if s.len() == 23 && s[19] == b'*' && s[22] == b'\n' => {
            let r = bytes(&s[1..19])?;
            if crc8(&r) != hex(&s[20..22])? as u8 || r[2] > 1 || r[3] >> 4 > 6 || r[3] & 15 > 1 {
                return None;
            }
            Some(Frame::Board(Board {
                seq: r[0],
                result: r[1],
                configured: r[2] == 1,
                mode: r[3] >> 4,
                direction: r[3] & 15,
                generation: r[4],
                pressed: u32::from_be_bytes(r[5..9].try_into().ok()?),
            }))
        }
        b'#' if s.len() == 37 && s[33] == b'*' && s[36] == b'\n' => {
            let r = bytes(&s[1..33])?;
            if crc8(&r) != hex(&s[34..36])? as u8 || r[0] > 3 || r[1] > 4 || r[3] > 6 {
                return None;
            }
            let px = u64::from_be_bytes(r[8..16].try_into().ok()?);
            Some(Frame::Game(Game {
                game: r[0],
                phase: r[1],
                seconds: r[2],
                reason: r[3],
                score: u16::from_be_bytes([r[4], r[5]]),
                misses: r[6],
                epoch: r[7],
                colors: (0..32).map(|i| ((px >> (2 * i)) & 3) as u8).collect(),
            }))
        }
        b'E' if s.len() == 34
            && (b'1'..=b'5').contains(&s[1])
            && &s[2..4] == b" A"
            && &s[5..7] == b" F"
            && &s[8..10] == b" Q"
            && &s[14..16] == b" P"
            && &s[20..22] == b" N"
            && &s[26..28] == b" X"
            && &s[32..] == b"\r\n" =>
        {
            let raw = hex(&s[4..5])? as u8;
            let filtered = hex(&s[7..8])? as u8;
            let q = hex(&s[10..14])? as u16;
            let p = hex(&s[16..20])? as u16;
            let n = hex(&s[22..26])? as u16;
            if raw > 3 || filtered > 3 || q != p.wrapping_sub(n) {
                return None;
            }
            Some(Frame::Encoder(Encoder {
                channel: s[1] - b'0',
                raw,
                filtered,
                q: q as i16,
                positive: p,
                negative: n,
                invalid: hex(&s[28..32])? as u16,
            }))
        }
        b'J' if s.len() == 21
            && &s[5..7] == b" R"
            && &s[9..11] == b" F"
            && &s[13..15] == b" P"
            && &s[19..] == b"\r\n" =>
        {
            let raw = hex(&s[7..9])? as u8;
            let filtered = hex(&s[11..13])? as u8;
            if raw > 31 || filtered > 31 {
                return None;
            }
            Some(Frame::Joystick(Joystick {
                sequence: hex(&s[1..5])? as u16,
                raw,
                filtered,
                presses: hex(&s[15..19])? as u16,
            }))
        }
        b'T' if s.len() == 100
            && (b'1'..=b'2').contains(&s[1])
            && s[95] == b'*'
            && &s[98..] == b"\r\n" =>
        {
            if crc8(&s[..95]) != hex(&s[96..98])? as u8 {
                return None;
            }
            let address = hex(&s[6..8])? as u8;
            let error = hex(&s[8..10])? as u8;
            let lines = hex(&s[10..11])? as u8;
            if !(0x5a..=0x5d).contains(&address) || error > 7 || lines > 7 {
                return None;
            }
            let r = bytes(&s[11..95])?;
            let filtered: Vec<_> = (0..12)
                .map(|i| u16::from_le_bytes([r[4 + 2 * i], r[5 + 2 * i]]))
                .collect();
            if error == 0 && filtered.iter().any(|v| *v > 1023) {
                return None;
            }
            let baseline: Vec<_> = r[30..42].iter().map(|v| u16::from(*v) * 4).collect();
            let delta = baseline
                .iter()
                .zip(&filtered)
                .map(|(b, f)| i32::from(*b) - i32::from(*f))
                .collect();
            Some(Frame::Pad(Pad {
                board: s[1] - b'0',
                sequence: hex(&s[2..6])? as u16,
                address,
                error,
                lines,
                mask: u16::from_le_bytes([r[0], r[1]]) & 4095,
                fault: r[1] & 128 != 0 || r[2] != 0 || r[3] & 0xcf != 0,
                filtered,
                baseline,
                delta,
            }))
        }
        b'G' if s.len() == 37
            && &s[..2] == b"G1"
            && (b'1'..=b'2').contains(&s[2])
            && s[32] == b'*'
            && &s[35..] == b"\r\n" =>
        {
            if crc8(&s[..32]) != hex(&s[33..35])? as u8 {
                return None;
            }
            let r = Guitar {
                board: s[2] - b'0',
                packet: hex(&s[3..7])? as u16,
                sample: hex(&s[7..11])? as u16,
                milliseconds: hex(&s[11..19])? as u32,
                flags: hex(&s[19..20])? as u8,
                mask: hex(&s[20..22])? as u8,
                x: hex(&s[22..25])? as u16,
                y: hex(&s[25..28])? as u16,
                dropped: hex(&s[28..32])? as u16,
            };
            if r.mask > 63 || r.x > 1023 || r.y > 1023 || (r.mask != 0 && r.flags & 3 != 3) {
                return None;
            }
            Some(Frame::Guitar(r))
        }
        b'H' if s.len() == 15 && &s[..2] == b"H1" && s[10] == b'*' && &s[13..] == b"\r\n" => {
            if crc8(&s[..10]) != hex(&s[11..13])? as u8 {
                return None;
            }
            let capabilities = hex(&s[2..6])? as u16;
            let build = hex(&s[6..10])? as u16;
            if !matches!(capabilities, 127 | 255) || build >> 8 != 1 {
                return None;
            }
            Some(Frame::Identity(Identity {
                capabilities,
                build,
            }))
        }
        _ => None,
    }
}

#[derive(Default)]
pub struct Parser {
    buffer: Vec<u8>,
    saw_line_end: bool,
    pub counts: [u64; 9],
    pub errors: u64,
    pub discarded: u64,
}
impl Parser {
    pub fn feed(&mut self, data: &[u8]) -> Vec<Frame> {
        let mut frames = Vec::new();
        for b in data {
            self.buffer.push(*b);
            if *b == b'\n' {
                let mut found = false;
                for start in 0..self.buffer.len() {
                    if let Some(f) = decode(&self.buffer[start..]) {
                        self.discarded += start as u64;
                        self.counts[f.kind()] += 1;
                        frames.push(f);
                        found = true;
                        break;
                    }
                }
                if !found {
                    // Opening a live UART may start in the middle of a frame.
                    // Account for that initial fragment as discarded bytes, not a bad full frame.
                    if self.saw_line_end {
                        self.errors += 1;
                    }
                    self.discarded += self.buffer.len() as u64;
                }
                self.saw_line_end = true;
                self.buffer.clear();
            } else if self.buffer.len() > 512 {
                self.discarded += self.buffer.len() as u64;
                self.buffer.clear();
                self.errors += 1;
            }
        }
        frames
    }
}

#[derive(Clone, Debug, Default)]
pub struct Command {
    pub code: u8,
    pub key: u8,
    pub rest: u16,
    pub bottom: u16,
    pub press: u16,
    pub release: u16,
    pub mode: u8,
    pub direction: u8,
}
impl Command {
    pub fn new(code: u8) -> Self {
        Self {
            code,
            ..Self::default()
        }
    }
    pub fn encode(&self, seq: u8) -> Vec<u8> {
        let mut n = 0u128;
        for (v, bits) in [
            (seq as u128, 8),
            (self.code as u128, 8),
            (self.key as u128, 8),
            (self.rest as u128, 12),
            (self.bottom as u128, 12),
            (self.press as u128, 12),
            (self.release as u128, 12),
            (self.mode as u128, 4),
            (self.direction as u128, 4),
        ] {
            n = (n << bits) | v;
        }
        let raw = n.to_be_bytes();
        format!("!{n:020X}*{:02X}\n", crc8(&raw[6..])).into_bytes()
    }
}
