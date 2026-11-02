use crate::{
    audio::Audio,
    calibration::{atomic_json, Calibration, Profile},
    link::Link,
    model::{Model, Settings, View},
    protocol::{Command, Frame, Parser},
};
use crossbeam_channel::{bounded, unbounded, Receiver, Sender};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    fs::File,
    io::{Read, Write},
    path::PathBuf,
    sync::{Arc, Mutex},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[derive(Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Action {
    Connect { port: String },
    Disconnect,
    Sync,
    Effect { mode: u8, direction: u8 },
    GameStart { game: u8 },
    GameStop,
    ZeroEncoders,
    CalibrationStart { targets: Vec<usize> },
    CalibrationPress,
    CalibrationApply,
    CalibrationCancel,
    Thresholds { press: f64, release: f64 },
    Settings { settings: Settings },
    Page { page: String },
    Panic,
    Record,
    Replay { path: String },
    Import { path: String },
}
struct Request {
    action: Action,
    reply: Sender<Result<String, String>>,
}
#[derive(Serialize)]
pub struct Snapshot {
    #[serde(flatten)]
    pub view: View,
    pub chart: Vec<[f64; 2]>,
}
pub struct Service {
    tx: Sender<Request>,
    pub shared: Arc<Mutex<(View, Vec<Vec<[f64; 2]>>)>>,
    pub audio: Arc<Audio>,
    pub data_dir: PathBuf,
}
impl Service {
    pub fn start() -> Self {
        let base = std::env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("."));
        let data_dir = base.join("TangHardwareLab");
        let legacy = base.join("TangKeyboardLab");
        let mut warnings = vec![];
        let profile_path = if data_dir.join("calibration.json").exists() {
            data_dir.join("calibration.json")
        } else {
            legacy.join("calibration.json")
        };
        let profile = match Profile::load(&profile_path) {
            Ok(p) => p,
            Err(e) => {
                warnings.push(format!("校准未载入：{e}"));
                Profile::default()
            }
        };
        let mut settings = Settings::default();
        if data_dir.join("settings.json").exists() {
            match std::fs::read_to_string(data_dir.join("settings.json"))
                .ok()
                .and_then(|s| serde_json::from_str::<Settings>(&s).ok())
                .filter(|s| s.validate().is_ok())
            {
                Some(s) => settings = s,
                None => warnings.push("设置文件无效，使用默认显示设置".into()),
            }
        } else {
            if let Ok(s) = std::fs::read_to_string(legacy.join("touchpad_mapping.json")) {
                if let Ok(m) = serde_json::from_str(&s) {
                    settings.pad = m;
                }
            }
            if let Ok(s) = std::fs::read_to_string(legacy.join("joystick_mapping.json")) {
                if let Ok(m) = serde_json::from_str(&s) {
                    settings.joystick = m;
                }
            }
            if let Ok(s) = std::fs::read_to_string(legacy.join("effects.json")) {
                if let Ok(v) = serde_json::from_str::<Value>(&s) {
                    let mode = v["mode"].as_u64().unwrap_or(1);
                    let dir = v["direction"].as_u64().unwrap_or(0);
                    if [0, 1, 2, 3, 4, 6].contains(&mode) && dir < 2 {
                        settings.effect = mode as u8;
                        settings.direction = dir as u8;
                    }
                }
            }
        }
        let mut model = Model::new(profile, settings);
        model.view.settings_path = data_dir.display().to_string();
        for w in warnings {
            model.log("warn", w, 0.);
        }
        if profile_path.starts_with(&legacy) && model.view.profile.complete() {
            model.log("ok", "已沿用旧版 32 键校准及方向配置；原文件保留", 0.);
        }
        let audio = Audio::new();
        let shared = Arc::new(Mutex::new((model.view.clone(), vec![vec![]; 32])));
        let (tx, rx) = unbounded();
        let state = shared.clone();
        let sound = audio.clone();
        let dir = data_dir.clone();
        std::thread::Builder::new()
            .name("tang-serial".into())
            .spawn(move || {
                Worker {
                    model,
                    parser: Parser::default(),
                    link: Link::default(),
                    port: None,
                    replay: None,
                    recording: None,
                    audio: sound,
                    dir,
                    shared: state,
                    origin: Instant::now(),
                    drain_until: 0.,
                    connected_at: 0.,
                    autosynced: false,
                    queried: false,
                    page: "overview".into(),
                    publish_at: 0.,
                }
                .run(rx)
            })
            .expect("serial thread");
        Self {
            tx,
            shared,
            audio,
            data_dir,
        }
    }
    pub fn action(&self, action: Action) -> Result<String, String> {
        let (tx, rx) = bounded(1);
        self.tx
            .send(Request { action, reply: tx })
            .map_err(|_| "通信线程已结束")?;
        rx.recv_timeout(Duration::from_secs(4))
            .map_err(|_| "操作等待超时")?
    }
    pub fn snapshot(&self, selected: usize) -> Snapshot {
        let (v, h) = &*self.shared.lock().unwrap();
        let mut view = v.clone();
        view.audio = self.audio.view.lock().unwrap().clone();
        Snapshot {
            view,
            chart: h.get(selected).cloned().unwrap_or_default(),
        }
    }
}
struct Replay {
    file: File,
    total: u64,
    read: u64,
    next: f64,
}
struct Worker {
    model: Model,
    parser: Parser,
    link: Link,
    port: Option<Box<dyn serialport::SerialPort>>,
    replay: Option<Replay>,
    recording: Option<File>,
    audio: Arc<Audio>,
    dir: PathBuf,
    shared: Arc<Mutex<(View, Vec<Vec<[f64; 2]>>)>>,
    origin: Instant,
    drain_until: f64,
    connected_at: f64,
    autosynced: bool,
    queried: bool,
    page: String,
    publish_at: f64,
}
impl Worker {
    fn run(mut self, rx: Receiver<Request>) {
        loop {
            for request in rx.try_iter() {
                let now = self.origin.elapsed().as_secs_f64();
                let result = self.action(request.action, now);
                if let Err(e) = &result {
                    self.model.log("warn", e, now);
                }
                self.model.view.transfer = self.link.view.clone();
                self.model.tick(self.origin.elapsed().as_secs_f64());
                self.publish();
                let _ = request.reply.send(result);
            }
            let now = self.origin.elapsed().as_secs_f64();
            if self.port.is_some() {
                let mut buffer = [0u8; 4096];
                let port = self.port.as_mut().unwrap();
                let result = port
                    .bytes_to_read()
                    .map_err(|e| e.to_string())
                    .and_then(|n| {
                        if n == 0 {
                            Ok(0)
                        } else {
                            port.read(&mut buffer[..(n as usize).min(4096)])
                                .map_err(|e| e.to_string())
                        }
                    });
                match result {
                    Ok(n) if n > 0 => {
                        // Timestamp the completed read, not the start of a loop that may
                        // have waited for UI actions, disk sync or the serial driver.
                        // An artificially early time poisons the minimum-delay clock
                        // anchor and makes all later guitar events appear stale.
                        let received_at = self.origin.elapsed().as_secs_f64();
                        if received_at >= self.drain_until {
                            self.ingest(&buffer[..n], received_at);
                        }
                    }
                    Err(e) => {
                        self.close();
                        self.model.view.connection = "error".into();
                        self.model.view.message = format!("串口连接中断：{e}");
                        self.model.log("error", format!("串口连接中断：{e}"), now);
                    }
                    _ => {}
                }
                if now >= self.drain_until && self.model.view.connection == "connecting" {
                    self.model.view.connection = "live".into();
                    self.model.view.message = "串口已打开，等待有效遥测".into();
                    self.model.log("ok", "串口已就绪 · 115200 / 8N1", now);
                }
            }
            if let Some(replay) = &mut self.replay {
                if now >= replay.next {
                    let mut b = [0u8; 128];
                    match replay.file.read(&mut b) {
                        Ok(0) => {
                            self.replay = None;
                            self.model.view.connection = "replay_done".into();
                            self.model.view.message = "历史回放结束".into();
                            self.model.view.replay_progress = 1.;
                        }
                        Ok(n) => {
                            replay.read += n as u64;
                            replay.next = now + n as f64 / 11520.;
                            self.model.view.replay_progress =
                                replay.read as f64 / replay.total.max(1) as f64;
                            self.ingest(&b[..n], now);
                        }
                        Err(e) => {
                            self.replay = None;
                            self.model.view.connection = "error".into();
                            self.model.view.message = e.to_string();
                        }
                    }
                }
            }
            let now = self.origin.elapsed().as_secs_f64();
            if self.port.is_some() && now >= self.drain_until {
                let v = &self.model.view;
                if !self.autosynced
                    && v.board.is_some()
                    && now - self.connected_at > 2.35
                    && !self.link.view.busy
                {
                    self.autosynced = true;
                    if v.board
                        .as_ref()
                        .is_some_and(|b| b.mode == 5 && b.configured)
                    {
                        self.model
                            .log("info", "保留 FPGA 当前游戏和校准，不重新配置", now);
                    } else if self.model.view.profile.complete() {
                        if let Err(e) = self.sync() {
                            self.model.log("warn", e, now);
                        }
                    }
                } else if !self.queried
                    && !self.link.view.busy
                    && v.protocol == "keyboard"
                    && v.board.is_none()
                    && now - self.connected_at > 2.5
                {
                    self.queried = true;
                    let _ = self.link.start(vec![Command::new(0x30)], "查询板卡");
                }
                if let Some(packet) = self.link.tick(now) {
                    if let Some(port) = &mut self.port {
                        match port.write_all(&packet) {
                            Ok(()) => self.model.view.tx_bytes += packet.len() as u64,
                            Err(e) => self.link.fail(format!("串口发送失败：{e}")),
                        }
                    }
                }
            }
            self.model.view.transfer = self.link.view.clone();
            self.model.tick(now);
            if !self.model.view.pads.iter().any(|p| p.fresh) || self.model.view.connection != "live"
            {
                self.audio.configure(false, self.model.view.settings.volume);
            } else {
                self.audio.configure(
                    self.page == "guitar" && self.model.view.settings.guitar_enabled,
                    self.model.view.settings.volume,
                );
            }
            if now - self.publish_at >= 0.025 {
                self.publish();
                self.publish_at = now;
            }
            std::thread::sleep(Duration::from_millis(2));
        }
    }
    fn publish(&self) {
        let h = self
            .model
            .histories
            .iter()
            .map(|v| v.iter().copied().collect())
            .collect();
        *self.shared.lock().unwrap() = (self.model.view.clone(), h);
    }
    fn ingest(&mut self, data: &[u8], now: f64) {
        self.model.view.rx_bytes += data.len() as u64;
        if let Some(file) = &mut self.recording {
            if let Err(e) = file.write_all(data) {
                self.recording = None;
                self.model.view.recording = None;
                self.model.log("error", format!("录制停止：{e}"), now);
            }
        }
        let frames = self.parser.feed(data);
        if !frames.is_empty() && self.model.view.protocol == "unsupported" {
            self.model.view.protocol = "unknown".into();
            self.model.view.message = "已识别到硬件调试数据".into();
        }
        for frame in frames {
            if let Frame::Board(b) = &frame {
                let done = self.link.view.completed;
                let failures = self.link.view.failures;
                self.link.ack(b);
                if self.link.view.completed > done && !self.link.view.busy {
                    self.model.log("ok", self.link.view.message.clone(), now);
                }
                if self.link.view.failures > failures {
                    self.model.log("error", self.link.view.message.clone(), now);
                }
            }
            let notes = self.model.frame(frame, now);
            if self.model.view.connection == "live"
                && self.page == "guitar"
                && self.model.view.settings.guitar_enabled
            {
                for (string, delay) in notes {
                    if self.audio.pluck(string, delay) {
                        self.model.view.guitar.counts[string] += 1;
                        self.model.view.guitar.last_hits[string] = now;
                    }
                }
            }
        }
        self.model.view.errors = self.parser.errors;
        self.model.view.discarded = self.parser.discarded;
        if self.model.view.protocol == "unknown"
            && self.model.view.rx_bytes > 1024
            && self.model.view.counts.iter().sum::<u64>() == 0
        {
            self.model.view.protocol = "unsupported".into();
            self.model.view.message =
                "串口有数据，但不是受支持的硬件调试协议；请核对板上固件。当前禁止下发命令。".into();
            self.model.log("warn", self.model.view.message.clone(), now);
        }
    }
    fn close(&mut self) {
        self.port = None;
        self.replay = None;
        if let Some(mut f) = self.recording.take() {
            let _ = f.flush();
        }
        self.model.view.recording = None;
        self.link = Link::default();
        self.audio.configure(false, self.model.view.settings.volume);
        self.audio.panic();
        if let Some(c) = &mut self.model.calibration {
            c.abort("连接已改变，候选校准取消；原配置保留");
        }
        self.model.view.connection = "disconnected".into();
    }
    fn gate(&self) -> Result<(), String> {
        if self.port.is_none() || self.model.view.connection != "live" {
            return Err("请先连接实时板卡；回放不能下发命令".into());
        }
        if self.model.view.board.is_none()
            || self.origin.elapsed().as_secs_f64() - self.model.view.board_updated > 0.6
        {
            return Err("等待有效板卡应答".into());
        }
        if self.link.view.busy {
            return Err("正在等待上一项指令确认".into());
        }
        Ok(())
    }
    fn not_game(&self) -> Result<(), String> {
        if self.model.view.board.as_ref().is_some_and(|b| b.mode == 5) {
            Err("请先结束游戏".into())
        } else {
            Ok(())
        }
    }
    fn sync(&mut self) -> Result<(), String> {
        self.gate()?;
        self.not_game()?;
        let mut cmds = self.model.view.profile.commands()?;
        let s = &self.model.view.settings;
        let mode = if s.effect == 6 && self.model.view.protocol != "hub" {
            0
        } else {
            s.effect
        };
        cmds.push(Command {
            code: 0x20,
            mode,
            direction: s.direction,
            ..Command::default()
        });
        self.link.start(cmds, "校准、阈值与灯效")
    }
    fn persist_profile(&self, p: &Profile) -> Result<(), String> {
        p.validate()?;
        atomic_json(&self.dir.join("calibration.json"), p)
    }
    fn action(&mut self, action: Action, now: f64) -> Result<String, String> {
        match action {
            Action::Connect { port } => {
                if port.is_empty() || port.len() > 100 {
                    return Err("串口名称无效".into());
                }
                self.close();
                self.model.reset();
                self.parser = Parser::default();
                let mut p = serialport::new(&port, 115200)
                    .data_bits(serialport::DataBits::Eight)
                    .parity(serialport::Parity::None)
                    .stop_bits(serialport::StopBits::One)
                    .flow_control(serialport::FlowControl::None)
                    .dtr_on_open(false)
                    .timeout(Duration::from_millis(10))
                    .open()
                    .map_err(|e| format!("无法打开 {port}：{e}。请关闭占用端口的旧版 App。"))?;
                p.write_data_terminal_ready(false)
                    .and_then(|_| p.write_request_to_send(false))
                    .map_err(|e| format!("无法设置串口控制线：{e}"))?;
                p.clear(serialport::ClearBuffer::All)
                    .map_err(|e| e.to_string())?;
                self.port = Some(p);
                self.drain_until = now + 2.;
                self.connected_at = now;
                self.autosynced = false;
                self.queried = false;
                self.model.view.port = port.clone();
                self.model.view.connection = "connecting".into();
                self.model.view.message = "正在排空桥接缓存（2 秒）".into();
                self.model.log("info", format!("连接 {port}"), now);
            }
            Action::Disconnect => {
                self.close();
                self.model.view.message = "已断开；板上逻辑继续运行".into();
                self.model.log("info", "已释放串口", now);
            }
            Action::Sync => {
                if self.model.calibration.is_some() {
                    return Err("请先完成或取消正在进行的校准".into());
                }
                self.sync()?;
            }
            Action::Effect { mode, direction } => {
                self.gate()?;
                self.not_game()?;
                if ![0, 1, 2, 3, 4, 6].contains(&mode) || direction > 1 {
                    return Err("灯效参数无效".into());
                }
                if mode == 6 && self.model.view.protocol != "hub" {
                    return Err("连续彩色流水需要综合固件".into());
                }
                let mut settings = self.model.view.settings.clone();
                settings.effect = mode;
                settings.direction = direction;
                atomic_json(&self.dir.join("settings.json"), &settings)?;
                self.model.view.settings = settings;
                self.link.start(
                    vec![Command {
                        code: 0x20,
                        mode,
                        direction,
                        ..Command::default()
                    }],
                    "切换灯效",
                )?;
            }
            Action::GameStart { game } => {
                self.gate()?;
                if !(1..=3).contains(&game)
                    || self.model.view.game.is_none()
                    || now - self.model.view.game_updated > 0.6
                {
                    return Err("等待支持小游戏的固件状态".into());
                }
                if !self.model.view.board.as_ref().is_some_and(|b| b.configured)
                    || self.model.calibration.is_some()
                {
                    return Err("请先完成校准并下发".into());
                }
                self.link.start(
                    vec![Command {
                        code: 0x41,
                        key: game,
                        ..Command::default()
                    }],
                    "开始游戏",
                )?;
            }
            Action::GameStop => {
                self.gate()?;
                let s = &self.model.view.settings;
                self.link.start(
                    vec![Command {
                        code: 0x42,
                        mode: s.effect,
                        direction: s.direction,
                        ..Command::default()
                    }],
                    "结束游戏",
                )?;
            }
            Action::ZeroEncoders => {
                for e in &mut self.model.view.encoders {
                    e.edges = 0;
                }
                self.model
                    .log("info", "编码器显示位置归零（保留板上计数）", now);
            }
            Action::CalibrationStart { targets } => {
                self.gate()?;
                self.not_game()?;
                if targets
                    .iter()
                    .any(|i| *i >= 32 || !self.model.view.keys[*i].fresh)
                {
                    return Err("校准范围存在未更新按键".into());
                }
                self.model.calibration = Some(Calibration::new(targets, now)?);
            }
            Action::CalibrationPress => {
                self.gate()?;
                self.model
                    .calibration
                    .as_mut()
                    .ok_or("请先采集松开位置")?
                    .press(now)?;
            }
            Action::CalibrationApply => {
                self.gate()?;
                self.not_game()?;
                let profile = self
                    .model
                    .calibration
                    .as_ref()
                    .ok_or("没有候选校准")?
                    .apply(&self.model.view.profile)?;
                self.persist_profile(&profile)?;
                self.model.view.profile = profile;
                self.model.calibration = None;
                self.sync()?;
            }
            Action::CalibrationCancel => {
                self.model.calibration = None;
            }
            Action::Thresholds { press, release } => {
                self.gate()?;
                self.not_game()?;
                if self.model.calibration.is_some() {
                    return Err("请先完成或取消校准".into());
                }
                let mut p = self.model.view.profile.clone();
                p.press_threshold = press;
                p.release_threshold = release;
                p.commands()?;
                self.persist_profile(&p)?;
                self.model.view.profile = p;
                self.sync()?;
            }
            Action::Settings { settings } => {
                settings.validate()?;
                atomic_json(&self.dir.join("settings.json"), &settings)?;
                self.audio.panic();
                self.model.view.settings = settings;
            }
            Action::Page { page } => {
                self.page = page;
                if self.page != "guitar" {
                    self.audio.configure(false, self.model.view.settings.volume);
                    self.audio.panic();
                }
            }
            Action::Panic => self.audio.panic(),
            Action::Record => {
                if let Some(mut f) = self.recording.take() {
                    f.flush().map_err(|e| e.to_string())?;
                    let path = self.model.view.recording.take().unwrap_or_default();
                    self.model.log("ok", format!("录制已保存：{path}"), now);
                } else {
                    if self.model.view.connection != "live" {
                        return Err("仅实时连接可以录制".into());
                    }
                    let folder = self.dir.join("recordings");
                    std::fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
                    let t = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap()
                        .as_millis();
                    let path = folder.join(format!("hardware-{t}.bin"));
                    self.recording = Some(File::create(&path).map_err(|e| e.to_string())?);
                    self.model.view.recording = Some(path.display().to_string());
                    self.model.log(
                        "info",
                        format!("开始录制全部原始帧：{}", path.display()),
                        now,
                    );
                }
            }
            Action::Replay { path } => {
                let file = File::open(&path).map_err(|e| e.to_string())?;
                let total = file.metadata().map_err(|e| e.to_string())?.len();
                self.close();
                self.model.reset();
                self.parser = Parser::default();
                self.model.view.connection = "replay".into();
                self.model.view.port = path.clone();
                self.model.view.message = "历史回放 · 不发送命令、不发声".into();
                self.replay = Some(Replay {
                    file,
                    total,
                    read: 0,
                    next: now,
                });
                self.model.log("info", format!("回放：{path}"), now);
            }
            Action::Import { path } => {
                if self.link.view.busy || self.model.calibration.is_some() {
                    return Err("请等待传输完成或取消候选校准".into());
                }
                self.not_game()?;
                let p = Profile::load(&PathBuf::from(path))?;
                self.persist_profile(&p)?;
                self.model.view.profile = p;
                if self.model.view.connection == "live" && self.model.view.profile.complete() {
                    self.sync()?;
                }
                self.model.log("ok", "校准配置已导入", now);
            }
        }
        Ok("操作已接受".into())
    }
}
pub fn ports() -> Result<Value, String> {
    let values = serialport::available_ports()
        .map_err(|e| e.to_string())?
        .into_iter()
        .map(|p| {
            let (description, recommended) = match p.port_type {
                serialport::SerialPortType::UsbPort(u) => (
                    format!(
                        "{} · {:04X}:{:04X} {}",
                        u.product.unwrap_or("USB Serial".into()),
                        u.vid,
                        u.pid,
                        u.serial_number.unwrap_or_default()
                    ),
                    u.vid == 0x0403 && u.pid == 0x6010,
                ),
                _ => ("Serial port".into(), false),
            };
            json!({"name":p.port_name,"description":description,"recommended":recommended})
        })
        .collect::<Vec<_>>();
    Ok(json!(values))
}
