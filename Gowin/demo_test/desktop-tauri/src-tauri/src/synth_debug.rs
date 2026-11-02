//! Dedicated binary protocol session; never sends HardwareLab configuration packets.
use serde::Serialize;
use std::{fs::File, io::{Read, Write}, sync::Mutex, time::{Duration, Instant}};

/// FPGA-clock measurements; the endpoint is the PT8211 left-word latch.
#[derive(Clone, Default, Serialize, Debug)]
pub struct Latency {
    pub records:u32,pub key:u8,pub flags:u8,pub total:u32,pub qualify:u32,pub queue:u32,
    pub compute:u32,pub output:u32,pub mix:u32,pub minimum:u32,pub maximum:u32,pub sum:u64,
    pub late:u32,pub timeouts:u32,pub overwritten:u32,pub scan_period:u32,
    pub physical_records:u32,pub remote_records:u32,pub tick:u32,pub start:u32,pub dac:u32,
    pub budget:u32,pub pending:u32,pub onset_wait:u32,pub canceled:u32,
}

#[derive(Clone, Default, Serialize, Debug)]
pub struct Frame {
    pub frames:u32,pub pressed:u32,pub delivered:u32,pub nonzero:u32,pub events:u32,
    pub cycles:u16,pub flags:u8,pub key:u8,pub raw:u16,pub volume:u8,pub active:u8,
    pub gain:u32,pub input_peak:u32,pub output_peak:u32,pub clips:u32,
    pub envelope_peak:u32,pub wave_peak:u32,pub modulation_peak:u32,pub stages:u8,pub version:u8,pub ack_seq:u8,pub ack_op:u8,pub ack_status:u8,pub ack_key:u8,pub ack_crc:u16,pub commits:u32,
    pub latency:Option<Latency>,
}
#[derive(Default)]
pub struct Parser {buffer:Vec<u8>,pub bad:u64}
impl Parser {
    pub fn feed(&mut self,data:&[u8])->Vec<Frame>{
        self.buffer.extend_from_slice(data);let mut result=Vec::new();
        while self.buffer.len()>=4 {
            if self.buffer[0..2]!=[0xa5,0x5a] {self.buffer.remove(0);continue;}
            let n=self.buffer[3] as usize;let version=self.buffer[2];
            if !((version==1&&n==32)||(version==2&&n==64)||(version==3&&n==80)||(version==4&&n==192)){self.buffer.remove(0);continue;}
            if self.buffer.len()<n{break;}
            let b=&self.buffer[..n];
            if b[n-1]!=13 || b[..n-2].iter().fold(0u8,|a,v|a^v)!=b[n-2]{self.bad+=1;self.buffer.remove(0);continue;}
            let u=|i|u32::from_le_bytes(b[i..i+4].try_into().unwrap());
            let mut f=Frame{frames:u(4),pressed:u(8),delivered:u(12),nonzero:u(16),events:u(20),cycles:u16::from_le_bytes([b[24],b[25]]),flags:b[26],key:b[27],raw:u16::from_le_bytes([b[28],b[29]]),version,..Frame::default()};
            if version>=2{f.volume=b[30];f.active=b[31];f.gain=u(32);f.input_peak=u(36);f.output_peak=u(40);f.clips=u(44);f.envelope_peak=u(48);f.wave_peak=u(52);f.modulation_peak=u(56);f.stages=b[60];}
            if version>=3{f.ack_seq=b[62];f.ack_op=b[63];f.ack_status=b[64];f.ack_key=b[65];f.ack_crc=u16::from_le_bytes([b[66],b[67]]);f.commits=u(68);}
            if version==4{f.latency=Some(Latency{
                records:u(80),key:b[84],flags:b[85],total:u(88),qualify:u(92),queue:u(96),compute:u(100),
                output:u(104),mix:u(108),minimum:u(112),maximum:u(116),sum:u64::from_le_bytes(b[120..128].try_into().unwrap()),
                late:u(128),timeouts:u(132),overwritten:u(136),scan_period:u(140),physical_records:u(144),remote_records:u(148),
                tick:u(152),start:u(156),dac:u(160),budget:u(164),pending:u(168),onset_wait:u(172),canceled:u(176),
            });}
            result.push(f);self.buffer.drain(..n);
        }
        result
    }
}
pub struct Session {seq:u8,heartbeat:Option<Instant>,wave_loaded:bool,port:Option<Box<dyn serialport::SerialPort>>,parser:Parser,last:Option<Frame>,received:Option<Instant>,opened:Option<Instant>,packets:u64,log:Option<File>}
impl Default for Session {fn default()->Self{Self{seq:0,heartbeat:None,wave_loaded:false,port:None,parser:Parser::default(),last:None,received:None,opened:None,packets:0,log:None}}}
#[derive(Serialize)]
pub struct View{connected:bool,packets:u64,bad:u64,age_ms:Option<u128>,frame:Option<Frame>}
#[tauri::command]
pub fn synth_connect(state:tauri::State<Mutex<Session>>,port:Option<String>)->Result<(),String>{
    let mut s=state.lock().map_err(|e|e.to_string())?;
    if s.last.as_ref().is_some_and(|f|matches!(f.version,3|4)){let _=s.send_packet(4,0,&[]);}s.port=None;s.wave_loaded=false;s.last=None;s.received=None;
    s.parser=Parser::default();s.packets=0;
    if let Some(name)=port{
        let mut p=serialport::new(name,115200).dtr_on_open(false).timeout(Duration::from_millis(20)).open().map_err(|e|e.to_string())?;
        p.write_data_terminal_ready(false).map_err(|e|e.to_string())?;p.write_request_to_send(false).map_err(|e|e.to_string())?;
        p.clear(serialport::ClearBuffer::Input).map_err(|e|e.to_string())?;s.port=Some(p);s.opened=Some(Instant::now());
    } Ok(())
}
#[tauri::command]
pub fn synth_command(state:tauri::State<Mutex<Session>>,command:String)->Result<(),String>{
    if command.len()!=1 || !b"TPL012345678".contains(&command.as_bytes()[0]){return Err("不支持的调试命令".into());}
    let mut s=state.lock().map_err(|e|e.to_string())?;
    if s.received.is_none_or(|t|t.elapsed()>Duration::from_secs(2)){return Err("尚未收到有效 FPGA 遥测".into());}
    if command=="L"&&!s.last.as_ref().is_some_and(|f|f.version==4){return Err("延迟统计清零需要协议 4 固件".into());}
    s.port.as_mut().ok_or("串口未连接")?.write_all(command.as_bytes()).map_err(|e|e.to_string())
}
#[tauri::command]
pub fn synth_snapshot(state:tauri::State<Mutex<Session>>)->Result<View,String>{
    let mut s=state.lock().map_err(|e|e.to_string())?;s.pump()?;
    if s.last.as_ref().is_some_and(|f|matches!(f.version,3|4))&&s.heartbeat.is_none_or(|t|t.elapsed()>Duration::from_millis(500)){
        s.send_packet(7,0,&[])?;s.heartbeat=Some(Instant::now());
    }
    Ok(View{connected:s.port.is_some(),packets:s.packets,bad:s.parser.bad,age_ms:s.received.map(|t|t.elapsed().as_millis()),frame:s.last.clone()})
}
pub fn run(){
    let mut session=Session::default();let args:Vec<_>=std::env::args().collect();
    if let Some(i)=args.iter().position(|a|a=="--capture"){
        if let Some(path)=args.get(i+1){session.log=Some(File::create(path).expect("create capture log"));}
    }
    let mut context=tauri::generate_context!();context.config_mut().app.windows[0].label="synth".into();
    context.config_mut().app.windows[0].title="Tang Synth Studio · 音色与链路".into();
    tauri::Builder::default().manage(Mutex::new(session)).manage(Mutex::new(super::synth_midi::Midi::default()))
        .invoke_handler(tauri::generate_handler![synth_connect,synth_snapshot,synth_command,synth_patch,synth_note,synth_panic,synth_wave,super::synth_midi::synth_midi_ports,super::synth_midi::synth_midi_connect,super::synth_midi::synth_midi_events,super::list_ports])
        .run(context).expect("synth debug app");
}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn fragmented_and_corrupted(){
  let mut b=[0u8;64];b[..4].copy_from_slice(&[0xa5,0x5a,2,64]);b[8]=5;b[24]=192;b[25]=1;b[26]=8;b[30]=6;b[31]=2;b[60]=127;b[63]=13;b[62]=b[..62].iter().fold(0,|a,v|a^v);
  let mut p=Parser::default();assert!(p.feed(&b[..15]).is_empty());let f=p.feed(&b[15..]);assert_eq!(f[0].pressed,5);assert_eq!(f[0].cycles,448);assert_eq!(f[0].stages,127);
  let mut corrupt=b;corrupt[29]^=4;assert!(p.feed(&corrupt).is_empty());assert_eq!(p.feed(&b).len(),1);assert_eq!(p.bad,1);
 }
 #[test]fn latency_packet_all_fragment_boundaries_and_recovery(){
  let mut b=[0u8;192];b[..4].copy_from_slice(&[0xa5,0x5a,4,192]);b[191]=13;
  b[24..26].copy_from_slice(&385u16.to_le_bytes());b[26]=8;b[62]=73;b[63]=2;b[65]=17;
  b[66..68].copy_from_slice(&0xf135u16.to_le_bytes());b[80..84].copy_from_slice(&37u32.to_le_bytes());
  b[84]=17;b[85]=7;b[88..92].copy_from_slice(&358921u32.to_le_bytes());
  b[92..96].copy_from_slice(&330000u32.to_le_bytes());b[100..104].copy_from_slice(&385u32.to_le_bytes());
  b[120..128].copy_from_slice(&0x123456789u64.to_le_bytes());b[168..172].copy_from_slice(&0x80000001u32.to_le_bytes());
  b[172..176].copy_from_slice(&1024u32.to_le_bytes());b[176..180].copy_from_slice(&9u32.to_le_bytes());
  b[190]=b[..190].iter().fold(0,|a,v|a^v);
  for split in 0..=192{
   let mut p=Parser::default();let mut frames=p.feed(&b[..split]);frames.extend(p.feed(&b[split..]));
   assert_eq!(frames.len(),1);assert_eq!(p.bad,0);let f=&frames[0];assert_eq!(f.cycles,385);assert_eq!(f.ack_crc,0xf135);
   let l=f.latency.as_ref().unwrap();assert_eq!(l.key,17);assert_eq!(l.total,358921);assert_eq!(l.records,37);
   assert_eq!(l.sum,0x123456789);assert_eq!(l.pending,0x80000001);assert_eq!(l.onset_wait,1024);assert_eq!(l.canceled,9);
  }
  let mut p=Parser::default();let mut corrupt=b;corrupt[90]^=1;assert!(p.feed(&corrupt).is_empty());
  let mut valid=vec![0x11,0x22,0xa5];valid.extend(b);assert_eq!(p.feed(&valid).len(),1);assert_eq!(p.bad,1);
 }
 #[test]fn legacy_studio_ack_still_works_without_latency(){
  let mut b=[0u8;80];b[..4].copy_from_slice(&[0xa5,0x5a,3,80]);b[62]=9;b[63]=1;b[65]=12;b[79]=13;
  b[78]=b[..78].iter().fold(0,|a,v|a^v);let f=Parser::default().feed(&b).remove(0);
  assert_eq!(f.ack_seq,9);assert_eq!(f.ack_op,1);assert!(f.latency.is_none());
 }
}

