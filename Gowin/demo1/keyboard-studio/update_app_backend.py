from pathlib import Path
ROOT=Path(__file__).resolve().parent
APP=ROOT.parent.parent/'demo_test/desktop-tauri/src-tauri/src'
p=APP/'lib.rs';s=p.read_text();s=s.replace('pub mod synth_debug;','pub mod synth_debug;\npub mod synth_studio;');p.write_text(s)
p=APP/'synth_debug.rs';s=p.read_text()
s=s.replace('pub stages:u8,pub version:u8,','pub stages:u8,pub version:u8,pub ack_seq:u8,pub ack_op:u8,pub ack_status:u8,pub ack_key:u8,pub ack_crc:u16,pub commits:u32,')
s=s.replace('(version==2&&n==64)','(version==2&&n==64)||(version==3&&n==80)')
s=s.replace('if version==2{','if version>=2{')
s=s.replace('result.push(f);','if version==3{f.ack_seq=b[62];f.ack_op=b[63];f.ack_status=b[64];f.ack_key=b[65];f.ack_crc=u16::from_le_bytes([b[66],b[67]]);f.commits=u(68);}\n            result.push(f);')
s=s.replace('pub struct Session {','pub struct Session {seq:u8,heartbeat:Option<Instant>,wave_loaded:bool,')
s=s.replace('Self{port:None,','Self{seq:0,heartbeat:None,wave_loaded:false,port:None,')
s=s.replace('let mut s=state.lock().map_err(|e|e.to_string())?;s.port=None;', '''let mut s=state.lock().map_err(|e|e.to_string())?;
    if s.last.as_ref().is_some_and(|f|f.version==3){let _=s.send_packet(4,0,&[]);}s.port=None;s.wave_loaded=false;''')
s=s.replace('serialport::new(name,115200).timeout','serialport::new(name,115200).dtr_on_open(false).timeout')
start=s.index('    let mut s=state.lock()',s.index('pub fn synth_snapshot'))
end=s.index('\n}\npub fn run()',start)
s=s[:start]+'''    let mut s=state.lock().map_err(|e|e.to_string())?;s.pump()?;
    if s.last.as_ref().is_some_and(|f|f.version==3)&&s.heartbeat.is_none_or(|t|t.elapsed()>Duration::from_millis(500)){
        s.send_packet(7,0,&[])?;s.heartbeat=Some(Instant::now());
    }
    Ok(View{connected:s.port.is_some(),packets:s.packets,bad:s.parser.bad,age_ms:s.received.map(|t|t.elapsed().as_millis()),frame:s.last.clone()})'''+s[end:]
s=s.replace('synth_connect,synth_snapshot,synth_command,super::list_ports','synth_connect,synth_snapshot,synth_command,synth_patch,synth_note,synth_panic,synth_wave,super::list_ports')
s=s.replace('Tang Synth · 完整链路调试','Tang Synth Studio · 音色与链路')
s+='''
impl Session {
 fn pump(&mut self)->Result<(),String>{
  let mut bytes=[0u8;4096];let mut n=0;
  if let Some(port)=self.port.as_mut(){let available=port.bytes_to_read().map_err(|e|e.to_string())? as usize;if available>0{n=port.read(&mut bytes[..available.min(4096)]).map_err(|e|e.to_string())?;}}
  if self.opened.is_some_and(|t|t.elapsed()<Duration::from_millis(1500)){n=0;}
  for frame in self.parser.feed(&bytes[..n]){
   if let Some(file)=self.log.as_mut(){serde_json::to_writer(&mut *file,&frame).map_err(|e|e.to_string())?;file.write_all(b"\\n").map_err(|e|e.to_string())?;}
   self.last=Some(frame);self.received=Some(Instant::now());self.packets+=1;
  }Ok(())
 }
 fn ready(&self)->Result<(),String>{
  if !self.last.as_ref().is_some_and(|f|f.version==3)||self.received.is_none_or(|t|t.elapsed()>Duration::from_secs(2)){return Err("需要已连接且正在回传的 Studio 固件（协议 3）".into());}Ok(())
 }
 fn send_packet(&mut self,op:u8,key:u8,payload:&[u8])->Result<(u8,u16),String>{
  self.seq=self.seq.wrapping_add(1);let bytes=super::synth_studio::packet(op,self.seq,key,payload)?;
  self.port.as_mut().ok_or("串口未连接")?.write_all(&bytes).map_err(|e|e.to_string())?;
  Ok((self.seq,u16::from_le_bytes([bytes[69],bytes[70]])))
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
'''
p.write_text(s)
print('Added native Studio compiler and acknowledged parameter transport')
