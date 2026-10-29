//! Serial IO has its own bounded worker so disk work and UI polling cannot starve heartbeats.
use crate::{
    Result,
    protocol::{self, Frame, Kind, Parser, Transfer},
};
use serde_json::{Value, json};
use std::{
    collections::BTreeSet,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc::{self, Receiver, SyncSender, TryRecvError},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};
pub enum Event {
    Status(Value),
    PcmStatus(bool),
    Progress(usize),
    Done(Kind),
    TransferError(String),
    Error(String),
    NotesReleased,
}
pub trait Link: Send {
    fn send(&mut self, frames: Vec<Frame>) -> bool;
    fn upload(&mut self, transfer: Transfer) -> bool;
    fn panic(&mut self);
    fn poll(&mut self) -> Vec<Event>;
    fn close(&mut self);
    fn touch_ui(&self) {}
    #[cfg(any(test, feature = "test-harness"))]
    fn recorded(&self) -> Vec<Frame> {
        vec![]
    }
}
enum Command {
    Frames(Vec<Frame>),
    Upload(Transfer),
    Panic,
}
pub fn ports() -> Result<Value> {
    let ports = serialport::available_ports().map_err(|e| e.to_string())?;
    Ok(json!(
        ports
            .into_iter()
            .map(|p| {
                let description = match p.port_type {
                    serialport::SerialPortType::UsbPort(info) => info
                        .product
                        .unwrap_or_else(|| format!("USB {:04X}:{:04X}", info.vid, info.pid)),
                    _ => p.port_name.clone(),
                };
                json!({"device":p.port_name,"description":description})
            })
            .collect::<Vec<_>>()
    ))
}
pub struct SerialLink {
    sender: SyncSender<Command>,
    events: Receiver<Event>,
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
    disconnected: bool,
    origin: Instant,
    last_ui: Arc<AtomicU64>,
}
impl SerialLink {
    pub fn open(name: &str) -> Result<Self> {
        let mut port = serialport::new(name, 115200)
            .data_bits(serialport::DataBits::Eight)
            .parity(serialport::Parity::None)
            .stop_bits(serialport::StopBits::One)
            .flow_control(serialport::FlowControl::None)
            .dtr_on_open(false)
            .timeout(Duration::from_millis(200))
            .open()
            .map_err(|e| e.to_string())?;
        port.write_request_to_send(false)
            .map_err(|e| e.to_string())?;
        port.clear(serialport::ClearBuffer::Input)
            .map_err(|e| e.to_string())?;
        let (sender, rx) = mpsc::sync_channel(32);
        let (tx, events) = mpsc::sync_channel(1024);
        let stop = Arc::new(AtomicBool::new(false));
        let stop_thread = stop.clone();
        let origin = Instant::now();
        let last_ui = Arc::new(AtomicU64::new(0));
        let worker_ui = last_ui.clone();
        let thread = thread::Builder::new()
            .name("tang-uart".into())
            .spawn(move || {
                let outcome = run(port.as_mut(), rx, &tx, &stop_thread, origin, &worker_ui);
                // Best effort abort and all-notes-off, including the pair-transfer opcode.
                let _ = write_frames(
                    port.as_mut(),
                    &[
                        protocol::command(0x33),
                        protocol::command(0x23),
                        protocol::command(0x13),
                        protocol::command(0x43),
                        protocol::command(4),
                    ],
                );
                if let Err(error) = outcome {
                    let _ = tx.try_send(Event::Error(error));
                }
            })
            .map_err(|e| e.to_string())?;
        Ok(Self {
            sender,
            events,
            stop,
            thread: Some(thread),
            disconnected: false,
            origin,
            last_ui,
        })
    }
    fn enqueue(&mut self, c: Command) -> bool {
        if self.stop.load(Ordering::Acquire) {
            return false;
        }
        if self.sender.try_send(c).is_err() {
            self.stop.store(true, Ordering::Release);
            return false;
        }
        true
    }
}
impl Link for SerialLink {
    fn touch_ui(&self) {
        self.last_ui
            .store(self.origin.elapsed().as_millis() as u64, Ordering::Release);
    }
    fn send(&mut self, frames: Vec<Frame>) -> bool {
        if frames.len() > 256 {
            return false;
        }
        self.enqueue(Command::Frames(frames))
    }
    fn upload(&mut self, t: Transfer) -> bool {
        self.enqueue(Command::Upload(t))
    }
    fn panic(&mut self) {
        self.enqueue(Command::Panic);
    }
    fn poll(&mut self) -> Vec<Event> {
        let mut out = Vec::new();
        for _ in 0..256 {
            match self.events.try_recv() {
                Ok(e) => out.push(e),
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    if !self.disconnected {
                        out.push(Event::Error(
                            "串口工作线程已关闭，连接或队列不可用。".into(),
                        ));
                        self.disconnected = true;
                    }
                    break;
                }
            }
        }
        out
    }
    fn close(&mut self) {
        self.stop.store(true, Ordering::Release);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}
