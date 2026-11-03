//! User-facing key assignment and passive monitor acquisition. Four patches are
//! allocated by ownership, never by silently evicting another key's sound.
use super::*;

#[derive(Clone,Serialize,Deserialize,Debug,PartialEq)]
pub struct KeyMapping { pub slot:u8,pub note:u8,pub velocity:u8 }
pub fn default_keys()->Vec<KeyMapping> {(0..32).map(|k|KeyMapping{slot:0,note:48+k,velocity:100}).collect()}

#[derive(Clone,Default,Serialize)]
pub struct MonitorView {
    pub available:bool,pub samples:Vec<i16>,pub captured_at_ms:Option<u128>,pub generation:u16,
    pub latency_cycles:u32,pub max_latency_cycles:u32,pub observations:u32,pub key:u8,
    pub capture_progress:usize,
}

pub fn choose_slot(keys:&[KeyMapping],key:usize,scope:&str)->Result<u8,String> {
    if keys.len()!=32||key>=32{return Err("按键编号越界".into());}
    let current=keys[key].slot;
    if current>3||keys.iter().any(|k|k.slot>3){return Err("按键映射损坏".into());}
    if scope=="all"||scope=="sound" {return Ok(current);}
    if scope!="key" {return Err("请选择当前键、共享此音色的键或全部键".into());}
    if keys.iter().filter(|k|k.slot==current).count()==1 {return Ok(current);}
    (0..4).find(|s|!keys.iter().any(|k|k.slot==*s)).ok_or_else(||"当前已有 4 种不同音色在使用。可选择“共享此音色的键”统一修改，或先将其他键合并到一种音色；不会覆盖其他键。".into())
}


// A retained slot belongs to a recording even after no live key maps to it.
pub fn choose_slot_retained(keys:&[KeyMapping],key:usize,scope:&str,locked:u8)->Result<u8,String>{
    if keys.len()!=32||key>=32||!["key","sound","all"].contains(&scope){return Err("无效的按键或应用范围".into());}
    if keys.iter().any(|k|k.slot>3){return Err("按键映射损坏".into());}
    let locked=locked&15;
    // No recording owns a slot: retain the key-sharing guidance instead of
    // suggesting that clearing a nonexistent loop can free the live mappings.
    if locked==0{return choose_slot(keys,key,scope);}
    if let Ok(slot)=choose_slot(keys,key,scope){if locked&(1<<slot)==0{return Ok(slot);}}
    let current=keys[key].slot;
    (0..4).find(|slot|locked&(1<<slot)==0 && !keys.iter().enumerate().any(|(i,k)|{
        let affected=scope=="all"||(scope=="sound"&&k.slot==current)||(scope=="key"&&i==key);
        !affected && k.slot==*slot
    })).ok_or_else(||{
        let retained=(0..4).filter(|s|locked&(1<<s)!=0).map(|s|(s+1).to_string()).collect::<Vec<_>>().join("、");
        if locked==15 {
            format!("4 个音色槽均由录音层保留（槽 {retained}），暂停回放不会释放。可复用已载入音色；清空音序会删除所有录音层并释放保留槽。")
        }else{
            format!("没有可替换的音色槽：录音保留槽 {retained}，其余槽被本次范围外的琴键引用。可复用已载入音色，或扩大载入范围为“共享此音色的键”/“全部 32 键”；清空音序只释放录音占用，不会合并琴键音色。")
        }
    })
}

