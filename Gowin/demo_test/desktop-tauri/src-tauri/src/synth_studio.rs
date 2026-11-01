//! 48.828125 kHz Studio firmware profiles. Distinct from the legacy 96 kHz protocol.
use serde::{Deserialize,Serialize};
pub const SAMPLE_RATE:f64=50_000_000.0/1024.0;
#[derive(Clone,Debug,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Envelope {pub attack:f64,pub decay:f64,pub sustain:f64,pub release:f64}
#[derive(Clone,Debug,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Patch {
 pub name:String,pub note:u8,pub velocity:u8,pub mode:String,
 pub wave_a:u8,pub wave_b:u8,pub ratio:f64,pub depth:f64,pub gain_a:f64,pub gain_b:f64,
 pub amp:Envelope,pub modulation:Envelope,pub cutoff:f64,pub resonance:f64,pub filter:u8,pub morph:f64,
}
pub fn crc(bytes:&[u8])->u16{let mut value=0xffffu16;for byte in bytes{value^=(*byte as u16)<<8;for _ in 0..8{value=if value&0x8000!=0{(value<<1)^0x1021}else{value<<1};}}value}
pub fn packet(op:u8,seq:u8,key:u8,payload:&[u8])->Result<Vec<u8>,String>{
 if payload.len()>64||key>=128{return Err("命令长度或目标越界".into());}
 let short=[2,3,4,6,7].contains(&op)&&payload.len()<=1;
 let mut result=vec![0xa5,if short{0xc4}else{0xc3},op,seq,key];result.extend_from_slice(payload);result.resize(if short{6}else{69},0);
 result.extend_from_slice(&crc(&result).to_le_bytes());Ok(result)
}
fn range(x:f64,low:f64,high:f64,name:&str)->Result<(),String>{if !x.is_finite()||x<low||x>high{Err(format!("{name} 必须位于 {low}～{high}"))}else{Ok(())}}
fn step(ms:f64)->u32{let mut value=(262143.0*16384.0/(ms*SAMPLE_RATE/1000.0).max(1.0)).round() as u64;let mut exponent=0;while value>2047{value=(value+1)/2;exponent+=1;}(value as u32)|(exponent<<11)}
fn put(bytes:&mut [u8;64],value:u64,start:usize,width:usize){for bit in 0..width{if value&(1<<bit)!=0{bytes[(start+bit)/8]|=1<<((start+bit)%8);}}}
fn envelope(bytes:&mut [u8;64],e:&Envelope,start:usize)->Result<(),String>{
 for (value,name) in [(e.attack,"起音"),(e.decay,"衰减"),(e.release,"释音")]{range(value,0.0,5000.0,name)?;}range(e.sustain,0.0,100.0,"保持")?;
 put(bytes,1,start,1);put(bytes,step(e.attack) as u64,start+1,18);put(bytes,step(e.decay) as u64,start+19,18);
 put(bytes,(e.sustain/100.0*262143.0).round() as u64,start+37,18);put(bytes,step(e.release) as u64,start+55,18);Ok(())
}
pub fn compile(p:&Patch)->Result<[u8;64],String>{
 if p.note>127||p.velocity==0||p.velocity>127||p.wave_a>4||p.wave_b>4||![1,4,6].contains(&p.filter){return Err("音符、力度、波形或滤波类型越界".into());}
 range(p.ratio,1.0/256.0,8.0,"频率比")?;range(p.depth,0.0,if p.mode=="fm"{2.0}else{1.0},"调制深度")?;
 for (x,n) in [(p.gain_a,"振荡器 A 音量"),(p.gain_b,"振荡器 B 音量"),(p.morph,"波表位置"),(p.resonance,"共振")]{range(x,0.0,100.0,n)?;}
 range(p.cutoff,30.0,10000.0,"截止频率")?;
 if !["mix","fm","am","ring"].contains(&p.mode.as_str()){return Err("当前流水线尚未接入 PCM 采样钢琴模式".into());}
 let hz=440.0*2f64.powf((p.note as f64-69.0)/12.0);let increment=(hz*4294967296.0/SAMPLE_RATE).round();
 if hz*p.ratio>=SAMPLE_RATE/2.0{return Err("调制振荡器频率超过奈奎斯特频率，请降低频率比或音高".into());}
 let mut b=[0u8;64];put(&mut b,(increment*p.ratio).round() as u64,0,32);put(&mut b,increment as u64,32,32);
 put(&mut b,if p.mode=="fm"{(increment*p.depth).round() as u64}else{0},64,32);
 envelope(&mut b,&p.amp,96)?;envelope(&mut b,&p.modulation,376)?;
 put(&mut b,if p.wave_a==4||p.wave_b==4{6}else{0},193,3);put(&mut b,p.wave_b as u64,171,3);put(&mut b,p.wave_a as u64,174,3);put(&mut b,(p.morph/100.0*65535.0).round() as u64,177,16);
 put(&mut b,if p.mode=="am"||p.mode=="ring"{(p.depth*67108864.0).round() as u64}else{0},196,32);
 put(&mut b,match p.mode.as_str(){"am"=>1,"ring"=>2,_=>0},228,2);
 put(&mut b,(2.0*(std::f64::consts::PI*p.cutoff/(2.0*SAMPLE_RATE)).sin()*268435456.0).round() as u64,230,32);
 put(&mut b,((2.0-1.8*p.resonance/100.0)*268435456.0).round() as u64,262,32);
 put(&mut b,0x0051eb85,294,32);put(&mut b,0x10000000,326,32);put(&mut b,p.filter as u64,358,3);
 put(&mut b,p.velocity as u64,361,7);put(&mut b,1,368,1);
 let scale=if p.mode=="mix"{(p.gain_a+p.gain_b).max(100.0)}else{100.0};
 put(&mut b,(p.gain_a/scale*65535.0).round() as u64,449,16);put(&mut b,(p.gain_b/scale*65535.0).round() as u64,465,16);
 put(&mut b,u64::from(p.mode=="mix"),481,1);Ok(b)
}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn crc_and_payload(){assert_eq!(crc(b"123456789"),0x29b1);let p=packet(1,3,12,b"TP012345678").unwrap();assert_eq!(p.len(),71);assert_eq!(crc(&p[..69]),u16::from_le_bytes([p[69],p[70]]));assert!(packet(1,0,0,&[0;65]).is_err());}
 #[test]fn precise_step(){assert_eq!(step(0.0),0xb400);assert!(step(5000.0)>0);}
 #[test]fn foundation_library_matches_independent_profile_model(){
  let library:serde_json::Value=serde_json::from_str(include_str!("../../src/data/foundation-library.json")).unwrap();
  let expected:serde_json::Value=serde_json::from_str(include_str!("../../tests/data/foundation-profiles.json")).unwrap();
  let presets=library["presets"].as_array().unwrap();let demos=library["demo"].as_array().unwrap();
  assert_eq!(presets.len(),16);assert_eq!(demos.len(),32);
  let hex=|p:&Patch|compile(p).unwrap().iter().map(|b|format!("{b:02x}")).collect::<String>();
  for (entry,vector) in presets.iter().zip(expected["presets"].as_array().unwrap()){
   assert_eq!(entry["id"],vector["id"]);
   let patch:Patch=serde_json::from_value(entry["patch"].clone()).unwrap();
   assert_eq!(hex(&patch),vector["hex"].as_str().unwrap(),"preset {}",patch.name);
  }
  for (entry,vector) in demos.iter().zip(expected["demo"].as_array().unwrap()){
   assert_eq!(entry["id"],vector["id"]);assert_eq!(entry["note"],vector["note"]);
   let source=presets.iter().find(|p|p["id"]==entry["id"]).unwrap();
   let mut patch:Patch=serde_json::from_value(source["patch"].clone()).unwrap();patch.note=entry["note"].as_u64().unwrap() as u8;
   assert_eq!(hex(&patch),vector["hex"].as_str().unwrap(),"demo {} note {}",patch.name,patch.note);
  }
  assert_eq!(demos[26..29].iter().map(|p|p["note"].as_u64().unwrap()).collect::<Vec<_>>(),vec![60,64,67]);
  assert_eq!(demos[29..32].iter().map(|p|p["note"].as_u64().unwrap()).collect::<Vec<_>>(),vec![60,63,67]);
 }
}
