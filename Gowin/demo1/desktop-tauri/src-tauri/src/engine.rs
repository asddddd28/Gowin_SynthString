use crate::{
    Result, model,
    protocol::{self, Kind, Transfer},
    resources::{self, Resource, Timbre},
    surge::{Connection, Snapshot},
    transport::{self, Event, Link, SerialLink},
};
use crate::{
    midi,
    performance::{LiveState, Performance},
};
use serde_json::{Value, json};
#[path = "performance_control.rs"]
mod controls;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{Instant, SystemTime, UNIX_EPOCH},
};
struct Pending {
    resource: Value,
    indices: Vec<usize>,
    candidate: Option<Value>,
}
pub struct Engine {
    pub config: Value,
    config_path: PathBuf,
    bank: Vec<Timbre>,
    library: Vec<Resource>,
    revision: u64,
    link: Option<Box<dyn Link>>,
    online: bool,
    port: String,
    synced: BTreeSet<usize>,
    held: BTreeMap<usize, BTreeSet<String>>,
    transfer: Option<&'static str>,
    progress: usize,
    total: usize,
    batch: Vec<usize>,
    pending: Option<Pending>,
    active_resource: Value,
    pcm_available: bool,
    telemetry: Value,
    message: String,
    level: &'static str,
    last_ui: Instant,
    surge: Option<Connection>,
    snapshot: Snapshot,
    surge_message: String,
    live: LiveState,
    performance: Performance,
    midi_link: Option<midi::Connection>,
    midi_message: String,
    midi_checked: Instant,
}
fn token() -> u16 {
    static SEQUENCE: AtomicU64 = AtomicU64::new(0);
    let value = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos() as u64
        ^ SEQUENCE.fetch_add(1, Ordering::Relaxed);
    (value % 65535 + 1) as u16
}
fn atomic_write(path: &Path, v: &Value) -> Result<()> {
    let folder = path.parent().ok_or("配置路径没有父目录")?;
    fs::create_dir_all(folder).map_err(|e| e.to_string())?;
    let temp = folder.join(format!(
        ".tang-settings-{}-{}.tmp",
        std::process::id(),
        token()
    ));
    let result = (|| -> Result<()> {
        let mut f = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)
            .map_err(|e| e.to_string())?;
        f.write_all(&serde_json::to_vec_pretty(v).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
        f.sync_all().map_err(|e| e.to_string())?;
        drop(f);
        fs::rename(&temp, path).map_err(|e| e.to_string())?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}
fn export(path: &Path, v: &Value) -> Result<()> {
    fs::write(
        path,
        serde_json::to_vec_pretty(v).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())
}
impl Engine {
    pub fn new(assets: &Path, config_path: Option<PathBuf>) -> Result<Self> {
        let explicit = config_path.is_some();
        let config_path = config_path.unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("LOCALAPPDATA").unwrap_or_else(|| ".".into()))
                .join("TangSynth32/settings-tauri.json")
        });
        let bank = resources::load_bank(&assets.join("basic_bank"))?;
        let demo = assets.join("wavetable_library/TSLIB.JSN");
        let library = if demo.exists() {
            resources::load_library(&demo)?
        } else {
            vec![]
        };
        let mut s = Self {
            config: model::defaults(),
            config_path,
            bank,
            library,
            revision: 0,
            link: None,
            online: false,
            port: String::new(),
            synced: BTreeSet::new(),
            held: BTreeMap::new(),
            transfer: None,
            progress: 0,
            total: 0,
            batch: vec![],
            pending: None,
            active_resource: Value::Null,
            pcm_available: false,
            telemetry: Value::Null,
            message: "离线编辑已就绪。连接 DEBUG USB 后可同步音色。".into(),
            level: "info",
            last_ui: Instant::now(),
            surge: None,
            snapshot: Snapshot::default(),
            surge_message: "等待连接本机 Surge OSC。".into(),
            live: LiveState::default(),
            performance: Performance::new(25.0),
            midi_link: None,
            midi_message: "选择 MIDI 输入设备后连接。".into(),
            midi_checked: Instant::now(),
        };
        let source = if !s.config_path.exists() && !explicit {
            s.config_path.with_file_name("settings-pcm.json")
        } else {
            s.config_path.clone()
        };
        if source.exists() {
            match resources::read_json(&source, 2 * 1024 * 1024).and_then(|v| s.validate(v)) {
                Ok(c) => {
                    s.config = c;
                    if source != s.config_path {
                        s.message = "已读取旧版配置；保存时写入独立的 Tauri 配置。".into();
                    }
                }
                Err(e) => s.tell(format!("配置未载入，使用默认值：{e}"), "error"),
            }
        }
        s.performance.volume = s.config["sound"]["volume"].as_f64().unwrap();
        Ok(s)
    }
    fn tell(&mut self, message: impl Into<String>, level: &'static str) {
        self.message = message.into();
        self.level = level;
    }
    fn validate(&self, c: Value) -> Result<Value> {
        let c = model::validate_config(c)?;
        for (_, tid) in c["tauri_bindings"].as_object().unwrap() {
            if !self
                .bank
                .iter()
                .any(|s| Some(s.id) == tid.as_u64() && s.samples.is_some())
            {
                return Err("资源绑定未找到对应的基础波表音色".into());
            }
        }
        Ok(c)
    }
    fn commit(&mut self, c: Value) -> Result<()> {
        let c = self.validate(c)?;
        atomic_write(&self.config_path, &c)?;
        self.config = c;
        self.revision += 1;
        Ok(())
    }
    fn index(params: &Value) -> Result<usize> {
        Ok(model::integer(params, "index", 0, 31)? as usize)
    }
    fn idle(&self, connected: bool) -> Result<()> {
        if self.transfer.is_some() || !self.live.pending.is_empty() {
            return Err("请等待当前传输结束。".into());
        }
        if connected && !self.online {
            return Err("请先连接 FPGA，等待硬件响应。".into());
        }
        Ok(())
    }
    pub fn state(&mut self) -> Value {
        self.last_ui = Instant::now();
        if let Some(link) = &self.link {
            link.touch_ui();
        }
        json!({"backend":"rust","config":self.config,"revision":self.revision,"online":self.online,"connecting":self.link.is_some()&&!self.online,"port":self.port,"synced":self.synced,"held":self.held.keys().collect::<Vec<_>>(),"transfer":self.transfer,"progress":self.progress,"total":self.total,"telemetry":self.telemetry,"message":self.message,"level":self.level,"pcm_available":self.pcm_available,"active_resource":self.active_resource,"surge":{"connected":self.surge.is_some(),"patch":self.snapshot.patch,"count":self.snapshot.parameters.len(),"message":self.surge_message},"live":self.live.state(),"performance":self.performance.state(),"midi":{"connected":self.midi_link.is_some(),"name":self.midi_link.as_ref().map(|m|&m.name),"message":self.midi_message}})
    }
    fn send(&mut self, frames: Vec<protocol::Frame>) -> bool {
        self.link.as_mut().is_some_and(|l| l.send(frames))
    }
    pub fn release_all(&mut self) {
        if self.online && !self.held.is_empty() {
            let f = self
                .held
                .keys()
                .map(|i| protocol::packet(2, 32 + *i as u8, 0, 0, 0))
                .collect();
            self.send(f);
        }
        self.held.clear();
        self.performance.clear_notes();
    }
    fn disconnect(&mut self) {
        if let Some(mut l) = self.link.take() {
            l.close();
        }
        self.online = false;
        self.port.clear();
        self.held.clear();
        self.synced.clear();
        self.transfer = None;
        self.pending = None;
        self.active_resource = Value::Null;
        self.pcm_available = false;
        self.telemetry = Value::Null;
        self.live = LiveState::default();
        self.performance.clear_notes();
        self.performance.pending_volume = None;
        self.tell("设备已断开。音色保留在电脑中。", "info");
    }
    fn note_on(&mut self, index: usize, owner: &str) -> Result<()> {
        self.start_note(index, owner, None, false)
    }
    fn note_off(&mut self, index: usize, owner: &str) {
        if let Some(owners) = self.held.get_mut(&index) {
            if !owners.remove(owner) {
                return;
            }
            if self.performance.sustain(owner) {
                owners.insert(format!("sustain:{owner}"));
            }
            if owners.is_empty() {
                self.held.remove(&index);
                if self.online {
                    self.send(vec![protocol::packet(2, 32 + index as u8, 0, 0, 0)]);
                }
            }
        }
    }
    fn unbind(c: &mut Value, index: usize) {
        c["tauri_bindings"]
            .as_object_mut()
            .unwrap()
            .remove(&index.to_string());
    }
    fn save_key(&mut self, index: usize, key: Value) -> Result<()> {
        self.idle(false)?;
        let mut c = self.config.clone();
        c["keys"][index] = key;
        if !model::custom(&c["keys"][index]["synth"]) {
            Self::unbind(&mut c, index);
        }
        let c = self.validate(c)?;
        let confirmed = self.synced.contains(&index)
            && self.live.applied.get(&index).is_some_and(|p| {
                crate::performance::normalized(p.clone())
                    == crate::performance::normalized(c["keys"][index]["synth"].clone())
            });
        let same_mapping = ["note", "keycode", "velocity"]
            .iter()
            .all(|f| c["keys"][index][*f] == self.config["keys"][index][*f]);
        if !confirmed || !same_mapping {
            self.release_all();
        }
        self.commit(c)?;
        self.live.forget(index);
        if !confirmed {
            self.synced.remove(&index);
        }
        self.tell(
            format!(
                "音键 {:02} 已保存到电脑{}。",
                index + 1,
                if confirmed {
                    "，硬件参数已确认"
                } else {
                    "，尚未同步"
                }
            ),
            "info",
        );
        Ok(())
    }
    fn bank_sound(&self, id: u64) -> Result<&Timbre> {
        self.bank
            .iter()
            .find(|s| s.id == id)
            .ok_or("没有找到该音色。".into())
    }
    fn start_profiles(&mut self, indices: Vec<usize>) -> Result<()> {
        for i in &indices {
            self.live.forget(*i);
        }
        self.release_all();
        let batch: Vec<_> = indices
            .iter()
            .map(|i| {
                let mut p = self.config["keys"][*i]["synth"].clone();
                p.as_object_mut()
                    .unwrap()
                    .entry("frame_position")
                    .or_insert(json!(0));
                (32 + *i as u8, p)
            })
            .collect();
        let t = Transfer::profiles(&batch, 0.0, token())?;
        if !self.link.as_mut().is_some_and(|l| l.upload(t)) {
            return Err("设备拒绝参数上传，请稍后重试。".into());
        }
        for i in &indices {
            self.synced.remove(i);
        }
        self.total = indices.len();
        self.batch = indices;
        self.transfer = Some("profiles");
        self.progress = 0;
        self.tell("正在上传音键参数，等待硬件校验…", "info");
        Ok(())
    }
    fn invalidate_waves(&mut self) {
        let indices: Vec<_> = (0..32)
            .filter(|i| {
                model::custom(&self.config["keys"][*i]["synth"])
                    || self.live.applied.get(i).is_some_and(model::custom)
            })
            .collect();
        for i in indices {
            self.synced.remove(&i);
            self.live.forget(i);
        }
    }
    fn start_resource(
        &mut self,
        frames: Vec<Vec<i16>>,
        resource: Value,
        indices: Vec<usize>,
        candidate: Option<Value>,
    ) -> Result<()> {
        self.idle(true)?;
        self.release_all();
        let t = Transfer::table(&frames, 0.0, token())?;
        if !self.link.as_mut().is_some_and(|l| l.upload(t)) {
            return Err("设备拒绝波表上传，请稍后重试。".into());
        }
        // A lost commit ACK can leave the physical bank changed. Never trust old residency.
        self.active_resource = Value::Null;
        self.invalidate_waves();
        self.pending = Some(Pending {
            resource,
            indices,
            candidate,
        });
        self.transfer = Some("wavetable");
        self.progress = 0;
        self.total = frames.len() * 1024;
        self.tell("正在传输波表；等待资源提交后再同步音键参数。", "info");
        Ok(())
    }
    fn sync(&mut self, params: &Value) -> Result<()> {
        self.idle(true)?;
        let a = params["indices"]
            .as_array()
            .filter(|a| !a.is_empty() && a.len() <= 32)
            .ok_or("请选择 1–32 个不同音键。")?;
        let indices: Vec<usize> = a
            .iter()
            .map(|v| {
                v.as_u64()
                    .filter(|n| *n < 32)
                    .map(|n| n as usize)
                    .ok_or_else(|| "音键编号必须为 0–31".to_string())
            })
            .collect::<Result<_>>()?;
        if indices.iter().collect::<BTreeSet<_>>().len() != indices.len() {
            return Err("请选择 1–32 个不同音键。".into());
        }
        let resources: BTreeSet<u64> = indices
            .iter()
            .filter(|i| model::custom(&self.config["keys"][**i]["synth"]))
            .filter_map(|i| self.config["tauri_bindings"][i.to_string()].as_u64())
            .collect();
        if resources.len() > 1 {
            return Err("板上只有一对共享波表。多个不同波表音色请分别同步。".into());
        }
        if let Some(id) = resources.first()
            && self.active_resource != *id
        {
            let samples = self
                .bank_sound(*id)?
                .samples
                .clone()
                .ok_or("缺少波表资源")?;
            return self.start_resource(vec![samples.clone(), samples], json!(id), indices, None);
        }
        self.start_profiles(indices)
    }
    fn library_catalog(&self) -> Value {
        json!(self.library.iter().enumerate().map(|(i,r)|json!({"id":i,"title":r.title,"frames":r.frames.len(),"resource_id":r.id,"revision":r.revision})).collect::<Vec<_>>())
    }
    fn pair(&self, p: &Value) -> Result<(Vec<Vec<i16>>, Value)> {
        let i = model::integer(p, "resource_id", 0, usize::MAX as u64)? as usize;
        self.library
            .get(i)
            .ok_or("请选择波表资源")?
            .pair(model::num(p, "position", 0.0, 100.0)?)
    }
    pub fn dispatch(&mut self, method: &str, p: Value) -> Result<Value> {
        if !p.is_object() {
            return Err("参数格式错误".into());
        }
        if let Some(result) = self.performance_command(method, &p) {
            return result;
        }
        match method {
            "get_state"=>return Ok(self.state()),"ports"=>return transport::ports(),
            "connect"=>{if self.link.is_some() {return Err("请先断开当前设备。".into());}let name=model::text(&p,"port")?;if !transport::ports()?.as_array().unwrap().iter().any(|v|v["device"]==name) {return Err("请选择当前可用的串口。".into());}let link=SerialLink::open(name)?;self.link=Some(Box::new(link));self.port=name.into();self.tell("串口已打开，等待 FPGA 状态包…","info");},
            "disconnect"=>self.disconnect(),"release_all"=>self.release_all(),
            "panic"=>{let uploading=self.transfer.is_some();if uploading {self.disconnect();} else if let Some(l)=self.link.as_mut() {l.panic();}self.held.clear();self.performance.clear_notes();self.live.pending.clear();preview(None)?;self.tell(if uploading {"已中止传输并断开设备。请重新连接后同步。"} else {"已请求紧急停止全部声部并停止电脑试听。"},"info");},
            "note_on"=>self.note_on(Self::index(&p)?,model::text(&p,"owner")?)?,
            "note_off"=>self.note_off(Self::index(&p)?,model::text(&p,"owner")?),
            "save_key"=>self.save_key(Self::index(&p)?,p["key"].clone())?,
            "bank_catalog"=>return Ok(json!(self.bank.iter().map(|s|json!({"id":s.id,"title":s.title,"category":s.category,"description":s.description,"profile":s.profile,"resource_id":s.resource_id,"waveform":s.samples.as_ref().map(|a|a.iter().step_by(8).copied().collect::<Vec<_>>())})).collect::<Vec<_>>())),
            "load_preset"=>{
                self.idle(false)?;let i=Self::index(&p)?;let sound=self.bank_sound(model::integer(&p,"timbre_id",1,65535)?)?.clone();
                let mut c=self.config.clone();c["keys"][i]["name"]=json!(sound.title.chars().take(24).collect::<String>());c["keys"][i]["synth"]=sound.profile;
                if sound.samples.is_some() {c["tauri_bindings"][i.to_string()]=json!(sound.id);} else {Self::unbind(&mut c,i);}
                self.release_all();self.commit(c)?;self.live.forget(i);self.synced.remove(&i);self.tell(format!("「{}」已载入音键 {:02}，同步后可在硬件演奏。",sound.title,i+1),"info");
            },
            "preview"=>{let s=self.bank_sound(model::integer(&p,"timbre_id",1,65535)?)?;preview(Some(&s.preview))?;let message=format!("电脑参考试听：{}（不是 FPGA 录音）。",s.title);self.tell(message,"info");},
            "preview_stop"=>preview(None)?,"sync"=>self.sync(&p)?,
            "library_catalog"=>return Ok(self.library_catalog()),
            "load_library_file"=>{self.library=resources::load_file(Path::new(model::text(&p,"path")?))?;self.tell(format!("已校验 {} 个波表资源。",self.library.len()),"info");return Ok(self.library_catalog());},
            "wave_preview"=>{let (frames,mut job)=self.pair(&p)?;job["frames"]=json!(frames.iter().map(|f|f.iter().step_by(4).copied().collect::<Vec<_>>()).collect::<Vec<_>>());return Ok(job);},
            "upload_wave"=>{
                let i=Self::index(&p)?;let (mut frames,job)=self.pair(&p)?;let single=match p.get("single") {None=>false,Some(v)=>v.as_bool().ok_or("single 必须为布尔值")?};
                let mut c=self.config.clone();let profile=&mut c["keys"][i]["synth"];
                profile["mode"]=json!("波表混合");profile["wave_a"]=json!(model::CUSTOM);profile["gain_a"]=json!(100.0);profile["gain_b"]=json!(0.0);profile["frame_position"]=json!(if single {0.0} else {job["fraction"].as_f64().unwrap()*100.0/65535.0});Self::unbind(&mut c,i);
                if single {frames.truncate(1);}self.start_resource(frames,json!("library"),vec![i],Some(c))?;
            },
            "upload_piano_wave"=>{let i=Self::index(&p)?;let mut c=self.config.clone();let mut profile=model::from_sound(&model::piano_sound());profile["wave_a"]=json!(model::CUSTOM);profile["gain_a"]=json!(100.0);profile["gain_b"]=json!(0.0);c["keys"][i]["synth"]=profile;Self::unbind(&mut c,i);self.start_resource(vec![resources::piano_table()],json!("piano"),vec![i],Some(c))?;},
            "upload_pcm"=>{self.idle(true)?;let i=Self::index(&p)?;let (meta,data)=resources::load_pcm(Path::new(model::text(&p,"path")?))?;self.release_all();let total=data.len();let t=Transfer::pcm(meta,data,0.0,token())?;if !self.link.as_mut().is_some_and(|l|l.upload(t)) {return Err("设备拒绝采样上传".into());}self.pending=Some(Pending{resource:Value::Null,indices:vec![i],candidate:None});self.transfer=Some("pcm");self.progress=0;self.total=total;self.pcm_available=false;self.tell("正在上传 PCM 采样包…","info");},
            "set_output"=>{self.idle(false)?;let volume=model::num(&p,"volume",0.0,100.0)?;let boost=model::integer(&p,"boost",0,4)?;let mut c=self.config.clone();c["sound"]["volume"]=json!(volume);c["sound"]["output_boost"]=json!(boost);self.commit(c)?;self.performance.volume=volume;self.performance.pending_volume=None;if self.online&&!self.send(vec![protocol::packet(3,12,0,0,boost as u16),protocol::packet(3,0,0,0,(volume*65535.0/100.0).round_ties_even() as u16)]) {return Err("设置已保存，但串口发送失败，请重新连接。".into());}self.tell("输出设置已保存，连接时将发送到硬件。","info");},
            "apply_template"=>{self.idle(false)?;let mut c=self.config.clone();c["sound"]=p["sound"].clone();c=model::validate_config(c)?;let profile=model::from_sound(&c["sound"]);for k in c["keys"].as_array_mut().unwrap() {k["synth"]=profile.clone();}c["tauri_bindings"]=json!({});self.release_all();self.commit(c)?;self.synced.clear();self.live=LiveState::default();self.tell("已覆盖全部音键音色；尚未同步。","info");},
            "import_config"=>{self.idle(false)?;let c=self.validate(resources::read_json(Path::new(model::text(&p,"path")?),2*1024*1024)?)?;self.release_all();self.commit(c)?;self.synced.clear();self.live=LiveState::default();self.tell("配置已导入；请重新同步。","info");},
            "export_config"=>{export(Path::new(model::text(&p,"path")?),&self.config)?;self.tell("配置已导出。","info");},
            "surge_connect"=>{let input=p.get("input_port").map(|_|model::integer(&p,"input_port",1024,65535)).transpose()?.unwrap_or(53280) as u16;let output=p.get("output_port").map(|_|model::integer(&p,"output_port",1024,65535)).transpose()?.unwrap_or(53281) as u16;self.surge=None;self.snapshot=Snapshot::default();self.surge=Some(Connection::open(input,output)?);self.surge_message="等待 Surge OSC 回包…".into();},
            "surge_disconnect"=>{self.surge=None;self.surge_message="已停止读取，保留快照。".into();},
            "surge_data"=>return Ok(self.snapshot.export()),
            "surge_import"=>{let s=Snapshot::load(&resources::read_json(Path::new(model::text(&p,"path")?),2*1024*1024)?)?;self.surge=None;self.snapshot=s;self.surge_message="已载入参数快照。".into();},
            "surge_export"=>export(Path::new(model::text(&p,"path")?),&self.snapshot.export())?,
            "surge_apply"=>{self.idle(false)?;let i=Self::index(&p)?;let scene=p.get("scene").map(|_|model::text(&p,"scene")).transpose()?.unwrap_or("a");let mut k=self.config["keys"][i].clone();k["synth"]=self.snapshot.map_envelope(&k["synth"],scene)?;self.save_key(i,k)?;self.tell("Surge ADSR 已保存到当前键，请同步后演奏。","info");return Ok(json!(["只映射 A/D/S/R；保留当前振荡器与调制参数。","FPGA 线性包络与 Surge 曲线可能不同。","尚非完整 Surge 音色转换。"]));},
            _=>return Err("未知命令".into())
        }
        Ok(Value::Null)
    }
    pub fn tick(&mut self) {
        if !self.held.is_empty() && self.last_ui.elapsed().as_secs_f64() > 1.5 {
            self.release_all();
            self.tell("界面心跳中断，已释放全部按键。", "error");
        }
        self.performance_tick();
        if let Some(s) = &self.surge {
            match s.poll(&mut self.snapshot) {
                Ok(n) if n > 0 => self.surge_message = "正在读取本机 Surge 参数。".into(),
                Ok(_) => {}
                Err(e) => {
                    self.surge = None;
                    self.snapshot = Snapshot::default();
                    self.surge_message = e;
                }
            }
        }
        let events = self.link.as_mut().map(|l| l.poll()).unwrap_or_default();
        for e in events {
            if let Err(error) = self.handle_event(e) {
                self.transfer = None;
                self.pending = None;
                self.tell(error, "error");
            }
            if self.link.is_none() {
                break;
            }
        }
    }
    pub fn handle_event(&mut self, e: Event) -> Result<()> {
        match e {
            Event::Status(v) => {
                let first = !self.online;
                self.online = true;
                self.telemetry = v;
                if first {
                    self.performance.volume = self.config["sound"]["volume"].as_f64().unwrap();
                    let mut frames = vec![protocol::command(4)];
                    frames.extend(protocol::sound_packets(&self.config["sound"]));
                    frames.push(protocol::command(0x36));
                    if !self.send(frames) {
                        return Err("初始设置发送失败，请重新连接。".into());
                    }
                    self.tell("FPGA 已响应。请同步需要演奏的音键。", "success");
                }
            }
            Event::PcmStatus(v) => self.pcm_available = v,
            Event::Progress(v) => {
                if self.transfer.is_some() {
                    self.progress = v;
                }
            }
            Event::Done(Kind::Profiles) if self.transfer == Some("profiles") => {
                if self.finish_live() {
                    return Ok(());
                }
                self.synced.extend(&self.batch);
                self.transfer = None;
                self.tell("音键参数已通过硬件校验，可以演奏。", "success");
            }
            Event::Done(Kind::Table | Kind::Pair) if self.transfer == Some("wavetable") => {
                if let Some(p) = self.pending.take() {
                    self.transfer = None;
                    self.active_resource = p.resource;
                    self.invalidate_waves();
                    if let Some(c) = p.candidate {
                        self.commit(c)?;
                    }
                    self.start_profiles(p.indices)?;
                }
            }
            Event::Done(Kind::Pcm) if self.transfer == Some("pcm") => {
                if let Some(p) = self.pending.take() {
                    let i = p.indices[0];
                    self.transfer = None;
                    self.pcm_available = true;
                    let mut c = self.config.clone();
                    c["keys"][i]["synth"] = model::pcm_profile();
                    Self::unbind(&mut c, i);
                    self.synced.remove(&i);
                    self.commit(c)?;
                    self.start_profiles(vec![i])?;
                }
            }
            Event::TransferError(e) => {
                self.live_failure(&e);
                self.transfer = None;
                self.pending = None;
                self.tell(e, "error");
            }
            Event::Error(e) => {
                self.disconnect();
                self.tell(e, "error");
            }
            Event::NotesReleased => {
                self.held.clear();
                self.performance.clear_notes();
                self.tell("界面心跳中断，串口线程已释放全部按键。", "error");
            }
            _ => {}
        }
        Ok(())
    }
    pub fn close(&mut self) {
        self.midi_link = None;
        self.surge = None;
        let _ = preview(None);
        self.disconnect();
    }
    #[cfg(any(test, feature = "test-harness"))]
    pub fn test_connect(&mut self) {
        self.link = Some(Box::<transport::RecordingLink>::default());
        self.online = true;
        self.synced = (0..32).collect();
    }
    #[cfg(any(test, feature = "test-harness"))]
    pub fn test_frames(&self) -> Value {
        json!(self.link.as_ref().map(|l| l.recorded()).unwrap_or_default())
    }
    #[cfg(any(test, feature = "test-harness"))]
    pub fn test_midi(&mut self, bytes: &[u8]) {
        if let Some(message) = midi::decode(bytes) {
            self.handle_midi(message);
        }
    }
    #[cfg(test)]
    pub fn advance_performance(&mut self) {
        self.live.last_send = Instant::now() - std::time::Duration::from_secs(1);
        self.performance.last_volume_send = Instant::now() - std::time::Duration::from_secs(1);
        self.performance_tick();
    }
    #[cfg(test)]
    pub fn expire_ui(&mut self) {
        self.last_ui = Instant::now() - std::time::Duration::from_secs(2);
    }
}
impl Drop for Engine {
    fn drop(&mut self) {
        self.close();
    }
}
#[cfg(windows)]
fn preview(path: Option<&Path>) -> Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Media::Audio::{PlaySoundW, SND_ASYNC, SND_FILENAME, SND_NODEFAULT};
    let wide = path.map(|p| {
        p.as_os_str()
            .encode_wide()
            .chain(Some(0))
            .collect::<Vec<_>>()
    });
    // PlaySound copies the filename before returning; no sample memory is borrowed.
    let result = unsafe {
        PlaySoundW(
            wide.as_ref().map_or(std::ptr::null(), |v| v.as_ptr()),
            std::ptr::null_mut(),
            if path.is_some() {
                SND_ASYNC | SND_FILENAME | SND_NODEFAULT
            } else {
                0
            },
        )
    };
    if result == 0 && path.is_some() {
        return Err("Windows 音频试听启动失败".into());
    }
    Ok(())
}
#[cfg(not(windows))]
fn preview(path: Option<&Path>) -> Result<()> {
    if path.is_some() {
        Err("此版本的参考试听只支持 Windows".into())
    } else {
        Ok(())
    }
}
