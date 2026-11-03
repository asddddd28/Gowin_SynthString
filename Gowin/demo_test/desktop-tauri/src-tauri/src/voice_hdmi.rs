//! SynthUI display companion. Uses the existing durable UART owner exclusively.
use super::*;

#[derive(Clone,Serialize)]
pub struct Hdmi {
    pub available:Option<bool>, pub page:u8, pub page_count:u8, pub slot:u8, pub operator:u8,
    pub dirty:bool, pub message:String,
    pub rgb_available:Option<bool>, pub rgb_mode:u8, pub rgb_direction:bool,
    #[serde(rename="encoder_counts")] counts:Option<[i16;5]>,
    pub draft_slots:Vec<u8>,
    #[serde(skip)] remainder:[i16;5],
    #[serde(skip)] confirm:u16,
    #[serde(skip)] focus:Option<u8>,
    #[serde(skip)] cached:Vec<u8>,
    #[serde(skip)] phase:u8,
    #[serde(skip)] drafts:[Option<Slot>;4],
}
impl Default for Hdmi {
    fn default()->Self {Self{available:None,page:0,page_count:6,slot:0,operator:0,dirty:false,message:String::new(),rgb_available:None,rgb_mode:1,rgb_direction:false,counts:None,draft_slots:Vec::new(),remainder:[0;5],confirm:0,focus:None,cached:vec![0;1024],phase:0,drafts:std::array::from_fn(|_|None)}}
}
impl Hdmi {
    fn refresh_flags(&mut self){
        self.dirty=self.drafts[self.slot as usize].is_some();
        self.draft_slots=self.drafts.iter().enumerate().filter_map(|(i,d)|d.as_ref().map(|_|i as u8)).collect();
    }
    fn select_slot(&mut self,steps:i16){
        self.slot=(i16::from(self.slot)+steps).rem_euclid(4) as u8;
        self.refresh_flags();
    }
    fn refresh_revisions(&mut self,slots:&[Slot;4]){
        for(i,slot)in slots.iter().enumerate(){
            if self.drafts[i].as_ref().is_some_and(|d|d.revision!=slot.revision){
                self.drafts[i]=None;
                self.message=format!("App 已更改音色槽 {}，该槽的旋钮草稿已刷新",i+1);
            }
        }
        self.refresh_flags();
    }
    fn edit_current(&mut self,base:&Slot,level:i16,ratio:i16)->bool{
        let mut value=self.drafts[self.slot as usize].as_ref().unwrap_or(base).clone();
        let changed=edit(&mut value,self.operator as usize,level,ratio);
        if changed{self.drafts[self.slot as usize]=Some(value);}
        self.refresh_flags();changed
    }
    fn steps(&mut self,counts:[i16;5])->[i16;5]{
        let mut steps=[0;5];
        if let Some(previous)=self.counts{
            for i in 0..5{
                let delta=counts[i].wrapping_sub(previous[i]);
                if delta.unsigned_abs()<=128{
                    self.remainder[i]+=delta;steps[i]=self.remainder[i]/4;self.remainder[i]%=4;
                }else{self.remainder[i]=0;}
            }
        }
        self.counts=Some(counts);steps
    }
    fn next_chunk(&self,image:&[u8])->Option<usize>{
        // Visible knob values and connection/draft status take precedence over
        // background descriptions, so selection feedback does not queue behind a page.
        (104..114).chain(8..16).chain(16..48).chain(0..8).chain(48..104).chain(114..128)
            .find(|i|image[i*8..i*8+8]!=self.cached[i*8..i*8+8])
    }
}
fn text(out:&mut [u8],at:usize,value:&str,width:usize){
    let bytes:Vec<_>=value.chars().map(|c|if c.is_ascii_graphic()||c==' ' {c.to_ascii_uppercase() as u8}else{b' '}).collect();
    for i in 0..width {out[at+i]=*bytes.get(i).unwrap_or(&b' ');}
}
fn patch_name(slot:&Slot)->String {
    if let Some(p)=&slot.snapshot{return p.name.clone();}
    if let Some(p)=&slot.native {
        if p.name.is_ascii(){return p.name.clone();}
        return p.operators.iter().find(|op|op.enabled&&op.carrier).map(|op|format!("{} {}",op.wave,op.mode)).unwrap_or("NATIVE".into());
    }
    library().presets.into_iter().find(|p|Some(p.program)==slot.program).map(|p|p.name).unwrap_or("EMPTY".into())
}
fn edit(slot:&mut Slot,index:usize,level:i16,ratio:i16)->bool {
    if let Some(p)=&mut slot.native {
        if let Some(op)=p.operators.get_mut(index){
            let before=(op.gain,op.ratio);
            op.gain=(op.gain+f64::from(level)*0.01).clamp(0.,1.);
            if let Some(r)=op.ratio {op.ratio=Some((r+f64::from(ratio)*0.25).clamp(0.,16.));}
            return before!=(op.gain,op.ratio);
        }
    }else if let Some(op)=slot.operators.get_mut(index){
        let before=(op.output,op.ratio);
        op.output=(i16::from(op.output)+level).clamp(0,99) as u8;
        if let Some(r)=op.ratio {op.ratio=Some((r+f64::from(ratio)*0.25).clamp(0.,64.));}
        return before!=(op.output,op.ratio);
    }
    false
}
impl Engine {
    pub(super) fn hdmi_rgb(&mut self,mode:u8,direction:bool)->Result<(),String>{
        if self.hdmi.rgb_available!=Some(true){return Err("当前固件未提供键盘灯效控制".into());}
        if !matches!(mode,0..=4|6){return Err("不支持的键盘灯效模式".into());}
        self.request(3,0x19,mode,&[u32::from(direction)],Effect::None)?;
        self.hdmi.rgb_mode=mode;self.hdmi.rgb_direction=direction;
        Ok(())
    }
    fn hdmi_image(&self)->Vec<u8>{
        let mut out=vec![b' ';1024];
        for(i,s)in self.saved.slots.iter().enumerate(){text(&mut out,i*16,&patch_name(s),16);}
        text(&mut out,64,if self.hdmi.dirty{"DRAFT / PRESS TO APPLY"}else{"APP EDIT LINK ONLINE"},32);
        text(&mut out,96,"APP EDIT OFFLINE",32);
        let slot=self.hdmi.drafts[self.hdmi.slot as usize].as_ref().unwrap_or(&self.saved.slots[self.hdmi.slot as usize]);
        let index=self.hdmi.operator as usize;
        let mut lines=vec![format!("SLOT {} / OP {} / REV {}",self.hdmi.slot+1,index+1,slot.revision)];
        if let Some(op)=slot.native.as_ref().and_then(|p|p.operators.get(index)){
            lines.extend([format!("{} / {} / {}",op.wave,op.mode,if op.enabled{"ENABLED"}else{"DISABLED"}),
                format!("GAIN {:.2} / DEPTH {:.3}",op.gain,op.depth),
                format!("RATIO {:?} / HZ {:?}",op.ratio,op.fixed_hz),
                format!("LEVELS {:.2} {:.2} {:.2} {:.2}",op.levels[0],op.levels[1],op.levels[2],op.levels[3]),
                format!("TIME MS {:.0} {:.0} {:.0} {:.0}",op.segment_ms[0],op.segment_ms[1],op.segment_ms[2],op.segment_ms[3]),
                format!("SOURCE {:?} / CARRIER {}",op.sources,op.carrier),format!("FEEDBACK {:.3} / MORPH {:.2}",op.feedback,op.morph)]);
            text(&mut out,864,&format!("{:.0}%",op.gain*100.),16);text(&mut out,880,&format!("{}",op.ratio.map(|r|format!("{r:.2}X")).unwrap_or("FIXED HZ".into())),16);
        } else if let Some(op)=slot.operators.get(index){
            lines.extend([format!("DX FM / OUTPUT {}",op.output),format!("RATIO {:?} / HZ {:?}",op.ratio,op.fixed_hz),
                format!("RATES {} {} {} {}",op.rates[0],op.rates[1],op.rates[2],op.rates[3]),
                format!("LEVELS {} {} {} {}",op.levels[0],op.levels[1],op.levels[2],op.levels[3]),
                "E3 / E4 EDIT DRAFT".into(),"PRESS JOYSTICK TO APPLY".into(),"APPLIES TO ALL KEYS ON THIS SLOT".into()]);
            text(&mut out,864,&format!("{} / 99",op.output),16);text(&mut out,880,&op.ratio.map(|r|format!("{r:.2}X")).unwrap_or("FIXED HZ".into()),16);
        }
        for(i,line)in lines.iter().take(8).enumerate(){text(&mut out,128+i*32,line,32);}
        // No saved LFO routing in the current merged UI: do not invent values.
        for(i,line)in ["HARDWARE LFO ENGINE AVAILABLE","CURRENT PATCH API: NO LFO STATE","NO READBACK = NO CLAIMED VALUES","CONFIGURATION ADAPTER PENDING"].iter().enumerate(){text(&mut out,384+i*32,line,32);}
        for(i,k)in self.saved.keys.iter().take(32).enumerate(){text(&mut out,640+i*6,&format!("K{:02}S{}",i+1,k.slot+1),6);}
        text(&mut out,832,&format!("SLOT {}",self.hdmi.slot+1),16);text(&mut out,848,&format!("OP {}",index+1),16);text(&mut out,896,&format!("{:.0}%",self.saved.volume*100.),16);
        if self.hdmi.page>=6 {
            let sequence=self.hdmi.page==6;
            for line in 0..8 {text(&mut out,128+line*32,"",32);}
            text(&mut out,128,self.storage.hdmi_title(),32);
            text(&mut out,160,&if self.storage.initialized {format!("CAPACITY {:.1} GB",f64::from(self.storage.sectors)*512./1e9)} else {format!("I/O {:02X} / CATALOG {:02X}",self.storage.sector_error,self.storage.catalog_error)},32);
            text(&mut out,512,if sequence{"SEQUENCES / NUMBERED FILES"}else{"SD PRESETS / LOAD TO SLOT"},32);
            text(&mut out,544,if sequence{"SW3 SAVE / SW4 PLAY-PAUSE"}else{"PRESETS FOLDER ON SD"},32);
            text(&mut out,576,&format!("DESTINATION: SLOT {}",self.hdmi.slot+1),32);
            text(&mut out,608,"RAM LOOP IS NOT SAVED TO SD",32);
            text(&mut out,848,"BROWSE",16);text(&mut out,864,"",16);text(&mut out,880,"",16);
        }
        out
    }
    pub(super) fn hdmi_page(&mut self,page:u8)->Result<(),String>{
        if page>=self.hdmi.page_count{return Err("当前显示固件不支持该页面，请先更新固件".into());}
        if self.hdmi.available!=Some(true){return Err("当前固件没有 HDMI 显示接口".into());}
        self.request(3,0x11,page,&[],Effect::None)?;self.hdmi.page=page;Ok(())
    }
    pub(super) fn hdmi_commit(&mut self)->Result<(),String>{
        if !self.hdmi.dirty{return Ok(());}
        // Refuse to interrupt held physical or host notes. Keep the draft.
        if self.telemetry.pressed!=0||!self.saved.notes.is_empty()||self.saved.sustain{
            self.hdmi.message="请先松键并关闭延音，再确认应用 HDMI 草稿".into();return Ok(());
        }
        if let Some(draft)=self.hdmi.drafts[self.hdmi.slot as usize].clone(){
            if let Some(native)=draft.native {self.load_native(self.hdmi.slot,native)?;}
            else if let Some(program)=draft.program {self.load(self.hdmi.slot,program,Some(draft.operators))?;}
        }
        self.hdmi.drafts[self.hdmi.slot as usize]=None;self.hdmi.refresh_flags();self.hdmi.message="当前槽的 HDMI 草稿已由 FPGA 确认".into();Ok(())
    }
    pub(super) fn hdmi_cancel(&mut self)->Result<(),String>{
        self.hdmi.drafts[self.hdmi.slot as usize]=None;self.hdmi.refresh_flags();self.hdmi.message="已取消当前槽的旋钮草稿，硬件音色未改变".into();Ok(())
    }
    pub(super) fn hdmi_step(&mut self)->Result<(),String>{
        if self.hdmi.available==Some(false){return Ok(());}
        if self.hdmi.available.is_none(){
            match self.request(3,0x10,0,&[],Effect::None){
                Ok(r)=>{let revision=u32_at(&r,12);self.hdmi.available=Some(u32_at(&r,8)==0x48444d31 && (revision==0x10000||revision==0x10001));self.hdmi.page_count=if revision==0x10001{8}else{6};}
                Err(e) if e=="通信控制器拒绝请求，状态5"||self.last_engine_status==Some(5)=>{self.hdmi.available=Some(false);}
                Err(e)=>return Err(e),
            }
            return Ok(());
        }
        if self.hdmi.rgb_available.is_none(){
            match self.request(3,0x18,0,&[],Effect::None){
                Ok(r)=>{
                    self.hdmi.rgb_available=Some(u32_at(&r,8)==0x52474231 && u32_at(&r,16)==0x10000);
                    if self.hdmi.rgb_available==Some(true){self.hdmi.rgb_mode=r[12];self.hdmi.rgb_direction=r[13]&1!=0;}
                }
                Err(e) if e=="通信控制器拒绝请求，状态5"=>{self.hdmi.rgb_available=Some(false);}
                Err(e)=>return Err(e),
            }
            return Ok(());
        }
        self.hdmi.refresh_revisions(&self.saved.slots);
        self.hdmi.phase=self.hdmi.phase.wrapping_add(1);
        if self.hdmi.phase%3!=0 && !(self.storage.service && self.hdmi.page>=6) {
            let image=self.hdmi_image();
            if let Some(chunk)=self.hdmi.next_chunk(&image){
                self.request(3,0x12,chunk as u8,&[u32_at(&image,chunk*8),u32_at(&image,chunk*8+4)],Effect::None)?;
                self.hdmi.cached[chunk*8..chunk*8+8].copy_from_slice(&image[chunk*8..chunk*8+8]);
                return Ok(());
            }
        }
        let reply=self.request(3,0x13,0,&[],Effect::None)?;
        let counts=std::array::from_fn(|i|i16::from_le_bytes([reply[8+i*2],reply[9+i*2]]));
        let confirm=u16::from_le_bytes([reply[20],reply[21]]);
        let focus=reply[19];
        let focus_step=self.hdmi.focus.map(|old|focus.wrapping_sub(old) as i8).filter(|d|d.unsigned_abs()<=32).unwrap_or(0);
        self.hdmi.focus=Some(focus);
        self.hdmi.page=reply[18];
        if self.storage.service {self.hdmi.slot=reply[22]&3;self.hdmi.refresh_flags();}
        let initialized=self.hdmi.counts.is_some();
        let steps=self.hdmi.steps(counts);
        if initialized {
            if self.hdmi.page>=6 {
                if steps[0]!=0 && !self.storage.service {self.hdmi.select_slot(steps[0]);}
                if steps[4]!=0 {self.control((self.saved.volume+f64::from(steps[4])*0.01).clamp(0.,1.),self.saved.sustain,false)?;}
                if confirm!=self.hdmi.confirm {
                    self.hdmi.confirm=confirm;
                    self.hdmi.message=if self.storage.service{"SD 操作由板卡独立执行，请查看存储状态"}else{"当前固件尚未接通 SD 存取服务"}.into();
                }
                return Ok(());
            }
            // Each slot owns its draft; navigation never blocks or applies audio changes.
            if steps[0]!=0 && !self.storage.service {
                self.hdmi.select_slot(steps[0]);
                self.hdmi.message=format!("已选择音色槽 {}；各槽草稿在本次连接中分别保留",self.hdmi.slot+1);
            }
            self.hdmi.operator=(i16::from(self.hdmi.operator)+steps[1]+i16::from(focus_step)).rem_euclid(6) as u8;
            if steps[2]!=0||steps[3]!=0 {
                let slot=self.saved.slots[self.hdmi.slot as usize].clone();
                self.hdmi.message=if self.hdmi.edit_current(&slot,steps[2],steps[3]){
                    "旋钮改动已保留为草稿，按摇杆确认；可随时切换音色槽"
                }else{"旋钮已收到；参数已到边界，或当前算子不支持频率比调整"}.into();
            }
            if steps[4]!=0 {self.control((self.saved.volume+f64::from(steps[4])*0.01).clamp(0.,1.),self.saved.sustain,false)?;}
            if confirm!=self.hdmi.confirm {self.hdmi.confirm=confirm;self.hdmi_commit()?;}
        } else {self.hdmi.confirm=confirm;}
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]fn ui_edit_clamps_dx_and_preserves_envelopes(){
        let(_,mut slot)=compile(4,0,1,None).unwrap();let original=slot.operators[0].rates;
        assert!(edit(&mut slot,0,300,300));assert_eq!(slot.operators[0].output,99);assert_eq!(slot.operators[0].ratio,Some(64.));assert_eq!(slot.operators[0].rates,original);
        edit(&mut slot,0,-300,-300);assert_eq!(slot.operators[0].output,0);assert_eq!(slot.operators[0].ratio,Some(0.));
    }
    #[test]fn character_upload_has_bounded_fields(){
        let mut bytes=vec![0;32];text(&mut bytes,4,"PIANO 音色",16);assert_eq!(&bytes[4..10],b"PIANO ");assert!(bytes[4..20].iter().all(u8::is_ascii));assert_eq!(bytes[20],0);
    }
    #[test]fn slot_navigation_keeps_independent_drafts(){
        let(_,slot)=compile(4,0,1,None).unwrap();let mut h=Hdmi::default();
        assert!(h.edit_current(&slot,-1,1));let first=h.drafts[0].as_ref().unwrap().operators[0].clone();
        h.select_slot(1);assert_eq!(h.slot,1);assert!(!h.dirty);assert_eq!(h.draft_slots,vec![0]);
        assert!(h.edit_current(&slot,-2,2));h.select_slot(-1);
        assert!(h.dirty);assert_eq!(h.draft_slots,vec![0,1]);
        assert_eq!(h.drafts[0].as_ref().unwrap().operators[0].output,first.output);
        assert_eq!(h.drafts[0].as_ref().unwrap().operators[0].ratio,first.ratio);
        h.drafts[0]=None;h.refresh_flags();assert_eq!(h.draft_slots,vec![1]);
        h.select_slot(-1);assert_eq!(h.slot,3);
    }
    #[test]fn stale_slot_revision_only_invalidates_its_own_draft(){
        let(_,slot)=compile(4,0,1,None).unwrap();let mut slots=std::array::from_fn(|_|slot.clone());let mut h=Hdmi::default();
        h.edit_current(&slots[0],-1,0);h.select_slot(1);h.edit_current(&slots[1],-2,0);
        slots[0].revision+=1;h.refresh_revisions(&slots);
        assert_eq!(h.draft_slots,vec![1]);assert!(h.dirty);
    }
    #[test]fn encoder_steps_are_wrap_safe_and_replay_idempotent(){
        let mut h=Hdmi::default();assert_eq!(h.steps([32766,-32766,0,0,0]),[0;5]);
        assert_eq!(h.steps([-32766,32766,2,4,-4]),[1,-1,0,1,-1]);
        assert_eq!(h.steps([-32766,32766,2,4,-4]),[0;5]);
        assert_eq!(h.steps([-32766,32766,4,4,-4]),[0,0,1,0,0]);
    }
    #[test]fn no_op_edits_do_not_create_a_draft(){
        let(_,mut slot)=compile(4,0,1,None).unwrap();let mut h=Hdmi::default();
        slot.operators[0].output=99;slot.operators[0].ratio=None;slot.operators[0].fixed_hz=Some(100.);
        assert!(!h.edit_current(&slot,1,1));assert!(!h.dirty);assert!(h.draft_slots.is_empty());
    }
    #[test]fn footer_feedback_precedes_background_text(){
        let h=Hdmi::default();let mut desired=vec![0;1024];desired[0]=b'A';desired[832]=b'B';
        assert_eq!(h.next_chunk(&desired),Some(104));
    }
    #[test]fn library_pages_do_not_present_operator_values_or_claim_sd_files(){
        let folder=tempfile::tempdir().unwrap();let mut engine=Engine::new(folder.path().into());
        for page in [6,7] {
            engine.hdmi.page=page;engine.hdmi.slot=3;
            let image=engine.hdmi_image();
            assert!(std::str::from_utf8(&image[128..160]).unwrap().starts_with("SD STATUS NOT QUERIED"));
            assert_eq!(&image[576..595],b"DESTINATION: SLOT 4");
            assert!(image[864..896].iter().all(|b|*b==b' '));
        }
    }
}
