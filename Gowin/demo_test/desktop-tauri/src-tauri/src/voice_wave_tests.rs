//! Protocol-level faults: busy hardware, uncertain write, replay and durable progress.
use super::*;
use std::{collections::VecDeque,io};
use serialport::*;

#[derive(Default)]
struct Hardware {
    sequence:u32,cache:Option<(Vec<u8>,Vec<u8>)>,writes:Vec<(u32,u32)>,requests:Vec<Vec<u8>>,
    busy_at:Option<u32>,busy:bool,always_busy:bool,lose_ack_at:Option<u32>,read_error:bool,
    replies:VecDeque<u8>,enabled:bool,
}
#[derive(Clone)]
struct Port(Arc<Mutex<Hardware>>);
impl Write for Port {
    fn write(&mut self,raw:&[u8])->io::Result<usize>{
        assert_eq!(raw.len(),52);assert_eq!(crc16(&raw[..50]),u16::from_le_bytes([raw[50],raw[51]]));
        let mut h=self.0.lock().unwrap();h.requests.push(raw.to_vec());
        let seq=u32_at(raw,4);
        if let Some((old,response))=&h.cache {if old==raw {let response=response.clone();h.replies.extend(response);return Ok(raw.len());}}
        assert_eq!(seq,h.sequence);h.sequence+=1;
        let mut response=vec![0;32];response[..8].copy_from_slice(&raw[..8]);response[1]=0x52;response[25]=raw[8];response[26]=raw[9];
        let index=u32_at(raw,10);
        if raw[8]==0xa7 {h.enabled=index&1!=0;if index&4!=0 {h.busy=false;}}
        if raw[8]==0xa8 {
            if h.busy_at==Some(index){h.busy=true;h.busy_at=None;}
            if h.busy||h.always_busy||h.enabled {response[16]=10;}else{h.writes.push((index,u32_at(raw,14)));}
        }
        let c=crc16(&response[..30]);response[30..].copy_from_slice(&c.to_le_bytes());h.cache=Some((raw.to_vec(),response.clone()));
        if raw[8]==0xa8&&h.lose_ack_at==Some(index){h.lose_ack_at=None;h.read_error=true;}else{h.replies.extend(response);}
        Ok(raw.len())
    }
    fn flush(&mut self)->io::Result<()>{Ok(())}
}
impl Read for Port {
    fn read(&mut self,out:&mut [u8])->io::Result<usize>{
        let mut h=self.0.lock().unwrap();
        if h.read_error {h.read_error=false;return Err(io::Error::new(io::ErrorKind::ConnectionReset,"simulated unplug after write"));}
        if h.replies.is_empty(){return Err(io::Error::new(io::ErrorKind::TimedOut,"empty"));}
        let count=out.len().min(h.replies.len());for byte in &mut out[..count]{*byte=h.replies.pop_front().unwrap();}Ok(count)
    }
}
impl SerialPort for Port {
    fn name(&self)->Option<String>{Some("WAVE_TEST".into())}
    fn baud_rate(&self)->serialport::Result<u32>{Ok(115200)}
    fn data_bits(&self)->serialport::Result<DataBits>{Ok(DataBits::Eight)}
    fn flow_control(&self)->serialport::Result<FlowControl>{Ok(FlowControl::None)}
    fn parity(&self)->serialport::Result<Parity>{Ok(Parity::None)}
    fn stop_bits(&self)->serialport::Result<StopBits>{Ok(StopBits::One)}
    fn timeout(&self)->Duration{Duration::from_millis(15)}
    fn set_baud_rate(&mut self,_:u32)->serialport::Result<()>{Ok(())}
    fn set_data_bits(&mut self,_:DataBits)->serialport::Result<()>{Ok(())}
    fn set_flow_control(&mut self,_:FlowControl)->serialport::Result<()>{Ok(())}
    fn set_parity(&mut self,_:Parity)->serialport::Result<()>{Ok(())}
    fn set_stop_bits(&mut self,_:StopBits)->serialport::Result<()>{Ok(())}
    fn set_timeout(&mut self,_:Duration)->serialport::Result<()>{Ok(())}
    fn write_request_to_send(&mut self,_:bool)->serialport::Result<()>{Ok(())}
    fn write_data_terminal_ready(&mut self,_:bool)->serialport::Result<()>{Ok(())}
    fn read_clear_to_send(&mut self)->serialport::Result<bool>{Ok(true)}
    fn read_data_set_ready(&mut self)->serialport::Result<bool>{Ok(true)}
    fn read_ring_indicator(&mut self)->serialport::Result<bool>{Ok(false)}
    fn read_carrier_detect(&mut self)->serialport::Result<bool>{Ok(true)}
    fn bytes_to_read(&self)->serialport::Result<u32>{Ok(self.0.lock().unwrap().replies.len() as u32)}
    fn bytes_to_write(&self)->serialport::Result<u32>{Ok(0)}
    fn clear(&self,_:ClearBuffer)->serialport::Result<()>{Ok(())}
    fn try_clone(&self)->serialport::Result<Box<dyn SerialPort>>{Ok(Box::new(self.clone()))}
    fn set_break(&self)->serialport::Result<()>{Ok(())}
    fn clear_break(&self)->serialport::Result<()>{Ok(())}
}
fn fixture()->(Engine,Arc<Mutex<Hardware>>,tempfile::TempDir){
    let dir=tempfile::tempdir().unwrap();let h=Arc::new(Mutex::new(Hardware::default()));
    let mut e=Engine::new(dir.path().into());e.name=Some("WAVE_TEST".into());e.port=Some(Box::new(Port(h.clone())));e.abi=Some(ABI);
    (e,h,dir)
}
#[test]
fn physical_key_busy_is_cleared_without_losing_sample(){
    let (mut e,h,_dir)=fixture();e.wave_begin("test".into(),vec![-32768;2048],0.).unwrap();h.lock().unwrap().busy_at=Some(7);
    e.wave_step().unwrap();let h=h.lock().unwrap();
    assert_eq!(e.saved.wave.as_ref().unwrap().next,16);assert_eq!(e.saved.wave.as_ref().unwrap().busy_recoveries,1);
    assert_eq!(h.writes,(0..16).map(|i|(i,(-67108864i32) as u32)).collect::<Vec<_>>());assert!(!h.enabled);
    assert!(e.saved.pending.is_none());assert_eq!(h.requests.iter().filter(|r|r[8]==0xa8&&u32_at(r,10)==7).count(),2);
}
#[test]
fn uncertain_write_replays_identical_packet_after_process_restart(){
    let (mut e,h,dir)=fixture();e.wave_begin("resume".into(),vec![32767;2048],0.4).unwrap();h.lock().unwrap().lose_ack_at=Some(3);
    assert!(e.wave_step().is_err());assert_eq!(e.saved.wave.as_ref().unwrap().next,3);
    let raw=e.saved.pending.as_ref().unwrap().raw.clone();drop(e);
    let mut next=Engine::new(dir.path().into());next.name=Some("WAVE_TEST".into());next.saved=serde_json::from_slice(&std::fs::read(next.path().unwrap()).unwrap()).unwrap();next.port=Some(Box::new(Port(h.clone())));next.abi=Some(ABI);
    assert_eq!(next.saved.pending.as_ref().unwrap().raw,raw);next.finish().unwrap();assert_eq!(next.saved.wave.as_ref().unwrap().next,4);
    next.wave_step().unwrap();let h=h.lock().unwrap();assert_eq!(h.writes.len(),20);
    assert_eq!(h.requests[4],h.requests[5]);assert!(h.writes.iter().all(|(_,v)|*v==67106816));
}
#[test]
fn permanent_busy_stops_boundedly_and_finish_never_enables_partial_wave(){
    let (mut e,h,_dir)=fixture();e.wave_begin("busy".into(),vec![0;2048],0.).unwrap();h.lock().unwrap().always_busy=true;
    assert!(e.wave_step().is_err());assert_eq!(e.saved.wave.as_ref().unwrap().next,0);assert_eq!(e.saved.wave.as_ref().unwrap().busy_recoveries,3);
    assert!(e.wave_finish().is_err());assert!(!h.lock().unwrap().enabled);assert!(e.saved.pending.is_none());
}

