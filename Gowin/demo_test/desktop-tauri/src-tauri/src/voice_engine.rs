//! Native protocol-5 session for the resident FPGA voice engine.
//! A timed-out request remains durable and is retried byte-for-byte after reconnect.
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, io::{Read, Write}, path::PathBuf, sync::{Arc, Mutex}, time::{Duration, Instant, SystemTime, UNIX_EPOCH}};
use tauri::Manager;

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

#[derive(Clone, Default, Serialize, Deserialize, Debug)]
pub struct Slot { pub program: Option<u8>, pub revision: u32, pub operators: Vec<Operator> }
#[derive(Clone, Serialize, Deserialize, Debug)]
struct Note { id: u32, slot: u8, note: u8, velocity: u8 }
#[derive(Clone, Serialize, Deserialize, Debug)]
enum Effect {
    None, Slot { slot: u8, value: Slot }, On { token: String, note: Note },
    Off { token: String }, Control { volume: f64, sustain: bool, panic: bool },
}
#[derive(Clone, Serialize, Deserialize, Debug)]
struct Pending { raw: Vec<u8>, effect: Effect }
#[derive(Clone, Serialize, Deserialize)]
struct Saved {
    next_sequence: u32, next_note: u32, pending: Option<Pending>, slots: [Slot; 4],
    notes: BTreeMap<String, Note>, volume: f64, sustain: bool,
}
impl Default for Saved {
    fn default() -> Self { Self { next_sequence: 0, next_note: 1, pending: None, slots: Default::default(), notes: BTreeMap::new(), volume: 0.5, sustain: false } }
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
    slots: [Slot; 4], volume: f64, sustain: bool, held: Vec<String>,
    telemetry: Telemetry, age_ms: Option<u128>, packets: u64, retries: u64, error: String,
}
pub struct Engine {
    port: Option<Box<dyn serialport::SerialPort>>, name: Option<String>, root: PathBuf,
    saved: Saved, abi: Option<u32>, telemetry: Telemetry, received: Option<Instant>,
    poll_index: usize, packets: u64, retries: u64, error: String,
}
pub type State = Arc<Mutex<Engine>>;

pub fn crc16(data: &[u8]) -> u16 {
    let mut crc = 0xffffu16;
    for byte in data { crc ^= (*byte as u16) << 8; for _ in 0..8 { crc = if crc & 0x8000 != 0 { (crc << 1) ^ 0x1021 } else { crc << 1 }; } }
    crc
}
pub fn packet(sequence: u32, kind: u8, opcode: u8, address: u8, words: &[u32]) -> Result<Vec<u8>, String> {
    if words.len() > 10 || kind > 2 { return Err("请求长度或类型越界".into()); }
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
    Ok((commands,Slot { program:Some(program),revision,operators:ops }))
}

