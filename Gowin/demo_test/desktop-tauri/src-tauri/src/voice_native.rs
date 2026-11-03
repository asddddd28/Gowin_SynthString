//! Native Voice ABI compiler. DX factory patches keep their separate log-EG path.
use super::{Command, Slot, UNITY, RATE};
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct NativeOperator {
    pub enabled: bool, pub carrier: bool, pub wave: String, pub mode: String,
    pub sources: Vec<u8>, pub ratio: Option<f64>, pub fixed_hz: Option<f64>,
    pub gain: f64, pub depth: f64, pub feedback: f64,
    pub morph: f64, pub pulse_width: f64,
    pub levels: [f64; 4], pub segment_ms: [f64; 4],
}
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct NativePatch { pub name: String, pub operators: Vec<NativeOperator> }

fn bounded(value:f64, low:f64, high:f64, name:&str)->Result<f64,String> {
    if value.is_finite() && (low..=high).contains(&value) {Ok(value)}
    else {Err(format!("{name} 必须在 {low}..{high} 范围内"))}
}
fn phase(value:f64)->u32 {(value*4294967296.0).round() as i64 as u32}

pub fn compile_native(patch:NativePatch,slot:u8,revision:u32)->Result<(Vec<Command>,Slot),String> {
    if slot>3 || revision==0 || patch.name.trim().is_empty() || patch.name.chars().count()>80 || patch.operators.len()!=6 {
        return Err("音色需要名称、有效槽位以及六行算子（闲置行可禁用）".into());
    }
    let mut commands=vec![Command{opcode:0xa0,address:slot,words:vec![revision]}];
    let mut carriers=0;
    for (index,op) in patch.operators.iter().enumerate() {
        let wave=match op.wave.as_str(){"sine"=>0,"triangle"=>1,"saw"=>2,"pulse"=>3,"noise"=>4,"wavetable"=>5,_=>return Err("未知波形".into())};
        let mode=match op.mode.as_str(){"pm"=>0,"fm"=>1,"am"=>2,"ring"=>3,_=>return Err("未知调制模式".into())};
        let mut mask=0u32;
        for source in &op.sources {
            if usize::from(*source)>=index || mask&(1<<source)!=0 {return Err("调制源必须是不重复的前序算子，反馈使用专用参数".into());}
            mask|=1<<source;
        }
        let mut flags=mask|((op.carrier as u32)<<6)|(wave<<7)|(mode<<10)|((op.enabled as u32)<<12)|(1<<14);
        let tuning=match (op.ratio,op.fixed_hz) {
            (Some(r),None)=>(bounded(r,0.,16.,"频率比")?*65536.).round() as u32,
            (None,Some(f))=>{flags|=1<<13;(bounded(f,0.,RATE/2.-1.,"固定频率")?*4294967296.0/RATE).round() as u32},
            _=>return Err("请选择比率或固定频率之一".into()),
        };
        let gain=(bounded(op.gain,0.,1.,"算子电平")?*UNITY as f64).round() as u32;
        let depth=if mode>=2 {(bounded(op.depth,0.,1.,"AM/Ring 深度")?*UNITY as f64).round() as u32}
            else {phase(bounded(op.depth,-0.5,0.499999,"PM/FM 深度（周期）")?)};
        let feedback=phase(bounded(op.feedback,-0.5,0.499999,"历史反馈")?);
        bounded(op.morph,0.,1.,"波表位置")?;bounded(op.pulse_width,0.,1.,"脉冲宽度")?;
        let shape=if wave==5 {(op.morph*65536.).round() as u32}else{(op.pulse_width*4294967296.0).round().min(u32::MAX as f64) as u32};
        if op.levels[3]!=0. {return Err("释放目标 L4 必须为零".into());}
        let mut eg=Vec::with_capacity(8);
        for level in op.levels {eg.push((bounded(level,0.,1.,"包络电平")?*UNITY as f64).round() as u32);}
        for time in op.segment_ms {eg.push((UNITY as f64/(bounded(time,0.,60000.,"满量程斜坡时间")?*RATE/1000.).max(1.)).round().max(1.) as u32);}
        let address=slot*8+index as u8;
        commands.push(Command{opcode:0xa1,address,words:vec![tuning,gain,depth,feedback,flags,shape]});
        commands.push(Command{opcode:0xa2,address,words:eg});
        if op.enabled&&op.carrier {carriers+=1;}
    }
    if carriers==0 {return Err("至少启用一个输出载波".into());}
    commands.push(Command{opcode:0xa3,address:slot,words:vec![]});
    Ok((commands,Slot{program:None,revision,operators:vec![],native:Some(patch),snapshot:None}))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn patch()->NativePatch {
        let op=NativeOperator{enabled:true,carrier:false,wave:"sine".into(),mode:"pm".into(),sources:vec![],ratio:Some(2.),fixed_hz:None,gain:1.,depth:0.,feedback:0.,morph:0.,pulse_width:0.5,levels:[1.,0.7,0.7,0.],segment_ms:[5.,80.,80.,180.]};
        let mut ops=vec![op;6];for op in &mut ops[2..] {op.enabled=false;}
        ops[1].carrier=true;ops[1].ratio=Some(1.);ops[1].sources=vec![0];ops[1].mode="am".into();ops[1].depth=0.75;
        NativePatch{name:"AM test".into(),operators:ops}
    }
    #[test] fn am_wire_units_and_envelope() {
        let (commands,slot)=compile_native(patch(),2,7).unwrap();
        assert_eq!(commands.len(),14);assert_eq!(commands[3].address,17);
        assert_eq!(commands[3].words,vec![65536,UNITY,UNITY*3/4,0,1|64|(2<<10)|(1<<12)|(1<<14),1<<31]);
        assert_eq!(commands[4].words[0],UNITY);assert_eq!(commands[4].words[3],0);
        assert_eq!(commands[4].words[4],274878);assert!(slot.native.is_some());
    }
    #[test] fn wave_morph_and_signed_fm() {
        let mut p=patch();p.operators[1].wave="wavetable".into();p.operators[1].morph=0.25;p.operators[1].mode="fm".into();p.operators[1].depth=-0.125;
        let (c,_)=compile_native(p,0,1).unwrap();assert_eq!(c[3].words[2],0xe0000000);assert_eq!(c[3].words[5],16384);
    }
    #[test] fn rejects_invalid_graph_and_numbers_before_io() {
        let mut p=patch();p.operators[0].sources=vec![1];assert!(compile_native(p,0,1).is_err());
        let mut p=patch();p.operators[1].gain=f64::NAN;assert!(compile_native(p,0,1).is_err());
        let mut p=patch();p.operators[1].levels[3]=0.1;assert!(compile_native(p,0,1).is_err());
        let mut p=patch();p.operators[1].depth=1.1;assert!(compile_native(p,0,1).is_err());
    }
}