#[test]
#[ignore = "requires exclusive COM4 access and a paused real wave transfer"]
fn real_board_resume_with_note_injection(){
    let root=PathBuf::from(std::env::var_os("LOCALAPPDATA").unwrap()).join("SynthString/voice-engine");
    let mut e=Engine::new(root);e.connect("COM4".into(),false).unwrap();
    let original=e.saved.wave.clone().expect("requires existing user transfer");
    let keys=serde_json::to_value(&e.saved.keys).unwrap();let slots=serde_json::to_value(&e.saved.slots).unwrap();
    println!("resume original={} of 2048",original.next);
    // Same A4 allocation as the keyboard, with a host-namespace Note-ID.
    e.request(0,0xa4,e.saved.keys[0].slot,&[0x6fffff01,23012828,UNITY,UNITY/2,0x8000323c],Effect::None).unwrap();
    assert_ne!(e.read(0x38).unwrap(),0,"must reproduce occupied muted voice");
    e.wave_step().unwrap();assert_eq!(e.saved.wave.as_ref().unwrap().busy_recoveries,original.busy_recoveries+1);
    let checkpoint=e.saved.wave.as_ref().unwrap().next;
    e.action(Action::Disconnect).unwrap();e.connect("COM4".into(),false).unwrap();
    assert_eq!(e.saved.wave.as_ref().unwrap().next,checkpoint);
    while e.saved.wave.as_ref().unwrap().next<2048 {e.wave_step().unwrap();}
    assert_eq!(e.saved.wave.as_ref().unwrap().samples,original.samples);
    e.wave_finish().unwrap();assert_eq!(e.saved.wave_name.as_deref(),Some(original.name.as_str()));
    assert_eq!(serde_json::to_value(&e.saved.keys).unwrap(),keys);assert_eq!(serde_json::to_value(&e.saved.slots).unwrap(),slots);
    for _ in 0..9{e.poll().unwrap();}
    assert_eq!(e.telemetry.overruns+e.telemetry.underruns as u32+e.telemetry.bad_packets as u32+e.telemetry.pcm_dropped,0);
    assert_eq!(e.retries,0);assert!(!e.saved.pending.is_some());
    e.action(Action::Disconnect).unwrap();
    println!("PASS real COM4: busy reproduced and repaired, reconnect checkpoint={}, full wave restored; original key/patch configuration preserved",checkpoint);
}