impl Drop for SerialLink {
    fn drop(&mut self) {
        self.close();
    }
}
fn write_frames(port: &mut dyn serialport::SerialPort, frames: &[Frame]) -> Result<()> {
    let bytes: Vec<_> = frames.iter().flatten().copied().collect();
    if !bytes.is_empty() {
        port.write_all(&bytes)
            .map_err(|e| format!("串口写入失败：{e}"))?;
    }
    Ok(())
}
fn emit(tx: &SyncSender<Event>, e: Event) -> Result<()> {
    tx.try_send(e)
        .map_err(|_| "串口事件队列不可用；连接已停止，需重新连接。".into())
}
#[derive(Default)]
struct NoteGuard {
    held: BTreeSet<u8>,
}
impl NoteGuard {
    fn observe(&mut self, frames: &[Frame]) {
        for f in frames {
            match f[1] {
                1 => {
                    self.held.insert(f[2]);
                }
                2 => {
                    self.held.remove(&f[2]);
                }
                4 => self.held.clear(),
                _ => {}
            }
        }
    }
    fn expired(&mut self, now: u64, last_ui: u64) -> Vec<Frame> {
        if now.saturating_sub(last_ui) <= 1500 {
            return vec![];
        }
        let frames = self
            .held
            .iter()
            .map(|id| protocol::packet(2, *id, 0, 0, 0))
            .collect();
        self.held.clear();
        frames
    }
}
fn run(
    port: &mut dyn serialport::SerialPort,
    rx: Receiver<Command>,
    tx: &SyncSender<Event>,
    stop: &AtomicBool,
    origin: Instant,
    last_ui: &AtomicU64,
) -> Result<()> {
    let mut last_reply = 0.0;
    let mut heartbeat = 0.0;
    let mut parser = Parser::default();
    let mut transfer: Option<Transfer> = None;
    let mut bytes = [0u8; 512];
    let mut notes = NoteGuard::default();
    while !stop.load(Ordering::Acquire) {
        let now = origin.elapsed().as_secs_f64();
        for _ in 0..8 {
            match rx.try_recv() {
                Ok(Command::Frames(frames)) => {
                    write_frames(port, &frames)?;
                    notes.observe(&frames);
                }
                Ok(Command::Panic) => {
                    write_frames(port, &[protocol::command(4)])?;
                    notes.held.clear();
                }
                Ok(Command::Upload(mut t)) => {
                    if transfer.is_some() {
                        emit(tx, Event::TransferError("已有传输正在进行。".into()))?;
                    } else {
                        t.activate(now);
                        transfer = Some(t);
                    }
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => return Ok(()),
            }
        }
        // Independent of the engine thread: slow file IO cannot keep held notes alive.
        let releases = notes.expired(
            origin.elapsed().as_millis() as u64,
            last_ui.load(Ordering::Acquire),
        );
        if !releases.is_empty() {
            write_frames(port, &releases)?;
            emit(tx, Event::NotesReleased)?;
        }
        if now >= heartbeat {
            write_frames(port, &[protocol::command(5)])?;
            heartbeat = now + 0.5;
        }
        let available = port.bytes_to_read().map_err(|e| e.to_string())? as usize;
        if available > 0 {
            let len = available.min(bytes.len());
            let count = port
                .read(&mut bytes[..len])
                .map_err(|e| format!("串口读取失败：{e}"))?;
            for status in parser.feed(&bytes[..count]) {
                last_reply = now;
                if status.get("flags").is_some() {
                    emit(tx, Event::Status(status.clone()))?;
                }
                if status["pcm"] == true {
                    emit(tx, Event::PcmStatus(status["available"] == true))?;
                }
                if let Some(t) = transfer.as_mut()
                    && t.accepts(&status)
                {
                    write_frames(port, &t.advance(now, Some(&status)))?;
                }
            }
        }
        if let Some(t) = transfer.as_mut() {
            write_frames(port, &t.advance(now, None))?;
            emit(tx, Event::Progress(t.count))?;
            if let Some(error) = t.error.take() {
                emit(tx, Event::TransferError(error))?;
                transfer = None;
            } else if t.done {
                emit(tx, Event::Done(t.kind))?;
                transfer = None;
            }
        }
        if now - last_reply > 3.0 {
            return Err("FPGA 状态响应超时，请检查连接。".into());
        }
        thread::sleep(Duration::from_millis(5));
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn serial_watchdog_expires_even_without_engine_ticks() {
        let mut notes = NoteGuard::default();
        notes.observe(&[
            protocol::packet(1, 32, 60, 96, 0),
            protocol::packet(1, 33, 61, 96, 0),
        ]);
        notes.observe(&[protocol::packet(2, 33, 0, 0, 0)]);
        assert!(notes.expired(1500, 0).is_empty());
        assert_eq!(
            notes.expired(1501, 0),
            vec![protocol::packet(2, 32, 0, 0, 0)]
        );
        assert!(notes.expired(2000, 0).is_empty());
        notes.observe(&[protocol::packet(1, 32, 60, 96, 0), protocol::command(4)]);
        assert!(notes.expired(3000, 0).is_empty());
    }
}
#[cfg(any(test, feature = "test-harness"))]
#[derive(Default)]
pub struct RecordingLink {
    pub frames: Vec<Frame>,
    pub transfers: Vec<Transfer>,
}
#[cfg(any(test, feature = "test-harness"))]
impl Link for RecordingLink {
    fn send(&mut self, f: Vec<Frame>) -> bool {
        self.frames.extend(f);
        true
    }
    fn upload(&mut self, t: Transfer) -> bool {
        self.transfers.push(t);
        true
    }
    fn panic(&mut self) {
        self.frames.push(protocol::command(4));
    }
    fn poll(&mut self) -> Vec<Event> {
        vec![]
    }
    fn close(&mut self) {}
    fn recorded(&self) -> Vec<Frame> {
        self.frames.clone()
    }
}