impl Engine {
    pub fn new(root: PathBuf) -> Self { Self { port:None,name:None,root,saved:Saved::default(),abi:None,telemetry:Telemetry::default(),received:None,poll_index:0,packets:0,retries:0,error:String::new() } }
    fn path(&self) -> Result<PathBuf,String> {
        let name = self.name.as_ref().ok_or("尚未选择串口")?;
        Ok(self.root.join(format!("{}.json",name.chars().map(|c| if c.is_ascii_alphanumeric() {c} else {'_'}).collect::<String>())))
    }
    fn save(&self) -> Result<(),String> { crate::calibration::atomic_json(&self.path()?, &self.saved) }
    pub fn view(&self) -> View { View { connected:self.port.is_some(),port:self.name.clone(),abi:self.abi,pending:self.saved.pending.is_some(),slots:self.saved.slots.clone(),volume:self.saved.volume,sustain:self.saved.sustain,held:self.saved.notes.keys().cloned().collect(),telemetry:self.telemetry.clone(),age_ms:self.received.map(|t|t.elapsed().as_millis()),packets:self.packets,retries:self.retries,error:self.error.clone() } }
    pub fn connect(&mut self, name: String, fresh: bool) -> Result<(),String> {
        if self.port.is_some() { return Err("请先断开当前连接".into()); }
        self.name = Some(name.clone()); self.abi=None; self.received=None; self.error.clear();
        let path=self.path()?;
        self.saved=if path.exists() { serde_json::from_slice(&std::fs::read(&path).map_err(|e|e.to_string())?).map_err(|e|format!("会话文件损坏，未发送命令：{e}"))? } else { Saved::default() };
        let mut port=serialport::new(&name,115200).dtr_on_open(false).timeout(Duration::from_millis(15)).open().map_err(|e|e.to_string())?;
        port.write_data_terminal_ready(false).map_err(|e|e.to_string())?;
        port.write_request_to_send(false).map_err(|e|e.to_string())?;
        port.clear(serialport::ClearBuffer::Input).map_err(|e|e.to_string())?;
        if fresh {
            if path.exists() { std::fs::copy(&path,path.with_extension(format!("{}.previous",SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis()))).map_err(|e|e.to_string())?; }
            self.saved=Saved::default();
            for (slot,p) in library().presets.into_iter().enumerate() { self.saved.slots[slot]=Slot{program:Some(p.program),revision:1,operators:p.operators}; }
        }
        self.port=Some(port);self.save()?;
        if self.saved.pending.is_some() { return Err("已连接，但上次请求结果未知。请点击恢复请求；不要重建会话".into()); }
        self.preflight()?;self.poll()?; Ok(())
    }
    fn preflight(&mut self) -> Result<(),String> {
        let abi=self.read(4)?;self.abi=Some(abi);
        if abi < ABI || abi>>16 != 1 { return Err(format!("固件ABI {abi:#010x}不支持此测试页，需要{ABI:#010x}")); }
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
            let port=self.port.as_mut().ok_or("串口未连接")?;
            port.write_all(raw).and_then(|_|port.flush()).map_err(|e|e.to_string())?;
            let deadline=Instant::now()+Duration::from_millis(500);let mut buffer=Vec::new();let mut chunk=[0u8;256];
            while Instant::now()<deadline {
                match port.read(&mut chunk) {
                    Ok(n)=>buffer.extend_from_slice(&chunk[..n]),
                    Err(e) if matches!(e.kind(),std::io::ErrorKind::TimedOut|std::io::ErrorKind::WouldBlock)=>{},
                    Err(e)=>return Err(e.to_string()),
                }
                while buffer.len()>=32 {
                    if matching_response(&buffer[..32],raw) {self.packets+=1;return Ok(buffer[..32].to_vec());}
                    buffer.remove(0);
                }
            }
        }
        Err("串口响应超时；请求已保留，可安全原样恢复".into())
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
                Effect::None=>{}, Effect::Slot{slot,value}=>self.saved.slots[slot as usize]=value,
                Effect::On{token,note}=>{self.saved.notes.insert(token,note);},
                Effect::Off{token}=>{self.saved.notes.remove(&token);},
                Effect::Control{volume,sustain,panic}=>{self.saved.volume=volume;self.saved.sustain=sustain;if panic{self.saved.notes.clear();}},
            }
        }
        self.save()?;
        if response[24]!=0 { return Err(format!("通信控制器拒绝请求，状态{}",response[24])); }
        if pending.raw[3]==0 && response[16]!=0 {
            return Err(if response[16]==10 {"音色仍有活动声部或资源忙；请松键等待，或紧急停止后重试".into()} else {format!("合成引擎拒绝操作{:02X}，状态{}",pending.raw[8],response[16])});
        }
        Ok(response)
    }
    fn request(&mut self, kind:u8, opcode:u8, address:u8, words:&[u32], effect:Effect) -> Result<Vec<u8>,String> {
        if self.saved.pending.is_some() {return Err("请先恢复未确认请求".into());}
        self.saved.pending=Some(Pending {raw:packet(self.saved.next_sequence,kind,opcode,address,words)?,effect});
        self.save()?;self.finish()
    }
    fn read(&mut self,address:u32) -> Result<u32,String> { Ok(u32_at(&self.request(1,0,0,&[address],Effect::None)?,8)) }
    pub fn poll(&mut self) -> Result<(),String> {
        self.ready()?;
        let result=self.request(2,0,0,&[],Effect::None)?;
        self.telemetry.flags=u32_at(&result,8);self.telemetry.pressed=u32_at(&result,12);self.telemetry.frames=u32_at(&result,16);
        self.telemetry.underruns=u16::from_le_bytes([result[20],result[21]]);self.telemetry.bad_packets=u16::from_le_bytes([result[22],result[23]]);self.received=Some(Instant::now());
        let addresses=[0x38,0x3c,0x40,0x44,0x58,0x5c,0x60];let value=self.read(addresses[self.poll_index])?;
        match self.poll_index {0=>self.telemetry.active=value,1=>self.telemetry.overruns=value,2=>self.telemetry.cycles=value,3=>self.telemetry.pcm_dropped=value,4=>self.telemetry.fx_clips=value,5=>self.telemetry.fx_dropped=value,_=>self.telemetry.fx_cycles=value}
        self.poll_index=(self.poll_index+1)%addresses.len();Ok(())
    }
    fn control(&mut self,volume:f64,sustain:bool,panic:bool) -> Result<(),String> {
        if !volume.is_finite() || !(0.0..=1.0).contains(&volume) {return Err("音量越界".into());}
        self.request(0,0xa7,0,&[1|(u32::from(sustain)<<1)|(u32::from(panic)<<2),(volume*UNITY as f64).round() as u32],Effect::Control{volume,sustain,panic})?;Ok(())
    }
    fn load(&mut self,slot:u8,program:u8,operators:Option<Vec<Operator>>) -> Result<(),String> {
        if slot>3{return Err("音色槽越界".into());}
        let time=SystemTime::now().duration_since(UNIX_EPOCH).map_err(|e|e.to_string())?.as_secs();
        let revision=time.max(self.saved.slots[slot as usize].revision as u64+1);
        if revision>u32::MAX as u64{return Err("音色版本耗尽".into());}
        let (commands,value)=compile(program,slot,revision as u32,operators)?;
        for command in commands {
            let effect=if command.opcode==0xa3 {Effect::Slot{slot,value:value.clone()}} else {Effect::None};
            self.request(0,command.opcode,command.address,&command.words,effect)?;
        }
        Ok(())
    }
    pub fn action(&mut self, action:Action) -> Result<View,String> {
        let result=(||{
            match action {
                Action::Connect{port,fresh}=>self.connect(port,fresh),
                Action::Disconnect=>{
                    if self.ready().is_ok() { self.control(self.saved.volume,false,true)?; }
                    self.port=None;self.abi=None;self.received=None;Ok(())
                },
                Action::Recover=>{self.finish()?;self.preflight()?;self.poll()},
                other=>{
                    self.ready()?;
                    match other {
                        Action::Poll=>self.poll(),
                        Action::Load{slot,program,operators}=>self.load(slot,program,operators),
                        Action::Control{volume,sustain}=>self.control(volume,sustain,false),
                        Action::Panic=>{self.control(self.saved.volume,false,true)?;self.request(0,0xc3,0,&[3],Effect::None)?;Ok(())},
                        Action::Fx{room}=>{for c in if room {library().room} else {library().dry} {self.request(0,c.opcode,c.address,&c.words,Effect::None)?;}Ok(())},
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
    Connect{port:String,fresh:bool},Disconnect,Recover,Poll,Panic,
    Load{slot:u8,program:u8,operators:Option<Vec<Operator>>},Control{volume:f64,sustain:bool},Fx{room:bool},
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
mod tests {
    use super::*;
    #[test] fn crc_and_wire_layout(){assert_eq!(crc16(b"123456789"),0x29b1);let p=packet(0x12345678,0,0xa4,3,&[42,12,UNITY,UNITY/2,0x8000323c]).unwrap();assert_eq!(p.len(),52);assert_eq!(&p[..10],&[0x53,0x59,5,0,0x78,0x56,0x34,0x12,0xa4,3]);assert_eq!(u32_at(&p,26),0x8000323c);assert_eq!(crc16(&p[..50]),u16::from_le_bytes([p[50],p[51]]));}
    #[test] fn exact_factory_compiler_parity(){for (slot,preset) in library().presets.into_iter().enumerate(){let (commands,_) = compile(preset.program,slot as u8,1,None).unwrap();assert_eq!(serde_json::to_value(commands).unwrap(),serde_json::to_value(preset.commands).unwrap());}}
    #[test] fn unsupported_and_invalid_parameters(){assert!(compile(3,0,1,None).is_err());assert!(compile(4,4,1,None).is_err());let mut ops=library().presets[0].operators.clone();ops[0].levels[3]=1;assert!(compile(4,0,1,Some(ops)).is_err());let mut ops=library().presets[0].operators.clone();ops[0].ratio=Some(f64::NAN);assert!(compile(4,0,1,Some(ops)).is_err());}
    #[test] fn response_identity_and_corruption(){let p=packet(7,0,0xa4,1,&[]).unwrap();let mut r=vec![0;32];r[..4].copy_from_slice(&[0x53,0x52,5,0]);r[4..8].copy_from_slice(&7u32.to_le_bytes());r[25]=0xa4;r[26]=1;let c=crc16(&r[..30]);r[30..].copy_from_slice(&c.to_le_bytes());assert!(matching_response(&r,&p));r[10]^=1;assert!(!matching_response(&r,&p));}
    #[test] fn pending_request_is_durable(){let dir=tempfile::tempdir().unwrap();let mut e=Engine::new(dir.path().into());e.name=Some("COM_TEST".into());let raw=packet(0,0,0xa4,0,&[1,2]).unwrap();e.saved.pending=Some(Pending{raw:raw.clone(),effect:Effect::None});e.save().unwrap();let disk:Saved=serde_json::from_slice(&std::fs::read(e.path().unwrap()).unwrap()).unwrap();assert_eq!(disk.pending.unwrap().raw,raw);assert_eq!(disk.next_sequence,0);assert!(e.request(2,0,0,&[],Effect::None).is_err());}
}
