//! Native protocol-5 session for the resident FPGA voice engine.
//! A timed-out request remains durable and is retried byte-for-byte after reconnect.
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, io::{Read, Write}, path::PathBuf, sync::{Arc, Mutex}, time::{Duration, Instant, SystemTime, UNIX_EPOCH}};
use tauri::Manager;
#[path="voice_native.rs"]
pub mod native;
pub use native::{NativePatch,compile_native};
#[path="voice_workspace.rs"]
mod workspace;
#[path="voice_hdmi.rs"]
mod hdmi;
#[path="voice_keyboard.rs"]
mod keyboard;
use keyboard::{Keyboard,Profile as KeyboardProfile};
#[path="voice_filter.rs"]
mod filter;
use filter::{Filter,Profile as FilterProfile};
#[path="voice_touch.rs"]
mod touch;
use touch::{Touch,Profile as TouchProfile};
#[path="voice_sequencer.rs"]
mod sequencer;
use sequencer::Sequencer;
#[path="voice_storage.rs"]
mod storage;
use storage::Storage;
#[path="voice_storage_patch.rs"]
mod storage_patch;
use hdmi::Hdmi;
use workspace::{KeyMapping,MonitorView,default_keys};

const UNITY: u32 = 1 << 26;
const RATE: f64 = 50_000_000.0 / 1024.0;
const ABI: u32 = 0x0001_0005;
const BANK: &str = include_str!("../assets/fm1-library.json");

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct Operator {
    pub output: u8, pub rates: [u8; 4], pub levels: [u8; 4],
    pub ratio: Option<f64>, pub fixed_hz: Option<f64>,
}
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct Command { pub opcode: u8, pub address: u8, pub words: Vec<u32> }
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct Preset { pub program: u8, pub name: String, pub algorithm: u8, pub operators: Vec<Operator>, pub commands: Vec<Command> }
#[derive(Clone, Serialize, Deserialize)]
pub struct Library { pub presets: Vec<Preset>, pub library: Vec<serde_json::Value>, pub room: Vec<Command>, pub dry: Vec<Command> }
pub fn library() -> Library { serde_json::from_str(BANK).expect("compiled FM1 bank") }

pub fn port_catalog() -> Result<serde_json::Value,String> {
    Ok(serde_json::Value::Array(serialport::available_ports().map_err(|e|e.to_string())?.into_iter().map(|p|{
        let (description,recommended)=match p.port_type {
            serialport::SerialPortType::UsbPort(u)=>(format!("{} · {:04X}:{:04X}",u.product.unwrap_or_else(||"USB Serial".into()),u.vid,u.pid),u.vid==0x0403&&u.pid==0x6010),
            _=>("Serial".into(),false),
        };
        serde_json::json!({"name":p.port_name,"description":description,"recommended":recommended})
    }).collect()))
}

#[derive(Clone,Default,Serialize)]
pub struct SerialDiagnostics {
    last_wire_ms:u128, max_wire_ms:u128, last_request_ms:u128, max_request_ms:u128,
    timeout_attempts:u64, corrupt_frames:u64, unmatched_frames:u64,
}

fn fx_commands(available: bool, room: bool) -> Result<Vec<Command>, String> {
    if !available {
        return if room { Err("当前固件未编译 FX，仅支持干声".into()) } else { Ok(Vec::new()) };
    }
    Ok(if room { library().room } else { library().dry })
}

