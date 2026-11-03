//! FPGA-local touch performance. Serial only configures and observes it.
use super::{Engine,Effect,u32_at};
use serde::{Serialize,Deserialize};

#[derive(Clone,Debug,Serialize,Deserialize,PartialEq)]
pub struct Profile {
    pub mode:u8,pub gain_percent:f64,pub pitch_semitones:f64,pub cutoff_octaves:f64,
    pub swap_axes:bool,pub flip_x:bool,pub flip_y:bool,
}
impl Default for Profile {fn default()->Self{Self::decode(0,32|(21<<8)|(64<<16))}}
impl Profile {
    fn words(&self)->Result<[u32;2],String>{
        if self.mode>3 || !self.gain_percent.is_finite() || !(0.0..=100.0).contains(&self.gain_percent) || !self.pitch_semitones.is_finite() || !(0.0..=12.0).contains(&self.pitch_semitones) || !self.cutoff_octaves.is_finite() || !(0.0..=6.0).contains(&self.cutoff_octaves){return Err("触摸模式需为1～4，音量范围0～100%，音高0～12半音，Cutoff 0～6倍频程".into());}
        Ok([self.mode as u32|((self.swap_axes as u32)<<2)|((self.flip_x as u32)<<3)|((self.flip_y as u32)<<4),
            (self.gain_percent*128./100.).round() as u32|(((self.pitch_semitones*128./12.).round() as u32)<<8)|(((self.cutoff_octaves*32.).round() as u32)<<16)])
    }
    fn decode(flags:u32,ranges:u32)->Self{Self{mode:(flags&3) as u8,swap_axes:flags&4!=0,flip_x:flags&8!=0,flip_y:flags&16!=0,gain_percent:(ranges&255) as f64*100./128.,pitch_semitones:((ranges>>8)&255) as f64*12./128.,cutoff_octaves:((ranges>>16)&255) as f64/32.}}
}
#[derive(Clone,Default,Serialize)]
pub struct Touch {
    pub available:bool,pub profile:Profile,pub applied:bool,pub mode:u8,
    pub touching:bool,pub pads:u8,pub pad:u8,pub x:u16,pub y:u16,pub errors:[u8;2],
    pub strums:u16,pub coalesced:u16,pub gain:f64,pub pitch_semitones:f64,pub cutoff_octaves:f64,
}
impl Engine {
    pub(super) fn discover_touch(&mut self)->Result<(),String>{
        self.touch=Touch::default();self.touch.profile=self.saved.touch.clone().unwrap_or_default();
        if self.abi.unwrap_or(0)<0x00010007{return Ok(());}
        let cap=self.request(3,0x30,0,&[],Effect::None)?;
        self.touch.available=u32_at(&cap,8)==0x544f5531;
        self.touch_step()
    }
    pub(super) fn touch_step(&mut self)->Result<(),String>{
        if !self.touch.available{return Ok(());}
        let state=self.request(3,0x32,0,&[],Effect::None)?;
        let flags=u32_at(&state,8);let position=u32_at(&state,12);let counts=u32_at(&state,16);
        self.touch.mode=(flags&3) as u8;self.touch.pads=((flags>>2)&3) as u8;self.touch.touching=flags&16!=0;self.touch.pad=((flags>>5)&1) as u8;
        self.touch.errors=[(flags>>8) as u8,(flags>>16) as u8];self.touch.x=(position&1023) as u16;self.touch.y=((position>>10)&1023) as u16;
        self.touch.strums=counts as u16;self.touch.coalesced=(counts>>16) as u16;
        self.touch.pitch_semitones=12.*(1.+(u32_at(&state,20) as i32) as f64/67108864.).max(0.0001).log2();
        let config=self.request(3,0x33,0,&[],Effect::None)?;
        let actual=Profile::decode(u32_at(&config,8),u32_at(&config,12));
        self.touch.mode=actual.mode;
        self.touch.gain=u32_at(&config,16) as f64/65536.;
        self.touch.cutoff_octaves=(u32_at(&config,20) as i32) as f64*900_f64.log2()/261888.;
        let desired=self.touch.profile.words()?;let received=actual.words()?;
        // A joystick mode change is authoritative only when the saved sensitivity
        // and orientation already match this board. A reset must not erase them.
        if self.saved.touch.is_none() || (desired[0]&!3==received[0]&!3 && desired[1]==received[1]) {
            if self.saved.touch.as_ref()!=Some(&actual){self.saved.touch=Some(actual.clone());self.save()?;}
            self.touch.profile=actual;
        }
        self.touch.applied=self.touch.profile.words()?==received;Ok(())
    }
    pub(super) fn touch_apply(&mut self,profile:Profile)->Result<(),String>{
        if !self.touch.available{return Err("当前固件未提供触摸演奏模块".into());}
        let words=profile.words()?;let canonical=Profile::decode(words[0],words[1]);
        self.request(3,0x31,0,&words,Effect::Touch{profile:canonical})?;self.touch_step()
    }
}
#[cfg(test)]mod tests{
    use super::*;
    #[test]fn touch_config_units_and_roundtrip(){
        let mut p=Profile::default();assert_eq!(p.words().unwrap(),[0,0x401520]);
        p.mode=3;p.gain_percent=100.;p.pitch_semitones=12.;p.cutoff_octaves=6.;p.swap_axes=true;p.flip_x=true;p.flip_y=true;
        let w=p.words().unwrap();assert_eq!(w,[31,0xc08080]);assert_eq!(Profile::decode(w[0],w[1]),p);
        p.pitch_semitones=2.;let w=p.words().unwrap();assert_eq!(Profile::decode(w[0],w[1]).words().unwrap(),w);
    }
    #[test]fn touch_rejects_invalid_config(){let mut p=Profile::default();p.gain_percent=f64::NAN;assert!(p.words().is_err());p.gain_percent=101.;assert!(p.words().is_err());p.gain_percent=0.;p.mode=4;assert!(p.words().is_err());p.mode=0;p.cutoff_octaves=-1.;assert!(p.words().is_err());}
    #[test]fn old_firmware_never_queries_touch(){let d=tempfile::tempdir().unwrap();let mut e=Engine::new(d.path().into());e.abi=Some(0x10006);assert!(e.discover_touch().is_ok());assert!(!e.touch.available);}
}
