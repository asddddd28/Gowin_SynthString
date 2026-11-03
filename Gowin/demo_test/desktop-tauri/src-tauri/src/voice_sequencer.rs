//! FPGA musical transport. Recorded patch slots are immutable until the loop is cleared.
use super::{Engine,Effect,u32_at};
use serde::{Deserialize,Serialize};

/// RAM event image only. Timbre and wavetable data belong to the full SD archive.
#[derive(Clone,Serialize,Deserialize,Debug,PartialEq)]
pub struct EventImage {
    pub ppq:u32,pub bpm:u16,pub loop_ticks:u32,pub events:Vec<[u32;3]>,
}
impl EventImage {
    pub fn validate(&self)->Result<u8,String>{
        if self.ppq!=960||!(20..=300).contains(&self.bpm)||self.loop_ticks>=1<<20||self.loop_ticks%3840!=0||self.events.len()>1024||self.loop_ticks==0&&!self.events.is_empty(){
            return Err("音序事件快照的时间基准、BPM、长度或容量不兼容".into());
        }
        let mut slots=0;
        for (index,event) in self.events.iter().enumerate(){
            let bits=(event[0] as u128)|((event[1] as u128)<<32)|((event[2] as u128)<<64);
            let anchor=((bits>>20)&1023) as usize;
            if bits>>85!=0||(bits&0xfffff)>=self.loop_ticks as u128{return Err("音序事件保留位或时间戳无效".into());}
            if (bits>>78)&1!=0 {
                if anchor!=index{return Err("起音事件配对索引无效".into());}
                slots|=1<<((bits>>76)&3);
            } else if anchor>=index||self.events[anchor][2]&(1<<14)==0{return Err("松键事件没有对应起音".into());}
        }
        Ok(slots)
    }
}

#[derive(Clone,Default,Serialize)]
pub struct Sequencer {
    pub available:bool,pub recording:bool,pub playing:bool,pub finalizing:bool,
    pub full:bool,pub fault:bool,pub waiting_first_note:bool,pub locked_slots:u8,pub buttons:u8,
    pub bpm:u16,pub events:u16,pub capacity:u32,pub ppq:u32,
    pub loop_ticks:u32,pub position:u32,
    pub archive_available:bool,pub archive_busy:bool,
    pub event_image:Option<EventImage>,
    pub button_layout:u32,pub library_message:String,
    #[serde(skip)] library_counts:Option<[u16;3]>,
}

impl Engine {
    pub(super) fn discover_sequencer(&mut self)->Result<(),String>{
        self.sequencer=Sequencer::default();
        let r=match self.request(3,0x40,0,&[],Effect::None){
            Ok(r)=>r,Err(e) if e=="通信控制器拒绝请求，状态5"=>return Ok(()),Err(e)=>return Err(e),
        };
        let layout=u32_at(&r,12);
        if u32_at(&r,8)!=0x53455131||!(1..=3).contains(&layout){return Err("未知音序器接口".into());}
        self.sequencer.button_layout=layout;
        self.sequencer.available=true;self.sequencer.capacity=u32_at(&r,16);self.sequencer.ppq=u32_at(&r,20);
        match self.request(3,0x43,0,&[],Effect::None){
            Ok(r)=>{if u32_at(&r,8)!=0x41524331||u32_at(&r,20)!=90{return Err("未知音序事件快照接口".into());}self.sequencer.archive_available=true;},
            Err(e) if e=="通信控制器拒绝请求，状态5"=>{},Err(e)=>return Err(e),
        }
        self.sequencer_step()
    }
    pub(super) fn sequencer_step(&mut self)->Result<(),String>{
        if !self.sequencer.available{return Ok(());}
        let r=self.request(3,0x41,0,&[],Effect::None)?;
        let flags=u32_at(&r,8);let packed=u32_at(&r,12);
        let s=&mut self.sequencer;
        s.recording=flags&1!=0;s.playing=flags&2!=0;s.finalizing=flags&4!=0;s.full=flags&8!=0;s.fault=flags&16!=0;
        s.archive_busy=flags&32!=0;
        s.waiting_first_note=flags&64!=0;
        s.locked_slots=((flags>>8)&15) as u8;s.buttons=((flags>>16)&63) as u8;
        s.bpm=packed as u16;s.events=(packed>>16) as u16;s.loop_ticks=u32_at(&r,16)&0xfffff;s.position=u32_at(&r,20)&0xfffff;
        if self.sequencer.button_layout>=2 {
            let r=self.request(3,0x49,0,&[],Effect::None)?;
            let counts=[u32_at(&r,8) as u16,u32_at(&r,12) as u16,u32_at(&r,16) as u16];
            if let Some(previous)=self.sequencer.library_counts {
                if previous!=counts {
                    self.sequencer.library_message=if self.storage.service {
                        "已收到音序库按键，保存或加载结果请查看 SD 卡与存储状态".into()
                    }else{
                        "已收到音序库按键；当前固件尚未接通独立 SD 存取服务".into()
                    };
                }
            }
            self.sequencer.library_counts=Some(counts);
        }
        Ok(())
    }
    pub(super) fn sequencer_control(&mut self,action:u8,bpm:Option<u16>)->Result<(),String>{
        if !self.sequencer.available{return Err("当前固件没有音序器".into());}
        if !(1..=4).contains(&action)||(action==4&&!matches!(bpm,Some(20..=300)))||(action!=4&&bpm.is_some()){
            return Err("无效的音序器控制；BPM 范围 20～300".into());
        }
        self.request(3,0x42,0,&[action as u32,bpm.unwrap_or(0) as u32],Effect::None)?;
        self.sequencer_step()
    }
    pub(super) fn check_slot_unlocked(&mut self,slot:u8)->Result<(),String>{
        self.sequencer_step()?;
        if self.sequencer.archive_busy{return Err("音序快照正在传输，请稍后再调整音色".into());}
        if self.sequencer.recording||self.sequencer.finalizing{return Err("请先结束本层录制，再换音色追加下一层".into());}
        if self.sequencer.locked_slots&(1<<slot)!=0{return Err("该音色由录音层保留，请选择空闲音色槽或清空音序；原有录音不会被覆盖".into());}
        Ok(())
    }