#[derive(Clone, Default, Serialize, Deserialize, Debug)]
pub struct Slot { pub program: Option<u8>, pub revision: u32, pub operators: Vec<Operator>, #[serde(default)] pub native: Option<NativePatch>, #[serde(default)] pub snapshot:Option<storage_patch::HardwarePatch> }
#[derive(Clone, Serialize, Deserialize)]
struct WaveTransfer { name:String, samples:Vec<i16>, next:usize, stopped:bool, #[serde(default)] morph:f64, #[serde(default)] busy_recoveries:u32 }
#[derive(Clone, Serialize)]
struct WaveStatus { name:String, written:usize, total:usize, busy_recoveries:u32 }
#[derive(Clone, Serialize, Deserialize, Debug)]
struct Note { id: u32, slot: u8, note: u8, velocity: u8 }
#[derive(Clone, Serialize, Deserialize, Debug)]
enum Effect {
    None, Slot { slot: u8, value: Slot }, On { token: String, note: Note },
    Off { token: String }, Control { volume: f64, sustain: bool, panic: bool },
    WaveStopped, WaveAdvance { next:usize }, WaveFinished,
    Key { key:u8,value:KeyMapping },
    Keyboard { profile:KeyboardProfile },
    Filter {profile:FilterProfile},
    Touch {profile:TouchProfile},
}
#[derive(Clone, Serialize, Deserialize, Debug)]
struct Pending { raw: Vec<u8>, effect: Effect }
#[derive(Clone, Serialize, Deserialize)]
struct Saved {
    next_sequence: u32, next_note: u32, pending: Option<Pending>, slots: [Slot; 4],
    #[serde(default="default_keys")] keys:Vec<KeyMapping>,
    #[serde(default)] keyboard:Option<KeyboardProfile>,
    #[serde(default)] filter:Option<FilterProfile>,
    #[serde(default)] touch:Option<TouchProfile>,
    notes: BTreeMap<String, Note>, volume: f64, sustain: bool,
    #[serde(default)] wave:Option<WaveTransfer>,
    #[serde(default)] wave_name:Option<String>,
    #[serde(default)] wave_morph:f64,
}
impl Default for Saved {
    fn default() -> Self { Self { next_sequence: 0, next_note: 1, pending: None, slots: Default::default(),keyboard:None,filter:None,touch:None,keys:default_keys(), notes: BTreeMap::new(), volume: 0.5, sustain: false,wave:None,wave_name:None,wave_morph:0. } }
}

#[derive(Clone, Default, Serialize)]
pub struct Telemetry {
    flags: u32, pressed: u32, frames: u32, underruns: u16, bad_packets: u16,
    active: u32, overruns: u32, cycles: u32, pcm_dropped: u32,
    fx_clips: u32, fx_dropped: u32, fx_cycles: u32,
}
#[derive(Clone, Serialize)]
pub struct View {
    connected: bool, port: Option<String>, abi: Option<u32>, pending: bool,
    pub fx_available: bool,
    keys:Vec<KeyMapping>,monitor:MonitorView,hdmi:Hdmi,keyboard:Keyboard,filter:Filter,touch:Touch,sequencer:Sequencer,storage:Storage,
    serial: SerialDiagnostics,
    slots: [Slot; 4], volume: f64, sustain: bool, held: Vec<String>,
    telemetry: Telemetry, age_ms: Option<u128>, packets: u64, retries: u64, error: String,
    wave_transfer:Option<WaveStatus>,wave_name:Option<String>,wave_morph:f64,
}
pub struct Engine {
    port: Option<Box<dyn serialport::SerialPort>>, name: Option<String>, root: PathBuf,
    saved: Saved, abi: Option<u32>, telemetry: Telemetry, received: Option<Instant>,
    poll_index: usize, packets: u64, retries: u64, error: String,
    fx_available: bool,
    monitor:MonitorView,capture_chunk:Option<u8>,capture_samples:Vec<i16>,
    serial: SerialDiagnostics,
    last_engine_status:Option<u8>,
    hdmi:Hdmi,keyboard:Keyboard,filter:Filter,touch:Touch,sequencer:Sequencer,storage:Storage,
}
pub type State = Arc<Mutex<Engine>>;

pub fn crc16(data: &[u8]) -> u16 {
    let mut crc = 0xffffu16;
    for byte in data { crc ^= (*byte as u16) << 8; for _ in 0..8 { crc = if crc & 0x8000 != 0 { (crc << 1) ^ 0x1021 } else { crc << 1 }; } }
    crc
}
pub fn packet(sequence: u32, kind: u8, opcode: u8, address: u8, words: &[u32]) -> Result<Vec<u8>, String> {
    if words.len() > 10 || kind > 3 { return Err("请求长度或类型越界".into()); }
    let mut raw = vec![0u8; 52]; raw[..4].copy_from_slice(&[0x53, 0x59, 5, kind]);
    raw[4..8].copy_from_slice(&sequence.to_le_bytes()); raw[8] = opcode; raw[9] = address;
    for (i, word) in words.iter().enumerate() { raw[10+i*4..14+i*4].copy_from_slice(&word.to_le_bytes()); }
    let crc = crc16(&raw[..50]); raw[50..].copy_from_slice(&crc.to_le_bytes()); Ok(raw)
}
fn u32_at(raw: &[u8], offset: usize) -> u32 { u32::from_le_bytes(raw[offset..offset+4].try_into().unwrap()) }
fn matching_response(data: &[u8], request: &[u8]) -> bool {
    data.len() == 32 && data[..3] == [0x53,0x52,5] &&
    crc16(&data[..30]) == u16::from_le_bytes([data[30],data[31]]) &&
    data[3..8] == request[3..8] && data[25] == request[8] && data[26] == request[9]
}
fn scale_level(value: u8) -> Result<u32, String> {
    const LOW: [u32;20] = [0,5,9,13,17,20,23,25,27,29,31,33,35,37,39,41,42,43,45,46];
    match value { 0..=19 => Ok(LOW[value as usize]), 20..=99 => Ok(value as u32 + 28), _ => Err("DX电平必须为0..99".into()) }
}
pub fn compile(program: u8, slot: u8, revision: u32, operators: Option<Vec<Operator>>) -> Result<(Vec<Command>,Slot),String> {
    if slot > 3 || revision == 0 { return Err("音色槽或版本越界".into()); }
    let preset = library().presets.into_iter().find(|p| p.program == program).ok_or("此音色尚未完成硬件适配")?;
    let ops = operators.unwrap_or(preset.operators);
    if ops.len() != 6 { return Err("需要6个算子".into()); }
    let mut commands = preset.commands;
    commands[0].address = slot; commands[0].words[0] = revision;
    for (i,op) in ops.iter().enumerate() {
        if op.rates.iter().any(|r| *r > 99) || op.levels[3] != 0 { return Err("速率必须为0..99，当前释放目标必须为0".into()); }
        let core = &mut commands[1+i*2]; core.address = slot*8+i as u8;
        let frequency = match (op.ratio,op.fixed_hz) {
            (Some(r),None) if r.is_finite() && (0.0..=64.0).contains(&r) => { core.words[4] &= !(1<<13); (r*65536.0).round() as u32 },
            (None,Some(f)) if f.is_finite() && (0.0..RATE/2.0).contains(&f) => { core.words[4] |= 1<<13; (f*4294967296.0/RATE).round() as u32 },
            _ => return Err("频率必须选择有效的比率或固定频率".into()),
        };
        core.words[0] = frequency;
        core.words[4] = (core.words[4] & !(127<<16)) | (scale_level(op.output)?<<16);
        if op.output == 0 { core.words[4] &= !(1<<12); } else { core.words[4] |= 1<<12; }
        let eg = &mut commands[2+i*2]; eg.address = slot*8+i as u8;
        for n in 0..4 { eg.words[n] = (scale_level(op.levels[n])? >> 1)<<6; eg.words[n+4] = (op.rates[n] as u32*41)>>6; }
    }
    commands.last_mut().unwrap().address = slot;
    Ok((commands,Slot { program:Some(program),revision,operators:ops,native:None,snapshot:None }))
}

impl Engine {
    pub fn new(root: PathBuf) -> Self { Self { port:None,name:None,root,saved:Saved::default(),abi:None,telemetry:Telemetry::default(),received:None,poll_index:0,packets:0,retries:0,error:String::new(),fx_available:false,monitor:MonitorView::default(),capture_chunk:None,capture_samples:Vec::new(),serial:SerialDiagnostics::default(),last_engine_status:None,hdmi:Hdmi::default(),keyboard:Keyboard::default(),filter:Filter::default(),touch:Touch::default(),sequencer:Sequencer::default(),storage:Storage::default() } }
    fn path(&self) -> Result<PathBuf,String> {
        let name = self.name.as_ref().ok_or("尚未选择串口")?;
        Ok(self.root.join(format!("{}.json",name.chars().map(|c| if c.is_ascii_alphanumeric() {c} else {'_'}).collect::<String>())))
    }
    fn save(&self) -> Result<(),String> {
        let path=self.path()?;let parent=path.parent().ok_or("无效会话路径")?;
        std::fs::create_dir_all(parent).map_err(|e|e.to_string())?;
        let mut temp=tempfile::NamedTempFile::new_in(parent).map_err(|e|e.to_string())?;
        temp.write_all(&serde_json::to_vec_pretty(&self.saved).map_err(|e|e.to_string())?)
            .and_then(|_|temp.as_file().sync_all()).map_err(|e|e.to_string())?;
        temp.persist(path).map_err(|e|e.to_string())?;Ok(())
    }
    pub fn is_connected(&self) -> bool { self.port.is_some() }
    pub fn view(&self) -> View { View { connected:self.port.is_some(),port:self.name.clone(),abi:self.abi,pending:self.saved.pending.is_some(),slots:self.saved.slots.clone(),volume:self.saved.volume,sustain:self.saved.sustain,held:self.saved.notes.keys().cloned().collect(),telemetry:self.telemetry.clone(),age_ms:self.received.map(|t|t.elapsed().as_millis()),packets:self.packets,retries:self.retries,error:self.error.clone(),fx_available:self.fx_available,keys:self.saved.keys.clone(),monitor:self.monitor.clone(),hdmi:self.hdmi.clone(),keyboard:self.keyboard.clone(),filter:self.filter.clone(),touch:self.touch.clone(),sequencer:self.sequencer.clone(),storage:self.storage.clone(),serial:self.serial.clone(),wave_transfer:self.saved.wave.as_ref().map(|w|WaveStatus{name:w.name.clone(),written:w.next,total:w.samples.len(),busy_recoveries:w.busy_recoveries}),wave_name:self.saved.wave_name.clone(),wave_morph:self.saved.wave_morph } }
    pub fn connect(&mut self, name: String, fresh: bool) -> Result<(),String> {
        if self.port.is_some() { return Err("请先断开当前连接".into()); }
        self.name = Some(name.clone()); self.abi=None; self.fx_available=false; self.received=None; self.error.clear();
        self.serial=SerialDiagnostics::default();self.packets=0;self.retries=0;
        self.telemetry=Telemetry::default();self.poll_index=0;self.hdmi=Hdmi::default();self.storage=Storage::default();
        let path=self.path()?;
        self.saved=if path.exists() { serde_json::from_slice(&std::fs::read(&path).map_err(|e|e.to_string())?).map_err(|e|format!("会话文件损坏，未发送命令：{e}"))? } else { Saved::default() };
        let mut port=serialport::new(&name,115200).dtr_on_open(false).timeout(Duration::from_millis(15)).open().map_err(|e|e.to_string())?;
        port.write_data_terminal_ready(false).map_err(|e|e.to_string())?;
        port.write_request_to_send(false).map_err(|e|e.to_string())?;
        port.clear(serialport::ClearBuffer::Input).map_err(|e|e.to_string())?;
        if fresh {
            if path.exists() { std::fs::copy(&path,path.with_extension(format!("{}.previous",SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis()))).map_err(|e|e.to_string())?; }
            let keyboard=self.saved.keyboard.clone();let filter=self.saved.filter.clone();let touch=self.saved.touch.clone();self.saved=Saved::default();self.saved.keyboard=keyboard;self.saved.filter=filter;self.saved.touch=touch;
            for (slot,p) in library().presets.into_iter().take(4).enumerate() { self.saved.slots[slot]=Slot{program:Some(p.program),revision:1,operators:p.operators,native:None,snapshot:None}; }
        }
        self.port=Some(port);self.save()?;
        if self.saved.pending.is_some() { return Err("已连接，但上次请求结果未知。请点击恢复请求；不要重建会话".into()); }
        self.preflight()?;self.poll()?; Ok(())
    }
    fn preflight(&mut self) -> Result<(),String> {
        let abi=self.read(4)?;self.abi=Some(abi);
        if abi < ABI || abi>>16 != 1 { return Err(format!("固件ABI {abi:#010x}不支持此测试页，需要{ABI:#010x}")); }
        self.fx_available=self.read(0x4c)?!=0;
        self.discover_workspace()?;self.discover_keyboard()?;self.discover_filter()?;self.discover_touch()?;self.discover_sequencer()?;self.storage_step()?;
        Ok(())
    }
    fn ready(&self) -> Result<(),String> {
        if self.port.is_none() { return Err("串口未连接".into()); }
        if self.saved.pending.is_some() { return Err("有未确认请求，请先恢复".into()); }
        if self.abi.is_none_or(|a| a<ABI || a>>16!=1) { return Err("尚未确认兼容的新固件".into()); }
        Ok(())
    }
    fn exchange(&mut self, raw: &[u8]) -> Result<Vec<u8>,String> {
        for attempt in 0..3 {
            if attempt>0 {self.retries+=1;}
            let started=Instant::now();
            let port=self.port.as_mut().ok_or("串口未连接")?;
            port.write_all(raw).and_then(|_|port.flush()).map_err(|e|e.to_string())?;
            let deadline=Instant::now()+Duration::from_millis(500);let mut buffer=Vec::new();let mut chunk=[0u8;32];
            while Instant::now()<deadline {
                // Windows waits for the requested byte count or timeout. Ask only
                // for the remaining 32-byte response, never a 256-byte buffer.
                let needed=32-buffer.len();
                match port.read(&mut chunk[..needed]) {
                    Ok(n)=>buffer.extend_from_slice(&chunk[..n]),
                    Err(e) if matches!(e.kind(),std::io::ErrorKind::TimedOut|std::io::ErrorKind::WouldBlock)=>{},
                    Err(e)=>return Err(e.to_string()),
                }
                while buffer.len()>=32 {
                    if matching_response(&buffer[..32],raw) {
                        self.packets+=1;self.serial.last_wire_ms=started.elapsed().as_millis();
                        self.serial.max_wire_ms=self.serial.max_wire_ms.max(self.serial.last_wire_ms);
                        if attempt>0 {self.trace(raw,"retry_succeeded",attempt,started.elapsed().as_millis());}
                        return Ok(buffer[..32].to_vec());
                    }
                    if buffer[..3]==[0x53,0x52,5] {
                        if crc16(&buffer[..30])==u16::from_le_bytes([buffer[30],buffer[31]]) {
                            self.serial.unmatched_frames+=1;buffer.drain(..32);continue;
                        }
                        self.serial.corrupt_frames+=1;
                    }
                    buffer.remove(0);
                }
            }
            self.serial.timeout_attempts+=1;
            self.trace(raw,"response_timeout",attempt,started.elapsed().as_millis());
        }
        Err(format!("{} 响应超时；请核对调试口与固件。原请求已保留，可原样恢复",self.name.as_deref().unwrap_or("串口")))
    }
    fn trace(&self,raw:&[u8],event:&str,attempt:u32,elapsed_ms:u128) {
        let Some(name)=self.name.as_ref() else{return;};
        let file=self.root.join(format!("serial-{}.jsonl",name.chars().filter(|c|c.is_ascii_alphanumeric()).collect::<String>()));
        let entry=serde_json::json!({"time_ms":SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis(),"port":name,"sequence":u32_at(raw,4),"kind":raw[3],"opcode":raw[8],"event":event,"attempt":attempt,"elapsed_ms":elapsed_ms,"serial":self.serial});
        if let Ok(mut file)=std::fs::OpenOptions::new().create(true).append(true).open(file){let _=writeln!(file,"{entry}");}
    }
    fn finish(&mut self) -> Result<Vec<u8>,String> {
        let pending=self.saved.pending.clone().ok_or("没有待恢复请求")?;
        let response=self.exchange(&pending.raw)?;
        if response[24]==2 || response[24]==3 { return Err("会话序号不匹配。若板卡刚复位，请断开后勾选建立新会话；否则使用原会话恢复".into()); }
        let success=response[24]==0 && (pending.raw[3]!=0 || response[16]==0);
        self.saved.next_sequence=self.saved.next_sequence.checked_add(1).ok_or("会话序号已耗尽，请复位板卡后建立新会话")?;
        self.saved.pending=None;
        if success {
            match pending.effect {
                Effect::Touch{profile}=>{self.saved.touch=Some(profile.clone());self.touch.profile=profile;},
                Effect::Filter{profile}=>{self.saved.filter=Some(profile.clone());self.filter.profile=profile;},
                Effect::Keyboard{profile}=>{self.saved.keyboard=Some(profile.clone());self.keyboard.profile=profile;self.keyboard.calibration=None;self.keyboard.draft_clear();},
                Effect::Key{key,value}=>self.saved.keys[key as usize]=value,
                Effect::None=>{}, Effect::Slot{slot,value}=>self.saved.slots[slot as usize]=value,
                Effect::On{token,note}=>{self.saved.notes.insert(token,note);},
                Effect::Off{token}=>{self.saved.notes.remove(&token);},
                Effect::Control{volume,sustain,panic}=>{self.saved.volume=volume;self.saved.sustain=sustain;if panic{self.saved.notes.clear();}},
                Effect::WaveStopped=>{if let Some(w)=self.saved.wave.as_mut(){w.stopped=true;}self.saved.notes.clear();self.saved.sustain=false;},
                Effect::WaveAdvance{next}=>{if let Some(w)=self.saved.wave.as_mut(){w.next=next;}},
                Effect::WaveFinished=>{if let Some(w)=self.saved.wave.take(){self.saved.wave_name=Some(w.name);self.saved.wave_morph=w.morph;}self.saved.notes.clear();self.saved.sustain=false;},
            }
        }
        self.save()?;
        if response[24]==11 {return Err("音序器保留了该音色或波表，请改用空闲音色槽".into());}
        if response[24]!=0 { return Err(format!("通信控制器拒绝请求，状态{}",response[24])); }
        if pending.raw[3]==0 && response[16]!=0 {
            self.last_engine_status=Some(response[16]);
            self.trace(&pending.raw,&format!("engine_rejected_{}",response[16]),0,0);
            return Err(if response[16]==10 {"音色仍有活动声部或资源忙；请松键等待，或紧急停止后重试".into()} else {format!("合成引擎拒绝操作{:02X}，状态{}",pending.raw[8],response[16])});
        }
        Ok(response)
    }
    fn request(&mut self, kind:u8, opcode:u8, address:u8, words:&[u32], effect:Effect) -> Result<Vec<u8>,String> {
        self.last_engine_status=None;
        if self.saved.pending.is_some() {return Err("请先恢复未确认请求".into());}
        let started=Instant::now();let raw=packet(self.saved.next_sequence,kind,opcode,address,words)?;
        self.saved.pending=Some(Pending {raw:raw.clone(),effect});
        self.save()?;let result=self.finish();
        self.serial.last_request_ms=started.elapsed().as_millis();
        self.serial.max_request_ms=self.serial.max_request_ms.max(self.serial.last_request_ms);
        if kind==0||self.serial.last_request_ms>50 {self.trace(&raw,"request_finished",0,self.serial.last_request_ms);}
        result
    }
    fn read(&mut self,address:u32) -> Result<u32,String> { Ok(u32_at(&self.request(1,0,0,&[address],Effect::None)?,8)) }
    pub fn poll(&mut self) -> Result<(),String> {
        self.ready()?;
        let result=self.request(2,0,0,&[],Effect::None)?;
        self.telemetry.flags=u32_at(&result,8);self.telemetry.pressed=u32_at(&result,12);self.telemetry.frames=u32_at(&result,16);
        self.telemetry.underruns=u16::from_le_bytes([result[20],result[21]]);self.telemetry.bad_packets=u16::from_le_bytes([result[22],result[23]]);self.received=Some(Instant::now());
        // Keep a background turn bounded: status plus one rotating counter.
        // Note-On/Off can run between polls and individual PCM chunks.
        let addresses=[0x38,0x40,0x38,0x3c,0x38,0x44,0x38,0x40];
        let address=addresses[self.poll_index];let value=self.read(address)?;
        match address {0x38=>self.telemetry.active=value,0x40=>self.telemetry.cycles=value,0x3c=>self.telemetry.overruns=value,_=>self.telemetry.pcm_dropped=value}
        if self.poll_index==0||self.poll_index==4 {self.poll_monitor()?;}
        self.poll_index=(self.poll_index+1)%addresses.len();Ok(())
    }
    fn control(&mut self,volume:f64,sustain:bool,panic:bool) -> Result<(),String> {
        if !volume.is_finite() || !(0.0..=1.0).contains(&volume) {return Err("音量越界".into());}
        let enable=u32::from(self.saved.wave.is_none());
        self.request(0,0xa7,0,&[enable|(u32::from(sustain)<<1)|(u32::from(panic)<<2),(volume*UNITY as f64).round() as u32],Effect::Control{volume,sustain,panic})?;Ok(())
    }
    fn load(&mut self,slot:u8,program:u8,operators:Option<Vec<Operator>>) -> Result<(),String> {
        if slot>3{return Err("音色槽越界".into());}
        self.check_slot_unlocked(slot)?;
        let time=SystemTime::now().duration_since(UNIX_EPOCH).map_err(|e|e.to_string())?.as_secs();
        let revision=time.max(self.saved.slots[slot as usize].revision as u64+1);
        if revision>u32::MAX as u64{return Err("音色版本耗尽".into());}
        let (commands,value)=compile(program,slot,revision as u32,operators)?;
        if self.saved.slots[slot as usize].native.is_some() && self.sequencer.locked_slots==0{self.control(self.saved.volume,false,true)?;}
        for command in commands {
            let effect=if command.opcode==0xa3 {Effect::Slot{slot,value:value.clone()}} else {Effect::None};
            self.request(0,command.opcode,command.address,&command.words,effect)?;
        }
        Ok(())
    }
    fn load_native(&mut self,slot:u8,patch:NativePatch)->Result<(),String> {
        if slot>3{return Err("音色槽越界".into());}
        self.check_slot_unlocked(slot)?;
        let time=SystemTime::now().duration_since(UNIX_EPOCH).map_err(|e|e.to_string())?.as_secs();
        let revision=time.max(self.saved.slots[slot as usize].revision as u64+1);
        if revision>u32::MAX as u64{return Err("音色版本耗尽".into());}
        let (commands,value)=compile_native(patch,slot,revision as u32)?;
        // Retained layers must not receive a global panic when editing a free slot.
        if self.sequencer.locked_slots==0 {self.control(self.saved.volume,false,true)?;}
        for command in commands {
            let effect=if command.opcode==0xa3 {Effect::Slot{slot,value:value.clone()}}else{Effect::None};
            self.request(0,command.opcode,command.address,&command.words,effect)?;
        }
        Ok(())
    }
    fn wave_begin(&mut self,name:String,samples:Vec<i16>,morph:f64)->Result<(),String> {
        self.sequencer_step()?;
        if self.sequencer.locked_slots!=0||self.sequencer.recording||self.sequencer.finalizing{return Err("当前录音保留了音色。全局波表不能在录音或已有层存在时替换，请先结束录制并清空音序".into());}
        if name.trim().is_empty()||name.chars().count()>120||samples.len()!=2048||!morph.is_finite()||!(0.0..=1.0).contains(&morph) {return Err("波表需要名称、两帧各 1024 个 signed16 样本及 0..1 的帧间位置".into());}
        if self.saved.wave.is_some(){return Err("请先完成当前波表上传；部分写入不能直接恢复演奏".into());}
        self.saved.wave=Some(WaveTransfer{name,samples,next:0,stopped:false,morph,busy_recoveries:0});self.save()?;
        self.wave_stop()
    }
    fn wave_stop(&mut self)->Result<(),String> {
        self.request(0,0xa7,0,&[4,(self.saved.volume*UNITY as f64).round() as u32],Effect::WaveStopped)?;Ok(())
    }
    fn wave_step(&mut self)->Result<(),String> {
        let w=self.saved.wave.as_ref().ok_or("没有正在上传的波表")?;
        if !w.stopped{self.wave_stop()?;}
        let w=self.saved.wave.as_ref().unwrap();let end=(w.next+16).min(w.samples.len());
        let batch:Vec<_>=(w.next..end).map(|i|(i,w.samples[i])).collect();
        for (index,sample) in batch {
            // 16-bit signed assets -> Q26, preserving the asymmetric PCM endpoints.
            let mut repairs=0;
            loop {
                match self.request(0,0xa8,0,&[index as u32,(i32::from(sample)*2048) as u32],Effect::WaveAdvance{next:index+1}) {
                    Ok(_)=>break,
                    Err(_) if self.last_engine_status==Some(10)&&self.saved.pending.is_none()&&repairs<3=>{
                        // Physical Note-On can allocate a voice while A7 has muted
                        // rendering. Acknowledge BUSY, clear those voices while
                        // remaining muted, then retry THIS sample with a new ID.
                        // An uncertain transport result is never skipped/replaced.
                        repairs+=1;
                        if let Some(w)=self.saved.wave.as_mut(){w.busy_recoveries=w.busy_recoveries.saturating_add(1);}
                        self.wave_stop()?;
                    },
                    Err(e)=>return Err(e),
                }
            }
        }
        Ok(())
    }
    fn wave_finish(&mut self)->Result<(),String> {
        let w=self.saved.wave.as_ref().ok_or("没有正在上传的波表")?;
        if !w.stopped||w.next!=2048{return Err("波表尚未完整确认，不能恢复演奏".into());}
        self.request(0,0xa7,0,&[5,(self.saved.volume*UNITY as f64).round() as u32],Effect::WaveFinished)?;Ok(())
    }
    pub fn action(&mut self, action:Action) -> Result<View,String> {
        let result=(||{
            match action {
                Action::Connect{port,fresh}=>self.connect(port,fresh),
                Action::Disconnect=>{
                    if self.keyboard.calibration.is_some() && self.ready().is_ok(){self.keyboard_cancel()?;}
                    if self.ready().is_ok() { self.control(self.saved.volume,false,true)?; }
                    self.port=None;self.abi=None;self.fx_available=false;self.received=None;Ok(())
                },
                Action::StorageStep=>self.storage_step(),
                Action::StorageAction{operation,number,slot}=>self.storage_action(operation,number,slot),
                #[cfg(feature="test-harness")]
                Action::StorageRead{lba}=>self.storage_read(lba),
                #[cfg(feature="test-harness")]
                Action::StorageRestart=>self.storage_restart(),
                Action::Recover=>{self.finish()?;self.preflight()?;self.poll()},
                other=>{
                    self.ready()?;
                    if self.storage.service && (self.storage.busy || self.storage.syncing) {
                        match &other {
                            Action::Poll|Action::SequencerStep|Action::FilterStep|Action::HdmiStep=>return Ok(()),
                            Action::HdmiPage{..}|Action::MonitorStep|Action::KeyboardStep|Action::TouchStep=>{},
                            _=>return Err("板卡正在存取 SD 或回读音色，请稍后再操作".into()),
                        }
                    }
                    if self.saved.wave.is_some()&&!matches!(&other,Action::Poll|Action::Panic|Action::WaveStep|Action::WaveFinish){return Err("共享波表上传期间已停音，请继续完成上传".into());}
                    if self.keyboard.calibration.is_some() && !matches!(&other,Action::Poll|Action::Panic|Action::KeyboardStep|Action::KeyboardCapture|Action::KeyboardPrevious|Action::KeyboardCancel|Action::KeyboardApply{..}) {return Err("键盘校准期间暂停演奏和音色修改，请先完成或取消校准".into());}
                    match other {
                        Action::KeyboardStep=>self.keyboard_step(),Action::KeyboardBegin=>self.keyboard_begin(),Action::KeyboardCapture=>self.keyboard_capture(),Action::KeyboardPrevious=>self.keyboard_previous(),Action::KeyboardCancel=>self.keyboard_cancel(),
                        Action::KeyboardApply{release,press,sensitivity,velocity_enabled,velocity_ceiling}=>self.keyboard_apply(release,press,sensitivity,velocity_enabled,velocity_ceiling),
                        Action::Poll=>self.poll(),
                        Action::MonitorStep=>self.capture_step(),
                        Action::SequencerStep=>self.sequencer_step(),Action::SequencerControl{action,bpm}=>self.sequencer_control(action,bpm),
                        Action::SequenceExport=>self.sequence_export(),Action::SequenceImport{image}=>self.sequence_import(image),
                        Action::TouchApply{profile}=>self.touch_apply(profile),Action::TouchStep=>self.touch_step(),
                        Action::FilterApply{profile}=>self.filter_apply(profile),Action::FilterStep=>self.filter_step(),
                        Action::HdmiStep=>self.hdmi_step(),Action::HdmiPage{page}=>self.hdmi_page(page),Action::HdmiApply=>self.hdmi_commit(),Action::HdmiCancel=>self.hdmi_cancel(),
                        Action::HdmiRgb{mode,direction}=>self.hdmi_rgb(mode,direction),
                        Action::ConfigureKey{key,note,velocity}=>self.configure_key(key,note,velocity),
                        Action::ValidateKey{key,scope,program,patch,operators}=>self.validate_key(key,&scope,program,patch,operators),
                        Action::AssignKey{key,scope,program,patch,operators}=>self.assign_key(key,scope,program,patch,operators),
                        Action::Load{slot,program,operators}=>self.load(slot,program,operators),
                        Action::LoadNative{slot,patch}=>self.load_native(slot,patch),
                        Action::WaveBegin{name,samples,morph}=>self.wave_begin(name,samples,morph),
                        Action::WaveStep=>self.wave_step(),Action::WaveFinish=>self.wave_finish(),
                        Action::Control{volume,sustain}=>self.control(volume,sustain,false),
                        Action::Panic=>{self.control(self.saved.volume,false,true)?;if self.fx_available {self.request(0,0xc3,0,&[3],Effect::None)?;}Ok(())},
                        Action::Fx{room}=>{for c in fx_commands(self.fx_available,room)? {self.request(0,c.opcode,c.address,&c.words,Effect::None)?;}Ok(())},
                        Action::Note{token,note,velocity,slot,pressed}=>{
                            if token.is_empty() || token.len()>80 || slot>3 || note>127 || velocity==0 || velocity>127{return Err("音符/力度/输入标识越界".into());}
                            if pressed {
                                if self.saved.notes.contains_key(&token){return Ok(());}
                                let id=self.saved.next_note;if id>=0x7fffffff{return Err("音符编号耗尽".into());}self.saved.next_note+=1;
                                let phase=(440.0*2f64.powf((note as f64-69.0)/12.0)*4294967296.0/RATE).round() as u32;
                                self.request(0,0xa4,slot,&[id,phase,UNITY,UNITY/2,0x80000000|((velocity as u32)<<7)|note as u32],Effect::On{token,note:Note{id,slot,note,velocity}})?;
                            } else if let Some(held)=self.saved.notes.get(&token).cloned() {
                                self.request(0,0xa5,0,&[held.id],Effect::Off{token})?;
                            }
                            Ok(())
                        },
                        _=>unreachable!(),
                    }
                },
            }
        })();
        if let Err(error)=result {self.error=error.clone();Err(error)} else {self.error.clear();Ok(self.view())}
    }
}

#[derive(Deserialize)]
#[serde(tag="kind",rename_all="snake_case")]
pub enum Action {
    StorageAction{operation:u8,number:u8,slot:u8},
    #[cfg(feature="test-harness")]
    StorageRead{lba:u32},
    #[cfg(feature="test-harness")]
    StorageRestart,
    SequencerStep,SequencerControl{action:u8,bpm:Option<u16>},
    SequenceExport,SequenceImport{image:sequencer::EventImage},
    Connect{port:String,fresh:bool},Disconnect,Recover,Poll,StorageStep,Panic,MonitorStep,HdmiStep,HdmiPage{page:u8},HdmiApply,HdmiCancel,
    HdmiRgb{mode:u8,direction:bool},
    FilterStep,FilterApply{profile:FilterProfile},
    TouchStep,TouchApply{profile:TouchProfile},
    KeyboardStep,KeyboardBegin,KeyboardCapture,KeyboardPrevious,KeyboardCancel,KeyboardApply{release:f64,press:f64,sensitivity:u16,velocity_enabled:bool,#[serde(default="keyboard_ceiling")] velocity_ceiling:u8},
    ConfigureKey{key:u8,note:u8,velocity:u8},
    ValidateKey{key:u8,scope:String,program:Option<u8>,patch:Option<NativePatch>,operators:Option<Vec<Operator>>},
    AssignKey{key:u8,scope:String,program:Option<u8>,patch:Option<NativePatch>,operators:Option<Vec<Operator>>},
    Load{slot:u8,program:u8,operators:Option<Vec<Operator>>},Control{volume:f64,sustain:bool},Fx{room:bool},
    LoadNative{slot:u8,patch:NativePatch},WaveBegin{name:String,samples:Vec<i16>,#[serde(default)] morph:f64},WaveStep,WaveFinish,
    Note{token:String,note:u8,velocity:u8,slot:u8,pressed:bool},
}
#[tauri::command]
pub fn voice_catalog() -> Library { library() }
#[tauri::command]
pub fn voice_snapshot(state:tauri::State<State>) -> Result<View,String> {Ok(state.lock().map_err(|e|e.to_string())?.view())}
#[tauri::command]
pub async fn voice_action(state:tauri::State<'_,State>,action:Action) -> Result<View,String> {
    let state=state.inner().clone();
    tauri::async_runtime::spawn_blocking(move||state.lock().map_err(|e|e.to_string())?.action(action)).await.map_err(|e|e.to_string())?
}
pub fn run() {
    let root=std::env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(std::env::temp_dir).join("SynthString/voice-engine");
    let engine=Arc::new(Mutex::new(Engine::new(root)));
    let mut context=tauri::generate_context!();context.config_mut().app.windows[0].label="voice-engine".into();
    context.config_mut().app.windows[0].title="SynthString · FM1 音色测试".into();
    tauri::Builder::default().manage(engine).manage(Mutex::new(crate::synth_midi::Midi::default()))
        .invoke_handler(tauri::generate_handler![voice_catalog,voice_snapshot,voice_action,crate::list_ports,crate::synth_midi::synth_midi_ports,crate::synth_midi::synth_midi_connect,crate::synth_midi::synth_midi_events])
        .setup(|app|{
            let args:Vec<_>=std::env::args().collect();
            if let Some(port)=args.iter().position(|s|s=="--port").and_then(|i|args.get(i+1)).cloned(){
                let state=app.state::<State>().inner().clone();let fresh=args.iter().any(|s|s=="--fresh");
                std::thread::spawn(move||{let _=state.lock().map(|mut e|e.action(Action::Connect{port,fresh}));});
            }
            Ok(())
        })
        .on_window_event(|window,event|{if matches!(event,tauri::WindowEvent::CloseRequested{..}) {if let Ok(mut engine)=window.state::<State>().lock(){let _=engine.action(Action::Panic);engine.port=None;}}})
        .run(context).expect("Voice engine App failed to start");
}

#[cfg(test)]
#[path = "voice_wave_tests.rs"]
mod wave_tests;
#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn crc_and_wire_layout(){assert_eq!(crc16(b"123456789"),0x29b1);let p=packet(0x12345678,0,0xa4,3,&[42,12,UNITY,UNITY/2,0x8000323c]).unwrap();assert_eq!(p.len(),52);assert_eq!(&p[..10],&[0x53,0x59,5,0,0x78,0x56,0x34,0x12,0xa4,3]);assert_eq!(u32_at(&p,26),0x8000323c);assert_eq!(crc16(&p[..50]),u16::from_le_bytes([p[50],p[51]]));}
    #[test] fn exact_factory_compiler_parity(){for (index,preset) in library().presets.into_iter().enumerate(){let (commands,_) = compile(preset.program,(index%4) as u8,1,None).unwrap();assert_eq!(serde_json::to_value(commands).unwrap(),serde_json::to_value(preset.commands).unwrap());}}
    #[test] fn dry_firmware_emits_no_fx_commands(){assert!(fx_commands(false,false).unwrap().is_empty());assert!(fx_commands(false,true).is_err());assert!(!fx_commands(true,false).unwrap().is_empty());assert!(!fx_commands(true,true).unwrap().is_empty());}
    #[test] fn unsupported_and_invalid_parameters(){assert!(compile(3,0,1,None).is_err());assert!(compile(4,4,1,None).is_err());let mut ops=library().presets[0].operators.clone();ops[0].levels[3]=1;assert!(compile(4,0,1,Some(ops)).is_err());let mut ops=library().presets[0].operators.clone();ops[0].ratio=Some(f64::NAN);assert!(compile(4,0,1,Some(ops)).is_err());}
    #[test] fn response_identity_and_corruption(){let p=packet(7,0,0xa4,1,&[]).unwrap();let mut r=vec![0;32];r[..4].copy_from_slice(&[0x53,0x52,5,0]);r[4..8].copy_from_slice(&7u32.to_le_bytes());r[25]=0xa4;r[26]=1;let c=crc16(&r[..30]);r[30..].copy_from_slice(&c.to_le_bytes());assert!(matching_response(&r,&p));r[10]^=1;assert!(!matching_response(&r,&p));}
    #[test] fn pending_request_is_durable(){let dir=tempfile::tempdir().unwrap();let mut e=Engine::new(dir.path().into());e.name=Some("COM_TEST".into());let raw=packet(0,0,0xa4,0,&[1,2]).unwrap();e.saved.pending=Some(Pending{raw:raw.clone(),effect:Effect::None});e.save().unwrap();let disk:Saved=serde_json::from_slice(&std::fs::read(e.path().unwrap()).unwrap()).unwrap();assert_eq!(disk.pending.unwrap().raw,raw);assert_eq!(disk.next_sequence,0);assert!(e.request(2,0,0,&[],Effect::None).is_err());}
}

fn keyboard_ceiling()->u8{127}
