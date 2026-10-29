//! Native MIDI input only. Callback work is bounded and never performs serial IO.
use crate::Result;
use midir::{Ignore, MidiInput, MidiInputConnection};
use serde_json::{Value, json};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
    mpsc::{self, Receiver},
};
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Message {
    On { channel: u8, note: u8, velocity: u8 },
    Off { channel: u8, note: u8 },
    Control { channel: u8, cc: u8, value: u8 },
}
pub fn decode(data: &[u8]) -> Option<Message> {
    if data.len() != 3 || data[1] > 127 || data[2] > 127 {
        return None;
    }
    let channel = data[0] & 15;
    let note = data[1];
    let velocity = data[2];
    match data[0] & 0xf0 {
        0x90 if velocity > 0 => Some(Message::On {
            channel,
            note,
            velocity,
        }),
        0x80 | 0x90 => Some(Message::Off { channel, note }),
        0xb0 => Some(Message::Control {
            channel,
            cc: note,
            value: velocity,
        }),
        _ => None,
    }
}
fn input() -> Result<MidiInput> {
    MidiInput::new("Tang Synth Studio").map_err(|e| format!("MIDI 初始化失败：{e}"))
}
pub fn ports() -> Result<Value> {
    let input = input()?;
    Ok(json!(input.ports().iter().enumerate().map(|(i,p)|json!({"id":i,"name":input.port_name(p).unwrap_or_else(|_|format!("MIDI {i}"))})).collect::<Vec<_>>()))
}
pub struct Connection {
    _connection: MidiInputConnection<()>,
    events: Receiver<Message>,
    overflow: Arc<AtomicBool>,
    pub name: String,
}
impl Connection {
    pub fn open(id: usize, name: &str) -> Result<Self> {
        let mut input = input()?;
        input.ignore(Ignore::None);
        let ports = input.ports();
        let port = ports.get(id).ok_or("MIDI 端口已变化，请刷新列表")?;
        let actual = input.port_name(port).map_err(|e| e.to_string())?;
        if actual != name {
            return Err("MIDI 端口已变化，请刷新列表".into());
        }
        let (tx, events) = mpsc::sync_channel(1024);
        let overflow = Arc::new(AtomicBool::new(false));
        let over = overflow.clone();
        let connection = input
            .connect(
                port,
                "Tang performance",
                move |_, data, _| {
                    if let Some(message) = decode(data)
                        && tx.try_send(message).is_err()
                    {
                        over.store(true, Ordering::Release);
                    }
                },
                (),
            )
            .map_err(|e| format!("MIDI 连接失败：{e}"))?;
        Ok(Self {
            _connection: connection,
            events,
            overflow,
            name: actual,
        })
    }
    pub fn poll(&self) -> Result<Vec<Message>> {
        if self.overflow.swap(false, Ordering::AcqRel) {
            return Err("MIDI 输入过载，已停止演奏，请重新连接。".into());
        }
        Ok(self.events.try_iter().take(512).collect())
    }
    pub fn present(&self) -> Result<bool> {
        Ok(ports()?
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["name"] == self.name))
    }
}
