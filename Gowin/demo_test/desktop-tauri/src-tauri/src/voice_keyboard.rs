//! Physical keyboard calibration and atomic FPGA configuration.
use super::{Engine,Effect,u32_at};
use serde::{Serialize,Deserialize};

#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct Endpoint {pub rest:u16,pub bottom:u16,pub noise:u16}
#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct Profile {pub keys:Vec<Endpoint>,pub release:f64,pub press:f64,pub sensitivity:u16,pub velocity_enabled:bool,
    #[serde(default="default_ceiling")] pub velocity_ceiling:u8,#[serde(default)] pub curve_version:u8}
fn default_ceiling()->u8{127}
impl Default for Profile {
    fn default()->Self {Self{keys:serde_json::from_str(include_str!("../assets/keyboard-factory.json")).expect("factory keyboard"),release:0.35,press:0.50,sensitivity:500,velocity_enabled:false,velocity_ceiling:127,curve_version:2}}
}
impl Profile {
    fn migrated(mut self)->Self {if self.curve_version<2 {self.sensitivity=500;self.velocity_ceiling=127;self.curve_version=2;} self}
    fn validate(&self)->Result<(),String>{
        if self.keys.len()!=32 || !self.release.is_finite() || !self.press.is_finite() || !(0.02..=0.95).contains(&self.release) || !(0.05..=0.98).contains(&self.press) || self.release+0.03>self.press || !(1..=1000).contains(&self.sensitivity) || !(1..=127).contains(&self.velocity_ceiling) || self.curve_version!=2 {return Err("需32键完整校准；松开阈值必须比按下阈值低至少3%，灵敏度为1～1000，力度上限为1～127".into());}
        for (i,k) in self.keys.iter().enumerate(){
            let span=k.rest.abs_diff(k.bottom) as f64;
            if k.rest>4095 || k.bottom>4095 || span<100.0_f64.max(k.noise as f64*8.) || span*(self.press-self.release)<(k.noise as f64*2.+4.) || span*self.release<10.0_f64.max(k.noise as f64*2.+4.) {return Err(format!("K{:02} 行程不足或阈值间隔小于噪声，请重新校准或拉大阈值间隔",i+1));}
        }Ok(())
    }
    fn threshold(&self,key:usize)->u32 {let k=&self.keys[key];let d=k.bottom as f64-k.rest as f64;let r=(k.rest as f64+d*self.release).round() as u32;let p=(k.rest as f64+d*self.press).round() as u32;((k.bottom<k.rest) as u32)<<24 | r<<12 | p}
    fn curve(&self,index:usize)->u8 {
        if index==127{return 1;}
        let us=if index<32{(index*128+64) as f64}else{let exponent=index/16+10;(1u32<<exponent) as f64+(index%16) as f64*(1u32<<(exponent-4)) as f64+0.5*(1u32<<(exponent-4)) as f64};
        let tau=0.5*256_f64.powf((self.sensitivity as f64-1.)/999.);
        (self.velocity_ceiling as f64*(-us/1000./tau).exp()).round().clamp(1.,self.velocity_ceiling as f64) as u8
    }
    pub(super) fn revision(&self)->u32 {serde_json::to_vec(self).unwrap().iter().fold(2166136261u32,|h,b|(h^*b as u32).wrapping_mul(16777619)).max(1)}
}
#[derive(Clone,Serialize)]
pub struct Calibration {pub stage:String,pub key:usize,pub samples:usize,pub completed:usize}
#[derive(Clone,Serialize)]
pub struct Keyboard {
    pub available:bool,pub profile:Profile,pub applied:bool,pub revision:u32,
    pub raw:Vec<u16>,pub scans:u32,pub last_key:u8,pub velocity:u8,pub travel_ms:f64,pub travel_us:u32,pub scan_interval_us:u32,pub estimated:bool,pub timer_us:u32,pub enabled:bool,
    pub calibration:Option<Calibration>,pub message:String,
    #[serde(skip)] samples:Vec<Vec<u16>>,#[serde(skip)] draft:Option<Profile>,
}
impl Keyboard {pub(super) fn draft_clear(&mut self){self.draft=None;}}
impl Default for Keyboard {fn default()->Self{Self{available:false,profile:Profile::default(),applied:false,revision:0,raw:vec![0;32],scans:0,last_key:0,velocity:100,travel_ms:0.,travel_us:0,scan_interval_us:0,estimated:false,timer_us:1,enabled:false,calibration:None,message:String::new(),samples:vec![Vec::new();32],draft:None}}}
fn stable(values:&[u16])->Result<(u16,u16),String>{
    if values.len()<10{return Err("请保持当前位置至少1.5秒，等待10份新采样".into());}
    let mut recent=values[values.len()-10..].to_vec();recent.sort_unstable();let noise=recent[9]-recent[0];
    if noise>60{return Err("采样波动较大，请保持按键不动再试".into());}Ok(((recent[4] as u32+recent[5] as u32).div_ceil(2) as u16,noise))
}
impl Engine {
    pub(super) fn discover_keyboard(&mut self)->Result<(),String>{
        self.keyboard=Keyboard::default();self.keyboard.profile=self.saved.keyboard.clone().unwrap_or_default().migrated();
        let r=match self.request(3,0x20,0,&[],Effect::None){Ok(r)=>r,Err(e)=>{if self.saved.pending.is_some(){return Err(e);}return Ok(());}};
        if u32_at(&r,8)!=0x4b424432{self.keyboard.message="需要 KBD2 微秒力度固件，请先更新固件".into();return Ok(());}self.keyboard.available=true;
        self.keyboard_status(&r);self.request(3,0x22,0,&[],Effect::None)?;Ok(())
    }
    fn keyboard_status(&mut self,r:&[u8]){
        self.keyboard.revision=u32_at(r,12);let v=u32_at(r,16);self.keyboard.scans=u32_at(r,20);
        self.keyboard.last_key=(v&31) as u8;self.keyboard.velocity=((v>>5)&127) as u8;self.keyboard.enabled=v&(1<<12)!=0;
        self.keyboard.applied=self.keyboard.revision==self.keyboard.profile.revision() || (self.keyboard.revision==0 && self.saved.keyboard.is_none());
    }
    pub(super) fn keyboard_step(&mut self)->Result<(),String>{
        if !self.keyboard.available{return Ok(());}
        let r=self.request(3,0x20,0,&[],Effect::None)?;let old=self.keyboard.scans;self.keyboard_status(&r);
        if self.keyboard.calibration.is_some() && u32_at(&r,16)&(1<<13)==0 {
            self.keyboard.calibration=None;self.keyboard.draft=None;self.keyboard.message="校准已被硬件超时取消，原配置保持不变，请重新开始".into();
        }
        let timing=self.request(3,0x28,0,&[],Effect::None)?;
        self.keyboard.travel_us=u32_at(&timing,8);self.keyboard.travel_ms=self.keyboard.travel_us as f64/1000.;
        self.keyboard.scan_interval_us=u32_at(&timing,12);let observation=u32_at(&timing,16);
        self.keyboard.last_key=(observation&31) as u8;self.keyboard.velocity=((observation>>5)&127) as u8;
        self.keyboard.estimated=observation&(1<<12)!=0;self.keyboard.timer_us=u32_at(&timing,20);
        for group in 0..4 {let r=self.request(3,0x21,group,&[],Effect::None)?;for n in 0..8{self.keyboard.raw[group as usize*8+n]=u16::from_le_bytes([r[8+n*2],r[9+n*2]]);}}
        if self.keyboard.scans!=old {if let Some(c)=self.keyboard.calibration.as_mut(){
            for (k,raw) in self.keyboard.raw.iter().enumerate(){let values=&mut self.keyboard.samples[k];values.push(*raw);if values.len()>20{values.remove(0);}}
            c.samples=self.keyboard.samples[c.key].len().min(10);
        }}Ok(())
    }
    pub(super) fn keyboard_begin(&mut self)->Result<(),String>{
        if !self.keyboard.available{return Err("当前固件未提供键盘设置接口".into());}
        if self.keyboard.calibration.is_some(){return Err("校准已经开始，请继续或取消".into());}
        self.control(self.saved.volume,false,true)?;
        self.request(3,0x22,1,&[],Effect::None)?;
        self.keyboard.draft=Some(self.keyboard.profile.clone());self.keyboard.samples=vec![Vec::new();32];
        self.keyboard.calibration=Some(Calibration{stage:"rest".into(),key:0,samples:0,completed:0});
        self.keyboard.message="请松开全部32键，保持不动后确认松开位置".into();Ok(())
    }
    pub(super) fn keyboard_capture(&mut self)->Result<(),String>{
        let c=self.keyboard.calibration.clone().ok_or("尚未开始校准")?;
        let mut draft=self.keyboard.draft.clone().ok_or("校准草稿不存在")?;
        if c.stage=="rest" {
            for (i,values) in self.keyboard.samples.iter().enumerate(){let (rest,noise)=stable(values).map_err(|e|format!("K{:02}: {e}",i+1))?;draft.keys[i].rest=rest;draft.keys[i].noise=noise;}
            self.keyboard.calibration=Some(Calibration{stage:"bottom".into(),key:0,samples:0,completed:0});
            self.keyboard.message="请只把 K01 按到底，保持不动后确认".into();
        } else if c.stage=="bottom" {
            let (bottom,noise)=stable(&self.keyboard.samples[c.key])?;let k=&mut draft.keys[c.key];
            if bottom.abs_diff(k.rest)<100.max(k.noise.max(noise)*8){return Err(format!("K{:02} 行程不足，请按到底；未覆盖原配置",c.key+1));}
            k.bottom=bottom;k.noise=k.noise.max(noise);
            let done=c.key+1;
            self.keyboard.calibration=Some(Calibration{stage:if done==32{"review"}else{"bottom"}.into(),key:done.min(31),samples:0,completed:done});
            self.keyboard.message=if done==32{"32键采集完成，请松开全部键，检查后保存校准".into()}else{format!("已记录 K{:02}，请松开它，再把 K{:02} 按到底",done,done+1)};
        } else {return Err("全部按键已采集，请保存或取消".into());}
        self.keyboard.draft=Some(draft);self.keyboard.samples=vec![Vec::new();32];Ok(())
    }
    pub(super) fn keyboard_previous(&mut self)->Result<(),String>{
        let c=self.keyboard.calibration.as_mut().ok_or("尚未开始校准")?;
        if c.stage=="rest" {return Err("已经是第一步".into());}
        if c.stage=="review" {c.stage="bottom".into();c.key=31;c.completed=31;}
        else if c.key==0 {c.stage="rest".into();c.completed=0;}
        else {c.key-=1;c.completed=c.key;}
        c.samples=0;self.keyboard.samples=vec![Vec::new();32];self.keyboard.message="已退回上一步，请保持指定位置后重新确认".into();Ok(())
    }
    pub(super) fn keyboard_cancel(&mut self)->Result<(),String>{
        if self.keyboard.available{self.request(3,0x22,0,&[],Effect::None)?;}
        self.keyboard.calibration=None;self.keyboard.draft=None;self.keyboard.message="已取消校准，原配置保持不变；松键后可继续演奏".into();Ok(())
    }
    pub(super) fn keyboard_apply(&mut self,release:f64,press:f64,sensitivity:u16,velocity_enabled:bool,velocity_ceiling:u8)->Result<(),String>{
        if !self.keyboard.available{return Err("请先更新支持键盘设置的固件".into());}
        let calibrating=self.keyboard.calibration.is_some();
        if self.keyboard.calibration.as_ref().is_some_and(|c|c.stage!="review"){return Err("请先完成32键校准或取消".into());}
        let mut profile=if calibrating{self.keyboard.draft.clone().ok_or("没有完整校准草稿")?}else{self.keyboard.profile.clone()};
        profile.release=release;profile.press=press;profile.sensitivity=sensitivity;profile.velocity_enabled=velocity_enabled;profile.velocity_ceiling=velocity_ceiling;profile.curve_version=2;profile.validate()?;
        // Keep the calibration overlay through commit; normal settings use a hidden short mute.
        if !calibrating {self.control(self.saved.volume,false,true)?;self.request(3,0x22,2,&[],Effect::None)?;}
        else {self.keyboard_step()?;if self.keyboard.calibration.is_none(){return Err("校准超时，请重新开始".into());}
            for (k,raw) in self.keyboard.raw.iter().enumerate(){let e=&profile.keys[k];if raw.abs_diff(e.rest) as f64>e.rest.abs_diff(e.bottom) as f64*release{return Err(format!("请先松开 K{:02} 再保存",k+1));}}
        }
        for key in 0..32 {self.request(3,0x23,key,&[profile.threshold(key as usize)],Effect::None)?;}
        for chunk in 0..16 {let mut bytes=[0u8;8];for (n,b) in bytes.iter_mut().enumerate(){*b=profile.curve(chunk as usize*8+n);}self.request(3,0x27,chunk,&[u32::from_le_bytes(bytes[..4].try_into().unwrap()),u32::from_le_bytes(bytes[4..].try_into().unwrap())],Effect::None)?;}
        let revision=profile.revision();self.request(3,0x24,0,&[velocity_enabled as u32,revision],Effect::Keyboard{profile:profile.clone()})?;
        self.keyboard.profile=profile;self.keyboard.applied=true;self.keyboard.revision=revision;self.keyboard.enabled=velocity_enabled;
        self.keyboard.calibration=None;self.keyboard.draft=None;self.keyboard.message="键盘设置已由硬件确认并保存到本机。松开全部键后继续演奏".into();Ok(())
    }
}
#[cfg(test)] mod tests {
    use super::*;
    #[test]fn calibration_thresholds_and_velocity(){let p=Profile::default();p.validate().unwrap();let mut q=p.clone();q.keys[0]=Endpoint{rest:3000,bottom:1000,noise:0};assert_eq!(q.threshold(0),(1<<24)|(2300<<12)|2000);q.keys[0]=Endpoint{rest:1000,bottom:3000,noise:0};assert_eq!(q.threshold(0),(1700<<12)|2000);for n in 1..128{assert!(p.curve(n)<=p.curve(n-1));}q.sensitivity=1000;assert!(q.curve(20)>p.curve(20));q.press=q.release;assert!(q.validate().is_err());}
    #[test]fn wide_curve_and_ceiling(){
        let mut p=Profile::default();assert!(p.curve(39)<70);
        for response in [1,250,500,750,1000]{p.sensitivity=response;for ceiling in [1,64,100,127]{p.velocity_ceiling=ceiling;p.validate().unwrap();for i in 0..128{assert!((1..=ceiling).contains(&p.curve(i)));if i>0{assert!(p.curve(i)<=p.curve(i-1));}}}}
        p.sensitivity=1001;assert!(p.validate().is_err());
    }
    #[test]fn legacy_migration_preserves_calibration(){
        let mut raw=serde_json::to_value(Profile::default()).unwrap();raw.as_object_mut().unwrap().remove("curve_version");raw.as_object_mut().unwrap().remove("velocity_ceiling");raw["sensitivity"]=100.into();raw["press"]=0.95.into();raw["keys"][0]["rest"]=850.into();raw["keys"][0]["bottom"]=120.into();
        let old:Profile=serde_json::from_value(raw).unwrap();let p=old.clone().migrated();assert_eq!(old.sensitivity,100);assert_eq!(p.sensitivity,500);assert_eq!(p.press,0.95);assert_eq!(p.keys[0].rest,850);assert_eq!(p.keys[0].bottom,120);assert_eq!(p.curve_version,2);assert_eq!(p.velocity_ceiling,127);
    }
    #[test]fn reject_unstable_and_partial_capture(){assert!(stable(&[10;9]).is_err());assert_eq!(stable(&[100;10]).unwrap(),(100,0));assert!(stable(&[0,100,100,100,100,100,100,100,100,100]).is_err());let mut p=Profile::default();p.keys[3].bottom=p.keys[3].rest;assert!(p.validate().is_err());}
    #[test]fn cancel_keeps_saved_calibration(){let dir=tempfile::tempdir().unwrap();let mut e=Engine::new(dir.path().into());let p=Profile::default();e.saved.keyboard=Some(p.clone());e.keyboard.draft=Some(p.clone());e.keyboard.calibration=Some(Calibration{stage:"bottom".into(),key:2,samples:10,completed:2});e.keyboard_cancel().unwrap();assert!(e.keyboard.draft.is_none());assert_eq!(e.saved.keyboard.unwrap().revision(),p.revision());}
}