impl Session {
 fn pump(&mut self)->Result<(),String>{
  let mut bytes=[0u8;4096];let mut n=0;
  if let Some(port)=self.port.as_mut(){let available=port.bytes_to_read().map_err(|e|e.to_string())? as usize;if available>0{n=port.read(&mut bytes[..available.min(4096)]).map_err(|e|e.to_string())?;}}
  if self.opened.is_some_and(|t|t.elapsed()<Duration::from_millis(1500)){n=0;}
  for frame in self.parser.feed(&bytes[..n]){
   if let Some(file)=self.log.as_mut(){serde_json::to_writer(&mut *file,&frame).map_err(|e|e.to_string())?;file.write_all(b"\n").map_err(|e|e.to_string())?;}
   self.last=Some(frame);self.received=Some(Instant::now());self.packets+=1;
  }Ok(())
 }
 fn ready(&self)->Result<(),String>{
  if !self.last.as_ref().is_some_and(|f|matches!(f.version,3|4))||self.received.is_none_or(|t|t.elapsed()>Duration::from_secs(2)){return Err("需要已连接且正在回传的 Studio 固件（协议 3/4）".into());}Ok(())
 }
 fn send_packet(&mut self,op:u8,key:u8,payload:&[u8])->Result<(u8,u16),String>{
  self.seq=self.seq.wrapping_add(1);let bytes=super::synth_studio::packet(op,self.seq,key,payload)?;
  self.port.as_mut().ok_or("串口未连接")?.write_all(&bytes).map_err(|e|e.to_string())?;
  Ok((self.seq,u16::from_le_bytes([bytes[bytes.len()-2],bytes[bytes.len()-1]])))
 }
 fn confirmed(&mut self,op:u8,key:u8,payload:&[u8])->Result<Frame,String>{
  self.ready()?;let (seq,crc)=self.send_packet(op,key,payload)?;let start=Instant::now();
  while start.elapsed()<Duration::from_millis(900){
   self.pump()?;
   if let Some(frame)=self.last.as_ref(){if frame.ack_seq==seq&&frame.ack_op==op&&frame.ack_key==key&&frame.ack_crc==crc{
    if frame.ack_status!=0{return Err(format!("FPGA 拒绝命令：{}",frame.ack_status));}return Ok(frame.clone());
   }}std::thread::sleep(Duration::from_millis(3));
  }Err("FPGA 配置确认超时，未标记为已同步".into())
 }
}
#[tauri::command]
pub async fn synth_patch(state:tauri::State<'_,Mutex<Session>>,key:u8,patch:super::synth_studio::Patch)->Result<Frame,String>{
 if key>=32{return Err("键位越界".into());}let bytes=super::synth_studio::compile(&patch)?;
 // The command runs outside the event loop; serialized ownership prevents ACK theft.
 let mut s=state.lock().map_err(|e|e.to_string())?;
 if (patch.wave_a==4||patch.wave_b==4)&&!s.wave_loaded{return Err("请先上传完整的双帧波表；重新连接后需再次上传".into());}
 s.confirmed(1,key,&bytes)
}
#[tauri::command]
pub fn synth_note(state:tauri::State<Mutex<Session>>,key:u8,pressed:bool,velocity:u8)->Result<(),String>{
 if key>=32||velocity==0||velocity>127{return Err("键位或力度越界".into());}
 let mut s=state.lock().map_err(|e|e.to_string())?;s.ready()?;
 s.send_packet(if pressed{2}else{3},key,&[velocity])?;Ok(())
}
#[tauri::command]
pub fn synth_panic(state:tauri::State<Mutex<Session>>)->Result<(),String>{
 let mut s=state.lock().map_err(|e|e.to_string())?;s.ready()?;s.send_packet(4,0,&[])?;Ok(())
}
#[tauri::command]
pub async fn synth_wave(state:tauri::State<'_,Mutex<Session>>,samples:Vec<i16>)->Result<(),String>{
 if samples.len()!=2048{return Err("需要 A、B 两帧各 1024 个采样".into());}
 let mut s=state.lock().map_err(|e|e.to_string())?;s.ready()?;let volume=s.last.as_ref().map_or(6,|f|f.volume);
 s.confirmed(4,0,&[])?;s.confirmed(6,0,&[0])?;s.wave_loaded=false;
 let start=Instant::now();while start.elapsed()<Duration::from_secs(2){s.pump()?;if s.last.as_ref().is_some_and(|f|f.gain==0){break;}std::thread::sleep(Duration::from_millis(10));}
 if !s.last.as_ref().is_some_and(|f|f.gain==0){return Err("未确认静音，已取消波表上传".into());}
 for (index,chunk) in samples.chunks(32).enumerate(){let bytes:Vec<u8>=chunk.iter().flat_map(|s|s.to_le_bytes()).collect();s.confirmed(5,index as u8,&bytes)?;}
 s.wave_loaded=true;s.confirmed(6,0,&[volume])?;Ok(())
}
