//! Global post-mix lowpass; atomic AXI command and durable acknowledgement.
use super::{Engine,Effect,u32_at,RATE};
use serde::{Serialize,Deserialize};

#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct Profile {
    pub enabled:bool,pub cutoff_hz:f64,pub lfo_enabled:bool,pub lfo_rate_hz:f64,pub lfo_depth_oct:f64,pub lfo_shape:u8,
}
impl Default for Profile {fn default()->Self{Self{enabled:false,cutoff_hz:2000.,lfo_enabled:false,lfo_rate_hz:1.,lfo_depth_oct:2.,lfo_shape:0}}}
impl Profile {
    fn words(&self)->Result<Vec<u32>,String>{
        if !self.cutoff_hz.is_finite() || !(20.0..=18000.0).contains(&self.cutoff_hz) || !self.lfo_rate_hz.is_finite() || !(0.05..=20.0).contains(&self.lfo_rate_hz) || !self.lfo_depth_oct.is_finite() || !(0.0..=6.0).contains(&self.lfo_depth_oct) || self.lfo_shape>1 {return Err("Cutoff需20～18000Hz，LFO速率0.05～20Hz，深度0～6倍频程，波形为正弦或三角".into());}
        let span=900_f64.log2();
        Ok(vec![self.enabled as u32|((self.lfo_enabled as u32)<<1)|((self.lfo_shape as u32)<<2),((self.cutoff_hz/20.).log2()/span*261888.).round() as u32,(self.lfo_rate_hz*4294967296./RATE).round() as u32,(self.lfo_depth_oct/span*261888.).round() as u32,self.revision()])
    }
    pub(super) fn revision(&self)->u32{serde_json::to_vec(self).unwrap().iter().fold(2166136261u32,|h,b|(h^*b as u32).wrapping_mul(16777619)).max(1)}
}
#[derive(Clone,Default,Serialize)]
pub struct Filter {pub available:bool,pub profile:Profile,pub applied:bool,pub revision:u32,pub actual_cutoff_hz:f64,pub enabled:bool,pub lfo_active:bool}
impl Engine {
    pub(super) fn discover_filter(&mut self)->Result<(),String>{
        self.filter=Filter::default();self.filter.profile=self.saved.filter.clone().unwrap_or_default();
        if self.abi.unwrap_or(0)<0x00010006{return Ok(());}
        self.filter.available=self.read(0x64)?==0x4c504631;
        self.filter_step()
    }
    fn filter_status(&mut self,response:&[u8]){
        let flags=u32_at(response,8);self.filter.revision=u32_at(response,12);
        self.filter.enabled=flags&1!=0;self.filter.lfo_active=flags&2!=0;
        self.filter.actual_cutoff_hz=20.*900_f64.powf(u32_at(response,20) as f64/261888.);
        self.filter.applied=self.filter.revision==self.filter.profile.revision();
    }
    pub(super) fn filter_step(&mut self)->Result<(),String>{
        if self.filter.available{let response=self.request(0,0xd1,0,&[],Effect::None)?;self.filter_status(&response);}Ok(())
    }
    pub(super) fn filter_apply(&mut self,profile:Profile)->Result<(),String>{
        if !self.filter.available{return Err("当前固件没有全局低通模块".into());}
        let words=profile.words()?;
        let response=self.request(0,0xd0,0,&words,Effect::Filter{profile})?;
        self.filter_status(&response);Ok(())
    }
}
#[cfg(test)]mod tests{
    use super::*;
    #[test]fn filter_packet_units_and_ranges(){
        let mut p=Profile::default();let words=p.words().unwrap();assert_eq!(words[1],177296);assert_eq!(words[2],87961);assert!(words[3]>53000);
        p.enabled=true;p.lfo_enabled=true;p.lfo_shape=1;p.cutoff_hz=18000.;p.lfo_rate_hz=20.;p.lfo_depth_oct=6.;let w=p.words().unwrap();assert_eq!(w[..4],[7,261888,1759219,160114]);
        p.cutoff_hz=20.;p.lfo_rate_hz=0.05;assert_eq!(p.words().unwrap()[1..3],[0,4398]);
        p.cutoff_hz=f64::NAN;assert!(p.words().is_err());p.cutoff_hz=2000.;p.lfo_shape=2;assert!(p.words().is_err());
    }
    #[test]fn filter_profile_revision_changes(){let a=Profile::default();let mut b=a.clone();b.lfo_depth_oct+=0.1;assert_ne!(a.revision(),b.revision());assert_eq!(a.revision(),a.clone().revision());}
}
