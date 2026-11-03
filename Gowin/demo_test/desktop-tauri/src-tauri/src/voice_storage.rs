//! SD operations run on the FPGA. App submits intent and observes completion.
use super::{Engine, Effect, u32_at};
use serde::Serialize;

#[derive(Clone,Default,Serialize)]
pub struct Storage {
    pub available:Option<bool>, pub initialized:bool, pub catalog_ready:bool,
    pub busy:bool, pub sector_error:u8, pub catalog_error:u8, pub sectors:u32,
    pub state:String, pub message:String,
    pub service:bool,pub library_ready:bool,pub dirty:bool,pub error:u8,pub generation:u32,
    pub sequence:u8,pub preset:u8,pub sequence_count:u8,pub preset_count:u8,pub syncing:bool,
    #[serde(skip)] synced_generation:Option<u32>,
    #[serde(skip)] sync_slot:u8,
    #[serde(skip)] sync_revision:u32,
    #[serde(skip)] sync_words:Vec<u32>,
    #[serde(skip_serializing_if="Option::is_none")]
    pub block_lba:Option<u32>,
    #[serde(skip_serializing_if="Vec::is_empty")]
    pub block:Vec<u8>,
}

impl Storage {
    fn decode(signature:u32, status:u32, sectors:u32)->Result<Self,String>{
        if signature!=0x53444331 || !(1..=2).contains(&(status>>24)) || status&0xe0!=0 {
            return Err("未知 SD 状态接口；未发送写入命令".into());
        }
        let mut value=Self{available:Some(true),initialized:status&1!=0,
            catalog_ready:status&2!=0,busy:status&4!=0,
            sector_error:(status>>8) as u8,catalog_error:(status>>16) as u8,sectors,
            service:status>>24==2,..Self::default()};
        let (state,message)=if value.sector_error!=0 {
            ("io_error",format!("SD 通信失败（{}）；请检查插卡和连接",value.sector_error))
        }else if !value.initialized {
            ("initializing","SD 正在初始化，尚未确认卡容量".into())
        }else if value.busy {
            ("checking","已识别 SD 卡，正在校验音序和预设目录".into())
        }else if value.catalog_error!=0 {
            ("unprepared",format!("已识别 SD 卡，音序/预设目录尚未就绪（0x{:02X}）",value.catalog_error))
        }else if value.catalog_ready {
            ("catalog_ready","SD 卡和专用目录已就绪；当前固件尚未接通保存/加载服务".into())
        }else {
            ("detected","已识别 SD 卡，等待目录校验".into())
        };
        value.state=state.into();value.message=message;Ok(value)
    }
    pub(super) fn hdmi_title(&self)->&str {
        match self.state.as_str(){
            "io_error"=>"SD COMMUNICATION ERROR", "initializing"=>"SD INITIALIZING",
            "checking"=>"SD CARD / CHECKING CATALOG", "unprepared"=>"SD CARD / CATALOG NOT READY",
            "catalog_ready"=>"SD CARD / CATALOG READY", "detected"=>"SD CARD DETECTED",
            "unsupported"=>"NO SD INTERFACE IN FIRMWARE", _=>"SD STATUS NOT QUERIED",
        }
    }
}
impl Engine {
    pub(super) fn storage_action(&mut self,operation:u8,number:u8,slot:u8)->Result<(),String>{
        self.ready()?;
        if self.saved.wave.is_some() || self.keyboard.calibration.is_some(){return Err("请先完成波表上传或键盘校准".into());}
        self.storage_step()?;
        if !self.storage.service || !self.storage.library_ready || self.storage.busy || self.storage.syncing{return Err("SD 文件库正在准备或同步，请稍后再试".into());}
        if !(1..=5).contains(&operation)||slot>3{return Err("SD 操作或音色槽无效".into());}
        if operation==2 && self.storage.dirty{return Err("当前录音尚未保存，请先保存或清空 RAM 录音".into());}
        self.request(3,0x14,slot,&[],Effect::None)?;
        self.hdmi.slot=slot;
        self.request(3,0x54,operation,&[u32::from(number)],Effect::None)?;
        self.storage.busy=true;self.storage.message="板卡正在执行 SD 操作，可以脱离 App 独立完成".into();Ok(())
    }
    fn storage_sync(&mut self)->Result<(),String>{
        if self.storage.sync_slot>=4 {self.storage.syncing=false;self.storage.synced_generation=Some(self.storage.generation);return Ok(());}
        let slot=self.storage.sync_slot;
        if self.storage.sync_words.is_empty(){
            let r=self.request(0,0xaa,6,&[u32::from(slot)],Effect::None)?;
            let revision=u32_at(&r,8);
            if revision==self.saved.slots[usize::from(slot)].revision{self.storage.sync_slot+=1;return Ok(());}
            self.storage.sync_revision=revision;
        }
        for _ in 0..16 {
            let index=self.storage.sync_words.len();if index==110{break;}
            let (category,selector)=super::storage_patch::selector(index,slot);
            let r=self.request(0,0xaa,category,&[selector],Effect::None)?;
            self.storage.sync_words.push(u32_at(&r,8));
        }
        if self.storage.sync_words.len()==110{
            let r=self.request(0,0xaa,6,&[u32::from(slot)],Effect::None)?;
            if u32_at(&r,8)==self.storage.sync_revision {
                self.saved.slots[usize::from(slot)]=super::storage_patch::decode(self.storage.sync_words.clone(),self.storage.sync_revision,slot)?;
                self.saved.notes.clear();self.save()?;self.storage.sync_slot+=1;
            }
            self.storage.sync_words.clear();
        }
        Ok(())
    }
    #[cfg(feature="test-harness")]
    pub(super) fn storage_restart(&mut self)->Result<(),String>{
        self.storage_step()?;
        if self.storage.available!=Some(true) || self.storage.busy {
            return Err("SD 接口不可用或仍在忙；未重新初始化".into());
        }
        self.request(3,0x55,0,&[],Effect::None)?;
        self.storage=Storage::default();
        Ok(())
    }
    #[cfg(feature="test-harness")]
    pub(super) fn storage_read(&mut self,lba:u32)->Result<(),String>{
        self.storage_step()?;
        if !self.storage.initialized || self.storage.busy || lba>=self.storage.sectors {
            return Err("SD 未就绪或只读地址越界".into());
        }
        self.storage.block.clear();self.storage.block_lba=None;
        self.request(3,0x51,0,&[lba],Effect::None)?;
        let mut block=Vec::with_capacity(512);
        for chunk in 0..32 {
            let r=self.request(3,0x52,chunk,&[],Effect::None)?;
            block.extend_from_slice(&r[8..24]);
        }
        self.storage.block=block;self.storage.block_lba=Some(lba);Ok(())
    }
    pub(super) fn storage_step(&mut self)->Result<(),String>{
        self.ready()?;
        if self.storage.available==Some(false){return Ok(());}
        match self.request(3,0x50,0,&[],Effect::None){
            Ok(r)=>{
                let mut next=Storage::decode(u32_at(&r,8),u32_at(&r,12),u32_at(&r,16))?;
                next.synced_generation=self.storage.synced_generation;next.sync_slot=self.storage.sync_slot;
                next.generation=self.storage.generation;
                next.sync_revision=self.storage.sync_revision;next.sync_words=std::mem::take(&mut self.storage.sync_words);next.syncing=self.storage.syncing;
                self.storage=next;
            },
            Err(e) if e=="通信控制器拒绝请求，状态5"=>{
                self.storage=Storage{available:Some(false),state:"unsupported".into(),
                    message:"当前固件未启用 SD 存储".into(),..Storage::default()};
            },
            Err(e)=>return Err(e),
        }
        if self.storage.service {
            let r=self.request(3,0x56,0,&[],Effect::None)?;
            if u32_at(&r,8)!=0x53444c31{return Err("SD 文件服务版本不匹配".into());}
            let status=u32_at(&r,12);let numbers=u32_at(&r,16);let generation=u32_at(&r,20);
            self.storage.library_ready=status&1!=0;self.storage.busy=status&2!=0;self.storage.dirty=status&4!=0;self.storage.error=(status>>8) as u8;
            self.storage.sequence=numbers as u8;self.storage.preset=(numbers>>8) as u8;
            self.storage.sequence_count=(numbers>>16) as u8;self.storage.preset_count=(numbers>>24) as u8;
            if self.storage.generation!=generation || (!self.storage.syncing && self.storage.synced_generation!=Some(generation)){
                self.storage.sync_slot=0;self.storage.sync_words.clear();self.storage.syncing=true;
            }
            self.storage.generation=generation;
            // Hardware patches are readable even without a mounted SD library.
            // A missing card must not leave ordinary performance locked in sync.
            if !self.storage.busy{self.storage_sync()?;}
            self.storage.message=if self.storage.busy{"板卡正在扫描或处理 SD 文件".into()}
                else if self.storage.syncing {format!("正在读取板上 Slot {} 的实际音色参数",self.storage.sync_slot.min(3)+1)}
                else if self.storage.error!=0 {storage_error(self.storage.error).into()}
                else if self.storage.library_ready {format!("独立 SD 存取已就绪：{} 段音序、{} 个预设",self.storage.sequence_count,self.storage.preset_count)}
                else {self.storage.message.clone()};
        }
        Ok(())
    }
}

