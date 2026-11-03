//! Hardware snapshots are authoritative after standalone SD operations.
//! Preserve exact parameter words even when no editable factory topology matches.
use super::{Slot,Command,NativePatch,native::NativeOperator,Operator,compile,compile_native,library,UNITY,RATE,scale_level};
use serde::{Serialize,Deserialize};

#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct HardwarePatch { pub name:String,pub words:Vec<u32> }

pub(super) fn words(commands:&[Command])->Vec<u32>{
    let mut out=vec![0;110];
    for c in commands {
        let (base,size)=match c.opcode {0xa1=>(0,6),0xa2=>(36,8),0xb0=>(84,5),0xb1=>(94,2),_=>continue};
        let start=base+usize::from(c.address&7)*size;
        if start+size<=out.len(){out[start..start+size].copy_from_slice(&c.words[..size]);}
    }
    out
}
pub(super) fn selector(index:usize,slot:u8)->(u8,u32){
    let (kind,offset,size)=if index<36 {(0,0,6)}else if index<84{(1,36,8)}else if index<94{(2,84,5)}else{(3,94,2)};
    let n=index-offset;(kind,u32::from(slot)*64+((n/size)*8+n%size) as u32)
}
#[derive(Deserialize)]
struct Known {name:String,commands:Vec<Command>}
fn known_name(raw:&[u32])->Option<String>{
    static BANK:std::sync::OnceLock<Vec<Known>>=std::sync::OnceLock::new();
    BANK.get_or_init(||serde_json::from_str(include_str!("../assets/sd-preset-commands.json")).expect("SD preset catalogue"))
        .iter().find(|p|words(&p.commands)==raw).map(|p|p.name.clone())
}
pub(super) fn decode(raw:Vec<u32>,revision:u32,slot:u8)->Result<Slot,String>{
    if raw.len()!=110{return Err("硬件音色快照不完整".into());}
    let name=known_name(&raw).unwrap_or_else(||format!("SD 音色 · Slot {}",slot+1));
    let snapshot=Some(HardwarePatch{name:name.clone(),words:raw.clone()});
    if (0..6).all(|op|raw[op*6+4]&(1<<15)==0){
        let mut operators=Vec::new();
        for op in 0..6 {
            let c=&raw[op*6..op*6+6];let e=&raw[36+op*8..44+op*8];let flags=c[4];
            let waves=["sine","triangle","saw","pulse","noise","wavetable"];
            let mode=((flags>>10)&3) as usize;
            let wave=waves.get(((flags>>7)&7) as usize).ok_or("硬件波形编号不支持")?;
            let fixed=flags&(1<<13)!=0;
            operators.push(NativeOperator{enabled:flags&(1<<12)!=0,carrier:flags&64!=0,wave:(*wave).into(),mode:["pm","fm","am","ring"][mode].into(),
                sources:(0..6).filter(|i|flags&(1<<i)!=0).map(|i|i as u8).collect(),
                ratio:(!fixed).then_some(f64::from(c[0])/65536.),fixed_hz:fixed.then_some(f64::from(c[0])*RATE/4294967296.),
                gain:f64::from(c[1])/f64::from(UNITY),depth:if mode>=2{f64::from(c[2])/f64::from(UNITY)}else{f64::from(c[2] as i32)/4294967296.},
                feedback:f64::from(c[3] as i32)/4294967296.,morph:if *wave=="wavetable"{f64::from(c[5])/65536.}else{0.},
                pulse_width:if *wave=="wavetable"{0.5}else{f64::from(c[5])/4294967296.},
                levels:std::array::from_fn(|n|f64::from(e[n])/f64::from(UNITY)),
                segment_ms:std::array::from_fn(|n|f64::from(UNITY)/f64::from(e[n+4].max(1))*1000./RATE)});
        }
        let patch=NativePatch{name,operators};
        if let Ok((commands,mut value))=compile_native(patch,slot,revision){
            if words(&commands)[..84]==raw[..84]{value.snapshot=snapshot;return Ok(value);}
        }
    }else{
        let operators:Vec<Operator>=(0..6).map(|op|{
            let c=&raw[op*6..op*6+6];let e=&raw[36+op*8..44+op*8];let flags=c[4];let fixed=flags&(1<<13)!=0;
            Operator{output:(0..=99).find(|v|scale_level(*v).ok()==Some((flags>>16)&127)).unwrap_or(0),
                rates:std::array::from_fn(|n|(0..=99).find(|v|(u32::from(*v)*41)>>6==e[n+4]).unwrap_or(0)),
                levels:std::array::from_fn(|n|(0..=99).find(|v|scale_level(*v).is_ok_and(|l|(l>>1)<<6==e[n])).unwrap_or(0)),
                ratio:(!fixed).then_some(f64::from(c[0])/65536.),fixed_hz:fixed.then_some(f64::from(c[0])*RATE/4294967296.)}
        }).collect();
        for preset in library().presets {
            if let Ok((commands,mut value))=compile(preset.program,slot,revision,Some(operators.clone())){
                if words(&commands)[..84]==raw[..84]{value.snapshot=snapshot;return Ok(value);}
            }
        }
    }
    Ok(Slot{program:None,revision,operators:vec![],native:None,snapshot})
}

#[cfg(test)]mod tests{
    use super::*;
    #[test]fn all_prepared_presets_have_editable_exact_snapshots(){
        let bank:Vec<Known>=serde_json::from_str(include_str!("../assets/sd-preset-commands.json")).unwrap();
        assert_eq!(bank.len(),49);
        for entry in bank{
            let raw=words(&entry.commands);let value=decode(raw.clone(),42,2).unwrap();
            assert_eq!(value.snapshot.as_ref().unwrap().words,raw);
            assert!(value.native.is_some()||value.program.is_some(),"{}",entry.name);
            let commands=if let Some(patch)=value.native {compile_native(patch,2,42).unwrap().0}
                else {compile(value.program.unwrap(),2,42,Some(value.operators)).unwrap().0};
            assert_eq!(words(&commands)[..84],raw[..84],"{}",entry.name);
        }
    }
}