    pub(super) fn sequence_export(&mut self)->Result<(),String>{
        self.sequencer_step()?;
        let s=&self.sequencer;
        if !s.archive_available{return Err("当前固件没有音序事件快照接口".into());}
        if s.recording||s.playing||s.finalizing||s.archive_busy{return Err("请先停止录制并暂停播放，再导出事件快照".into());}
        self.request(3,0x45,0,&[1],Effect::None)?;
        let result:Result<EventImage,String>=(||{
            self.sequencer_step()?;
            let mut image=EventImage{ppq:self.sequencer.ppq,bpm:self.sequencer.bpm,loop_ticks:self.sequencer.loop_ticks,events:Vec::new()};
            let count=self.sequencer.events;
            if count>1024{return Err("设备事件数超出容量".into());}
            let mut generation=None;
            for index in 0..count {
                let r=self.request(3,0x44,0,&[index as u32],Effect::None)?;
                let current=u32_at(&r,20);
                if generation.is_some_and(|g|g!=current){return Err("导出过程中音序发生变化".into());}
                generation=Some(current);
                image.events.push([u32_at(&r,8),u32_at(&r,12),u32_at(&r,16)]);
            }
            image.validate()?;Ok(image)
        })();
        // Never supersede an unconfirmed UART packet. The hardware lease expires.
        let release=if self.saved.pending.is_none(){self.request(3,0x45,0,&[0],Effect::None).map(|_|())}else{Err("请恢复未确认请求；音序传输锁会超时解除".into())};
        let image=result?;release?;self.sequencer.event_image=Some(image);self.sequencer_step()
    }

    pub(super) fn sequence_import(&mut self,image:EventImage)->Result<(),String>{
        let slots=image.validate()?;
        self.sequencer_step()?;
        let s=&self.sequencer;
        if !s.archive_available{return Err("当前固件没有音序事件快照接口".into());}
        if s.recording||s.playing||s.finalizing||s.archive_busy||s.events!=0||s.loop_ticks!=0{return Err("导入事件需要空的音序工作区，请先另存并清空现有录音".into());}
        for slot in 0..4 {
            if slots&(1<<slot)!=0&&self.saved.slots[slot].revision==0{return Err("先装载事件引用的音色，再导入事件".into());}
        }
        self.request(3,0x45,0,&[2],Effect::None)?;
        let result:Result<(),String>=(||{
            for (index,event) in image.events.iter().enumerate(){
                self.request(3,0x46,0,&event[..2],Effect::None)?;
                self.request(3,0x47,0,&[event[2],index as u32],Effect::None)?;
            }
            let packed=image.events.len() as u32|((image.bpm as u32)<<16);
            self.request(3,0x48,0,&[packed,image.loop_ticks/3840],Effect::None)?;
            Ok(())
        })();
        if result.is_err()&&self.saved.pending.is_none(){let _=self.request(3,0x45,0,&[0],Effect::None);}
        result?;self.sequencer.event_image=Some(image);self.sequencer_step()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn event_images_preserve_unsorted_overdub_and_reject_broken_anchors(){
        let mut image=EventImage{ppq:960,bpm:120,loop_ticks:3840,events:vec![[100,0,1<<14],[300,0,0],[10|(2<<20),0,(1<<14)|(2<<12)],[90|(2<<20),0,0]]};
        assert_eq!(image.validate().unwrap(),5);
        image.events[3][0]=90|(1<<20);assert!(image.validate().is_err());
        image.events[3][0]=90|(2<<20);image.events[0][2]|=1<<21;assert!(image.validate().is_err());
    }
    #[test]
    fn event_image_length_and_range_are_bounded(){
        let mut image=EventImage{ppq:960,bpm:20,loop_ticks:0,events:vec![]};assert!(image.validate().is_ok());
        image.loop_ticks=3841;assert!(image.validate().is_err());image.loop_ticks=3840;
        image.events=vec![[3840,0,1<<14]];assert!(image.validate().is_err());
        image.events=vec![[0,0,1<<14]];assert!(image.validate().is_ok());image.bpm=301;assert!(image.validate().is_err());
    }
}