fn storage_error(code:u8)->&'static str{
    match code{0x30=>"当前录音状态不允许操作，或目标音色槽被录音引用",0xb0=>"先保存或清空当前未保存录音，再切换文件",
        0xb1=>"64 个编号已使用，请用读卡器整理文件库",0xb2=>"文件编号或操作无效",0xb3=>"该编号没有有效文件",
        0xb4=>"文件位置不在已验证目录内",0xb5|0x88=>"文件校验失败，未提交加载",0xb6=>"再按一次摇杆确认删除当前文件",
        _=>"SD 操作失败；保留原存档，请检查卡状态后重试"}
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]fn sd_status_distinguishes_card_catalog_and_io(){
        let capacity=124735488;
        let detected=Storage::decode(0x53444331,0x01000001,capacity).unwrap();
        assert!(detected.initialized);assert_eq!(detected.state,"detected");
        let missing=Storage::decode(0x53444331,0x01450019,capacity).unwrap();
        assert!(missing.initialized);assert!(!missing.catalog_ready);assert_eq!(missing.state,"unprepared");
        let ready=Storage::decode(0x53444331,0x01000013,capacity).unwrap();
        assert_eq!(ready.state,"catalog_ready");assert_eq!(ready.sectors,capacity);
        assert_eq!(Storage::decode(0x53444331,0x01000108,0).unwrap().state,"io_error");
        assert_eq!(Storage::decode(0x53444331,0x01000005,capacity).unwrap().state,"checking");
        assert!(Storage::decode(0,0x01000001,capacity).is_err());
        assert!(Storage::decode(0x53444331,0x02000001,capacity).unwrap().service);
    }
}
