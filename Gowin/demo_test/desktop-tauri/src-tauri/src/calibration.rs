use crate::protocol::Command;
use serde::{Deserialize, Serialize};
use std::{collections::VecDeque, io::Write, path::Path};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Endpoint {
    pub rest: f64,
    pub bottom: f64,
    pub noise: f64,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Entry {
    pub key: usize,
    pub calibration: Option<Endpoint>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Profile {
    pub format: String,
    pub version: u8,
    pub name: String,
    pub source: String,
    pub press_threshold: f64,
    pub release_threshold: f64,
    pub keys: Vec<Entry>,
}
impl Default for Profile {
    fn default() -> Self {
        Self {
            format: "TangKeyboardCalibration".into(),
            version: 1,
            name: "尚未校准".into(),
            source: String::new(),
            press_threshold: 0.5,
            release_threshold: 0.35,
            keys: (1..=32)
                .map(|key| Entry {
                    key,
                    calibration: None,
                })
                .collect(),
        }
    }
}
impl Profile {
    pub fn validate(&self) -> Result<(), String> {
        if self.format != "TangKeyboardCalibration" || self.version != 1 || self.keys.len() != 32 {
            return Err("不是受支持的 32 键校准文件（v1）".into());
        }
        if !self.press_threshold.is_finite()
            || !self.release_threshold.is_finite()
            || !(0.01..=1.).contains(&self.press_threshold)
            || !(0.0..=0.99).contains(&self.release_threshold)
            || self.release_threshold >= self.press_threshold
        {
            return Err("释放阈值必须小于触发阈值，且在 0–100% 范围内".into());
        }
        if self.name.len() > 800 || self.source.len() > 8000 {
            return Err("配置描述过长".into());
        }
        for (i, e) in self.keys.iter().enumerate() {
            if e.key != i + 1 {
                return Err("键号缺失或顺序错误".into());
            }
            if let Some(c) = &e.calibration {
                if [c.rest, c.bottom, c.noise]
                    .iter()
                    .any(|v| !v.is_finite() || !(0.0..=4095.).contains(v))
                    || (c.bottom - c.rest).abs() < 100.
                {
                    return Err(format!("K{:02} 校准范围无效或行程不足 100", i + 1));
                }
            }
        }
        Ok(())
    }
    pub fn complete(&self) -> bool {
        self.validate().is_ok() && self.keys.iter().all(|k| k.calibration.is_some())
    }
    pub fn commands(&self) -> Result<Vec<Command>, String> {
        self.validate()?;
        let mut result = vec![Command::new(0x10)];
        for (i, e) in self.keys.iter().enumerate() {
            let c = e.calibration.as_ref().ok_or("请完成全部 32 键校准")?;
            // Python's legacy round uses ties-to-even. Preserve its exact integer thresholds.
            let rest = c.rest.round_ties_even() as u16;
            let bottom = c.bottom.round_ties_even() as u16;
            let threshold = |t: f64| {
                (f64::from(rest) + (f64::from(bottom) - f64::from(rest)) * t).round_ties_even()
                    as u16
            };
            let press = threshold(self.press_threshold);
            let release = threshold(self.release_threshold);
            if press == release {
                return Err(format!("K{:02} 整数阈值无法区分", i + 1));
            }
            result.push(Command {
                code: 0x11,
                key: i as u8,
                rest,
                bottom,
                press,
                release,
                ..Command::default()
            });
        }
        result.push(Command::new(0x12));
        Ok(result)
    }
    pub fn depth(&self, index: usize, value: f64) -> Option<f64> {
        self.keys[index]
            .calibration
            .as_ref()
            .map(|c| ((value - c.rest) / (c.bottom - c.rest)).clamp(0., 1.))
    }
    pub fn load(path: &Path) -> Result<Self, String> {
        if std::fs::metadata(path).map_err(|e| e.to_string())?.len() > 1024 * 1024 {
            return Err("配置文件过大".into());
        }
        let text = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
        let p: Self =
            serde_json::from_str(text.trim_start_matches('\u{feff}')).map_err(|e| e.to_string())?;
        p.validate()?;
        Ok(p)
    }
}
pub fn atomic_json(path: &Path, value: &impl Serialize) -> Result<(), String> {
    let parent = path.parent().ok_or("无效路径")?;
    std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let mut temp = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    let data = serde_json::to_vec_pretty(value).map_err(|e| e.to_string())?;
    temp.write_all(&data)
        .and_then(|_| temp.as_file().sync_all())
        .map_err(|e| e.to_string())?;
    temp.persist(path).map_err(|e| e.to_string())?;
    Ok(())
}

#[derive(Clone, Serialize)]
pub struct CalibrationView {
    pub stage: String,
    pub targets: Vec<usize>,
    pub done: Vec<usize>,
    pub progress: f64,
    pub error: String,
}
pub struct Calibration {
    pub view: CalibrationView,
    started: f64,
    last: [f64; 32],
    samples: Vec<Vec<f64>>,
    recent: Vec<VecDeque<f64>>,
    rest: [f64; 32],
    noise: [f64; 32],
    bottom: [Option<f64>; 32],
}
fn median(values: &[f64]) -> f64 {
    let mut v = values.to_vec();
    v.sort_by(f64::total_cmp);
    if v.len() % 2 == 0 {
        (v[v.len() / 2 - 1] + v[v.len() / 2]) / 2.
    } else {
        v[v.len() / 2]
    }
}
impl Calibration {
    pub fn new(targets: Vec<usize>, now: f64) -> Result<Self, String> {
        if targets.is_empty() || targets.iter().any(|i| *i >= 32) {
            return Err("校准范围无效".into());
        }
        Ok(Self {
            view: CalibrationView {
                stage: "rest".into(),
                targets,
                done: vec![],
                progress: 0.,
                error: String::new(),
            },
            started: now,
            last: [now; 32],
            samples: vec![vec![]; 32],
            recent: vec![VecDeque::new(); 32],
            rest: [0.; 32],
            noise: [0.; 32],
            bottom: [None; 32],
        })
    }
    pub fn abort(&mut self, message: &str) {
        self.view.stage = "error".into();
        self.view.error = message.into();
    }
    pub fn feed(&mut self, i: usize, value: u16, now: f64) {
        if !self.view.targets.contains(&i) || !matches!(self.view.stage.as_str(), "rest" | "press")
        {
            return;
        }
        if now - self.last[i] > 0.6 {
            self.abort("数据中断，候选校准已取消；原配置保留");
            return;
        }
        self.last[i] = now;
        if self.view.stage == "rest" {
            self.samples[i].push(f64::from(value));
        } else {
            let w = &mut self.recent[i];
            w.push_back(f64::from(value));
            if w.len() > 7 {
                w.pop_front();
            }
            if w.len() == 7 {
                let end = median(w.make_contiguous());
                let span = (end - self.rest[i]).abs();
                if span >= 100f64.max(self.noise[i] * 8.)
                    && span > (self.bottom[i].unwrap_or(self.rest[i]) - self.rest[i]).abs()
                {
                    self.bottom[i] = Some(end);
                }
            }
            self.view.done = self
                .view
                .targets
                .iter()
                .copied()
                .filter(|i| self.bottom[*i].is_some())
                .collect();
            self.view.progress = self.view.done.len() as f64 / self.view.targets.len() as f64;
        }
    }
    pub fn tick(&mut self, now: f64) {
        if !matches!(self.view.stage.as_str(), "rest" | "press") {
            return;
        }
        if self.view.targets.iter().any(|i| now - self.last[*i] > 0.6) {
            self.abort("校准数据超时；原配置保留");
            return;
        }
        if self.view.stage == "rest" {
            // Integrated telemetry is 10 Hz. Four seconds provides >30 real samples.
            self.view.progress = ((now - self.started) / 4.).clamp(0., 1.);
            if now - self.started >= 4. {
                for i in self.view.targets.clone() {
                    let v = &mut self.samples[i];
                    v.sort_by(f64::total_cmp);
                    if v.len() < 30 {
                        self.abort(&format!("K{:02} 样本不足，请重试", i + 1));
                        return;
                    }
                    let noise = v[((v.len() - 1) as f64 * 0.95) as usize]
                        - v[((v.len() - 1) as f64 * 0.05) as usize];
                    if noise > 60. {
                        self.abort(&format!("K{:02} 零点不稳定，请松开按键后重试", i + 1));
                        return;
                    }
                    self.rest[i] = median(v);
                    self.noise[i] = noise;
                }
                self.view.stage = "ready".into();
            }
        }
    }
    pub fn press(&mut self, now: f64) -> Result<(), String> {
        if self.view.stage != "ready" {
            return Err("请先完成松开位置采集".into());
        }
        self.view.stage = "press".into();
        self.last = [now; 32];
        self.view.progress = 0.;
        Ok(())
    }
    pub fn apply(&self, old: &Profile) -> Result<Profile, String> {
        if self.view.stage != "press" || self.view.done.len() != self.view.targets.len() {
            return Err("尚有按键没有采集到有效终点".into());
        }
        let mut next = old.clone();
        for i in &self.view.targets {
            next.keys[*i].calibration = Some(Endpoint {
                rest: self.rest[*i],
                bottom: self.bottom[*i].unwrap(),
                noise: self.noise[*i],
            });
        }
        next.name = "实时校准 · Tang Hardware Lab".into();
        next.source = "Rust / 115200 / 4s rest + 7-sample median".into();
        next.validate()?;
        Ok(next)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stable_calibration_and_spike_rejection() {
        let mut c = Calibration::new(vec![0], 0.).unwrap();
        for n in 1..=40 {
            c.feed(0, 900, n as f64 / 10.);
            c.tick(n as f64 / 10.);
        }
        assert_eq!(c.view.stage, "ready");
        c.press(4.).unwrap();
        for n in 41..48 {
            c.feed(0, if n == 44 { 100 } else { 900 }, n as f64 / 10.);
        }
        assert!(c.view.done.is_empty());
        for n in 48..56 {
            c.feed(0, 120, n as f64 / 10.);
        }
        assert_eq!(
            c.apply(&Profile::default()).unwrap().keys[0]
                .calibration
                .as_ref()
                .unwrap()
                .bottom,
            120.
        );
    }
    #[test]
    fn interruption_never_commits() {
        let mut c = Calibration::new(vec![0], 0.).unwrap();
        c.feed(0, 900, 0.1);
        c.tick(1.);
        assert_eq!(c.view.stage, "error");
        assert!(c.apply(&Profile::default()).is_err());
    }
    #[test]
    fn invalid_thresholds_and_profiles_rejected() {
        let mut p = Profile::default();
        p.release_threshold = p.press_threshold;
        assert!(p.validate().is_err());
        assert!(Profile::default().commands().is_err());
    }
}