impl Engine {
    pub(super) fn discover_workspace(&mut self)->Result<(),String> {
        self.monitor=MonitorView::default();self.capture_samples.clear();self.capture_chunk=None;
        let response=match self.request(3,0,0,&[],Effect::None) {
            Ok(r)=>r,
            Err(e) if e=="通信控制器拒绝请求，状态5"=>return Ok(()),
            Err(e)=>return Err(e),
        };
        if u32_at(&response,8)!=0x53544d31||u32_at(&response,12)!=1{return Err("未知监测接口版本".into());}
        self.monitor.available=true;
        // Read back the authoritative board map; never infer it from stale UI settings.
        let mut keys=Vec::new();
        for key in 0..32 {
            let r=self.request(3,4,key,&[],Effect::None)?;let d=u32_at(&r,12);
            keys.push(KeyMapping{slot:(d&3) as u8,note:((d>>2)&127) as u8,velocity:((d>>9)&127) as u8});
        }
        self.saved.keys=keys;self.save()
    }
    pub(super) fn poll_monitor(&mut self)->Result<(),String> {
        if !self.monitor.available{return Ok(());}
        let r=self.request(3,3,0,&[],Effect::None)?;
        self.monitor.latency_cycles=u32_at(&r,8);self.monitor.max_latency_cycles=u32_at(&r,12);
        self.monitor.observations=u32_at(&r,16);self.monitor.key=((u32_at(&r,20)>>3)&31) as u8;
        Ok(())
    }
    pub(super) fn capture_step(&mut self)->Result<(),String> {
        if !self.monitor.available{return Err("当前固件尚未提供 PCM 监测接口".into());}
        if let Some(chunk)=self.capture_chunk {
            if chunk==0 {let status=self.request(3,3,0,&[],Effect::None)?;if u32_at(&status,20)&2==0{return Ok(());}}
            let r=self.request(3,5,chunk,&[],Effect::None)?;
            for pair in r[8..24].chunks_exact(2){self.capture_samples.push(i16::from_le_bytes([pair[0],pair[1]]));}
            self.monitor.capture_progress=self.capture_samples.len();
            if chunk==63 {
                self.monitor.samples=std::mem::take(&mut self.capture_samples);
                self.monitor.captured_at_ms=Some(SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis());
                self.capture_chunk=None;
            }else{self.capture_chunk=Some(chunk+1);}
        }else{
            let r=self.request(3,2,0,&[],Effect::None)?;
            self.monitor.generation=u16::from_le_bytes([r[8],r[9]]);
            self.capture_samples.clear();self.monitor.capture_progress=0;self.capture_chunk=Some(0);
            // Capture needs 10.49 ms. The next action is scheduled at least 20 ms later.
        }
        Ok(())
    }
    fn map_key(&mut self,key:u8,value:KeyMapping)->Result<(),String> {
        if !self.monitor.available{return Err("请更新支持逐键映射的固件后再同步音色".into());}
        if key>31||value.slot>3||value.note>127||value.velocity==0||value.velocity>127{return Err("按键配置越界".into());}
        let phase=(440.0*2f64.powf((value.note as f64-69.0)/12.0)*4294967296.0/RATE).round() as u32;
        let descriptor=value.slot as u32|((value.note as u32)<<2)|((value.velocity as u32)<<9);
        self.request(3,1,key,&[phase,descriptor],Effect::Key{key,value})?;Ok(())
    }
    pub(super) fn configure_key(&mut self,key:u8,note:u8,velocity:u8)->Result<(),String> {
        let old=self.saved.keys.get(key as usize).ok_or("按键编号越界")?.clone();
        self.map_key(key,KeyMapping{note,velocity,..old})
    }
    pub(super) fn validate_key(&mut self,key:u8,scope:&str,program:Option<u8>,patch:Option<NativePatch>,operators:Option<Vec<Operator>>)->Result<(),String> {
        // Physical SW2 can release reservations between GUI polls. Ask the board
        // before preflight (including wavetable upload), not just at final apply.
        self.sequencer_step()?;
        if !self.monitor.available{return Err("当前固件未提供逐键音色映射，请先更新固件".into());}
        if key>31||!["key","sound","all"].contains(&scope){return Err("无效的按键或应用范围".into());}
        if program.is_some()==patch.is_some(){return Err("需要选择一个预设或一份合成参数".into());}
        let desired=if let Some(p)=patch{compile_native(p,0,1)?.1}else{compile(program.unwrap(),0,1,operators)?.1};
        let same=self.saved.slots.iter().any(|s|s.program==desired.program &&
            serde_json::to_value(&s.native).ok()==serde_json::to_value(&desired.native).ok() &&
            serde_json::to_value(&s.operators).ok()==serde_json::to_value(&desired.operators).ok());
        if !same {choose_slot_retained(&self.saved.keys,key as usize,scope,self.sequencer.locked_slots)?;}Ok(())
    }
    pub(super) fn assign_key(&mut self,key:u8,scope:String,program:Option<u8>,patch:Option<NativePatch>,operators:Option<Vec<Operator>>)->Result<(),String> {
        self.validate_key(key,&scope,program,patch.clone(),operators.clone())?;
        if !self.monitor.available{return Err("当前固件未提供逐键音色映射，请先更新固件".into());}
        if program.is_some()==patch.is_some(){return Err("需要选择一个预设或一份合成参数".into());}
        // Compile first: malformed patches must not stop notes or alter an existing sound.
        let desired=if let Some(ref patch)=patch{compile_native(patch.clone(),0,1)?.1}else{compile(program.unwrap(),0,1,operators.clone())?.1};
        let identical=self.saved.slots.iter().position(|s|s.program==desired.program &&
            serde_json::to_value(&s.native).ok()==serde_json::to_value(&desired.native).ok() &&
            serde_json::to_value(&s.operators).ok()==serde_json::to_value(&desired.operators).ok());
        let old=self.saved.keys.get(key as usize).ok_or("按键编号越界")?.slot;
        let slot=if let Some(i)=identical{i as u8}else{choose_slot_retained(&self.saved.keys,key as usize,&scope,self.sequencer.locked_slots)?};
        if !["key","sound","all"].contains(&scope.as_str()){return Err("无效的应用范围".into());}
        let targets:Vec<_>=self.saved.keys.iter().enumerate().filter(|(i,k)|scope=="all"||(scope=="sound"&&k.slot==old)||(scope=="key"&&*i==key as usize)).map(|(i,k)|(i as u8,KeyMapping{slot,..k.clone()})).collect();
        if identical.is_none() {
            if let Some(p)=patch{self.load_native(slot,p)?;}else{self.load(slot,program.unwrap(),operators)?;}
        }
        for (index,value) in targets{if self.saved.keys[index as usize]!=value{self.map_key(index,value)?;}}
        Ok(())
    }
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn retained_layers_use_new_slots(){
        let k=default_keys();assert_eq!(choose_slot_retained(&k,0,"all",1).unwrap(),1);
        assert_eq!(choose_slot_retained(&k,0,"all",3).unwrap(),2);
        assert!(choose_slot_retained(&k,0,"all",15).is_err());
        assert_eq!(choose_slot_retained(&k,0,"key",1).unwrap(),1);
    }
    #[test] fn allocation_preserves_other_keys(){
        let mut k=default_keys();assert_eq!(choose_slot(&k,0,"key").unwrap(),1);
        k[0].slot=1;assert_eq!(choose_slot(&k,0,"key").unwrap(),1);
        k[1].slot=2;k[2].slot=3;
        assert!(choose_slot(&k,3,"key").unwrap_err().contains("4 种"));
        assert_eq!(choose_slot(&k,3,"all").unwrap(),0);
        assert_eq!(choose_slot(&k,3,"sound").unwrap(),0);
        assert!(choose_slot(&k,3,"invalid").is_err());
    }
    #[test] fn allocation_errors_distinguish_recordings_from_live_keys(){
        let mut k=default_keys();k[0].slot=1;k[1].slot=2;k[2].slot=3;
        let live=choose_slot_retained(&k,3,"key",0).unwrap_err();
        assert!(live.contains("共享此音色"));assert!(!live.contains("清空音序"));
        let mixed=choose_slot_retained(&k,3,"key",2).unwrap_err();
        assert!(mixed.contains("录音保留槽 2"));assert!(mixed.contains("不会合并琴键"));
        assert!(choose_slot_retained(&k,3,"all",15).unwrap_err().contains("暂停回放不会释放"));
        // SW2 releases recording ownership; broadening scope still has to be
        // explicit when live keys share the patch that is being replaced.
        assert_eq!(choose_slot_retained(&k,3,"all",0).unwrap(),0);
        assert_eq!(choose_slot_retained(&k,3,"sound",2).unwrap(),0);
        k[31].slot=7;assert!(choose_slot_retained(&k,3,"all",2).unwrap_err().contains("损坏"));
    }
}
