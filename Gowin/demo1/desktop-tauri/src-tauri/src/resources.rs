//! Bounded resource readers. CRCs, canonical filenames and SHA-256 are verified before use.
use crate::{Result, model};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, File},
    io::Read,
    path::{Path, PathBuf},
};
pub const MAX_BANK: usize = 32 + 512 * 2048;
pub fn read(path: &Path, max: usize) -> Result<Vec<u8>> {
    let file = File::open(path).map_err(|e| format!("{}：{e}", path.display()))?;
    if file.metadata().map_err(|e| e.to_string())?.len() > max as u64 {
        return Err("文件超过大小限制".into());
    }
    let mut b = Vec::new();
    file.take(max as u64 + 1)
        .read_to_end(&mut b)
        .map_err(|e| e.to_string())?;
    if b.len() > max {
        return Err("文件超过大小限制".into());
    }
    Ok(b)
}
pub fn read_json(path: &Path, max: usize) -> Result<Value> {
    let b = read(path, max)?;
    let b = b.strip_prefix(&[239, 187, 191]).unwrap_or(&b);
    serde_json::from_slice(b).map_err(|e| format!("JSON 编码错误：{e}"))
}
fn asset(path: &Path, max: usize) -> Result<Vec<u8>> {
    if fs::symlink_metadata(path)
        .map_err(|e| e.to_string())?
        .file_type()
        .is_symlink()
    {
        return Err("资源不允许使用符号链接".into());
    }
    read(path, max)
}
fn sha(b: &[u8]) -> String {
    format!("{:x}", Sha256::digest(b))
}
fn u16le(b: &[u8], i: usize) -> u16 {
    u16::from_le_bytes([b[i], b[i + 1]])
}
fn u32le(b: &[u8], i: usize) -> u32 {
    u32::from_le_bytes(b[i..i + 4].try_into().unwrap())
}
fn title(v: &Value, f: &str, max: usize) -> Result<String> {
    let s = model::text(v, f)?;
    if !(1..=max).contains(&s.chars().count()) || s.chars().any(|c| c < ' ') {
        return Err(format!("{f} 文本长度或字符无效"));
    }
    Ok(s.into())
}
#[derive(Clone)]
pub struct Resource {
    pub id: u32,
    pub revision: u32,
    pub title: String,
    pub frames: Vec<Vec<i16>>,
    pub crcs: Vec<u32>,
    pub digest: String,
    pub payload_crc: u32,
}
impl Resource {
    pub fn decode(id: u32, revision: u32, title: String, b: &[u8]) -> Result<Self> {
        if id == 0
            || revision == 0
            || !(1..=80).contains(&title.chars().count())
            || title.chars().any(|c| c < ' ')
        {
            return Err("资源编号、版本或名称无效".into());
        }
        if !(32..=MAX_BANK).contains(&b.len())
            || &b[..4] != b"TSWT"
            || u16le(b, 4) != 1
            || u16le(b, 6) != 32
            || u32le(b, 8) != 1024
            || u32le(b, 16) != 1
        {
            return Err("TSWT 头格式无效".into());
        }
        let count = u32le(b, 12) as usize;
        if !(1..=512).contains(&count)
            || u32le(b, 20) as usize != count * 1024
            || u32le(b, 24) as usize != count * 2048
            || b.len() != 32 + count * 2048
            || u32le(b, 28) != crc32fast::hash(&b[32..])
        {
            return Err("TSWT 长度或 CRC 错误".into());
        }
        let frames = b[32..]
            .as_chunks::<2048>()
            .0
            .iter()
            .map(|f| {
                f.as_chunks::<2>()
                    .0
                    .iter()
                    .map(|s| i16::from_le_bytes([s[0], s[1]]))
                    .collect()
            })
            .collect();
        Ok(Self {
            id,
            revision,
            title,
            frames,
            crcs: b[32..]
                .as_chunks::<2048>()
                .0
                .iter()
                .map(|f| crc32fast::hash(f))
                .collect(),
            digest: sha(b),
            payload_crc: u32le(b, 28),
        })
    }
    pub fn from_frames(title: String, frames: Vec<Vec<i16>>) -> Result<Self> {
        Self::decode(1, 1, title, &encode_bank(&frames)?)
    }
    pub fn pair(&self, percent: f64) -> Result<(Vec<Vec<i16>>, Value)> {
        if !percent.is_finite() || !(0.0..=100.0).contains(&percent) {
            return Err("波表位置应为 0–100%".into());
        }
        let coordinate =
            (percent * (self.frames.len() - 1) as f64 * 65536.0 / 100.0).round_ties_even() as usize;
        let first = coordinate >> 16;
        let second = (first + 1).min(self.frames.len() - 1);
        let fraction = coordinate & 65535;
        Ok((
            vec![self.frames[first].clone(), self.frames[second].clone()],
            json!({"resource_id":self.id,"revision":self.revision,"frame_count":self.frames.len(),"first":first,"second":second,"fraction":fraction,"payload_base":0,"first_address":first*2048,"second_address":second*2048,"first_crc":self.crcs[first],"second_crc":self.crcs[second],"frame_bytes":2048}),
        ))
    }
}
pub fn encode_bank(frames: &[Vec<i16>]) -> Result<Vec<u8>> {
    if !(1..=512).contains(&frames.len()) || frames.iter().any(|f| f.len() != 1024) {
        return Err("波表帧数或长度无效".into());
    }
    let payload: Vec<u8> = frames
        .iter()
        .flatten()
        .flat_map(|s| s.to_le_bytes())
        .collect();
    let mut b = b"TSWT\x01\x00\x20\x00".to_vec();
    for n in [
        1024,
        frames.len() as u32,
        1,
        (frames.len() * 1024) as u32,
        payload.len() as u32,
        crc32fast::hash(&payload),
    ] {
        b.extend(n.to_le_bytes());
    }
    b.extend(payload);
    Ok(b)
}
pub fn load_library(path: &Path) -> Result<Vec<Resource>> {
    let folder = if path.is_dir() {
        path
    } else {
        path.parent().ok_or("缺少资源目录")?
    };
    let b = read(&folder.join("TSINDEX.BIN"), 32 + 32 * (64 + 512 * 4))?;
    if b.len() < 32
        || &b[..4] != b"TSLB"
        || u16le(&b, 4) != 1
        || u16le(&b, 6) != 32
        || u32le(&b, 8) != 64
        || u32le(&b, 24) != 0
    {
        return Err("资源目录头无效".into());
    }
    let count = u32le(&b, 12) as usize;
    if !(1..=32).contains(&count)
        || b.len() != 32 + u32le(&b, 16) as usize
        || b.len() < 32 + count * 64
        || crc32fast::hash(&b[..28]) != u32le(&b, 28)
        || crc32fast::hash(&b[32..]) != u32le(&b, 20)
    {
        return Err("资源目录边界或 CRC 错误".into());
    }
    let manifest = read_json(&folder.join("TSLIB.JSN"), 1024 * 1024)?;
    if manifest["version"].as_u64() != Some(1)
        || manifest["resources"].as_array().map(Vec::len) != Some(count)
    {
        return Err("资源库元数据版本或数量不匹配".into());
    }
    let mut cursor = 32 + count * 64;
    let mut used = BTreeSet::new();
    let mut out = Vec::new();
    for (i, row) in manifest["resources"].as_array().unwrap().iter().enumerate() {
        let e = &b[32 + i * 64..32 + (i + 1) * 64];
        let id = u32le(e, 0);
        let rev = u32le(e, 4);
        let frames = u32le(e, 8) as usize;
        let mut check = e[..36].to_vec();
        check.extend_from_slice(&e[40..]);
        let filename = format!("{id:08X}.BIN");
        if id == 0
            || rev == 0
            || !used.insert(id)
            || !(1..=512).contains(&frames)
            || u32le(e, 16) as usize != 32 + frames * 2048
            || u32le(e, 20) as usize != cursor
            || cursor + frames * 4 > b.len()
            || e[35] != 0
            || e[40..].iter().any(|v| *v != 0)
            || crc32fast::hash(&check) != u32le(e, 36)
            || e[24..35] != *filename.replace('.', "").as_bytes()
        {
            return Err("资源描述符 CRC、名称或边界错误".into());
        }
        if row["resource_id"].as_u64() != Some(id as u64)
            || row["revision"].as_u64() != Some(rev as u64)
            || row["filename"] != filename
        {
            return Err("资源元数据与目录不匹配".into());
        }
        let raw = asset(&folder.join(filename), MAX_BANK)?;
        let resource = Resource::decode(id, rev, title(row, "title", 80)?, &raw)?;
        let crcs: Vec<u32> = (0..frames).map(|j| u32le(&b, cursor + j * 4)).collect();
        if raw.len() != u32le(e, 16) as usize
            || resource.frames.len() != frames
            || resource.payload_crc != u32le(e, 12)
            || resource.crcs != crcs
            || row["sha256"] != resource.digest
        {
            return Err("资源 SHA-256 或逐帧 CRC 不匹配".into());
        }
        cursor += frames * 4;
        out.push(resource);
    }
    if cursor != b.len() {
        return Err("资源目录含额外数据".into());
    }
    Ok(out)
}
fn wav_chunks(b: &[u8], allow_surplus: bool) -> Result<BTreeMap<Vec<u8>, &[u8]>> {
    if b.len() < 12 || &b[..4] != b"RIFF" || &b[8..12] != b"WAVE" {
        return Err("不是 RIFF WAVE 文件".into());
    }
    let declared = u32le(b, 4) as u64 + 8;
    if declared != b.len() as u64 && !(allow_surplus && declared == b.len() as u64 + 2) {
        return Err("WAV 总长度不匹配".into());
    }
    let mut chunks = BTreeMap::new();
    let mut pos = 12;
    while pos < b.len() {
        if pos + 8 > b.len() {
            return Err("WAV chunk 头被截断".into());
        }
        let tag = b[pos..pos + 4].to_vec();
        let size = u32le(b, pos + 4) as usize;
        pos += 8;
        if size > b.len() - pos || chunks.insert(tag, &b[pos..pos + size]).is_some() {
            return Err("WAV chunk 越界或重复".into());
        }
        pos += size + (size & 1);
        if pos > b.len() {
            return Err("WAV 缺少对齐字节".into());
        }
    }
    Ok(chunks)
}
pub fn resample(frame: &[f64]) -> Vec<i16> {
    (0..1024)
        .map(|i| {
            let pos = i as f64 * frame.len() as f64 / 1024.0;
            let idx = pos as usize;
            let frac = pos - idx as f64;
            ((frame[idx] * (1.0 - frac) + frame[(idx + 1) % frame.len()] * frac) * 32768.0)
                .round_ties_even()
                .clamp(-32768.0, 32767.0) as i16
        })
        .collect()
}
pub fn load_surge(path: &Path) -> Result<Vec<Vec<i16>>> {
    let b = read(path, 8 * 1024 * 1024 + 4096)?;
    let (size, width, scale, payload) = if path
        .extension()
        .and_then(|e| e.to_str())
        .is_some_and(|s| s.eq_ignore_ascii_case("wav"))
    {
        let chunks = wav_chunks(&b, true)?;
        let meta = chunks
            .get(b"srge".as_slice())
            .ok_or("需要 Surge 单周期波表元数据 srge")?;
        let fmt = chunks.get(b"fmt ".as_slice()).ok_or("WAV 缺少格式参数")?;
        let data = *chunks.get(b"data".as_slice()).ok_or("WAV 缺少样本")?;
        if chunks.contains_key(b"srgo".as_slice())
            || meta.len() != 8
            || u32le(meta, 0) != 1
            || fmt.len() < 16
            || u16le(fmt, 2) != 1
        {
            return Err("WAV 不是受支持的单周期波表".into());
        }
        let (enc, bits) = (u16le(fmt, 0), u16le(fmt, 14));
        if ![(1, 16), (3, 32)].contains(&(enc, bits)) {
            return Err("WAV 需要 PCM16 或 float32".into());
        }
        (u32le(meta, 4) as usize, bits as usize / 8, 32768.0, data)
    } else {
        if b.len() < 12 || &b[..4] != b"vawt" {
            return Err("Surge 波表头无效".into());
        }
        let size = u32le(&b, 4) as usize;
        let count = u16le(&b, 8) as usize;
        let flags = u16le(&b, 10);
        if flags & !15 != 0 || flags & 3 != 0 || (flags & 8 != 0 && flags & 4 == 0) {
            return Err("这里只支持单周期波表，不支持采样模式".into());
        }
        let width = if flags & 4 != 0 { 2 } else { 4 };
        if !(1..=512).contains(&count) || size > 4096 || b.len() != 12 + size * count * width {
            return Err("Surge 波表长度不匹配".into());
        }
        (
            size,
            width,
            if flags & 8 != 0 { 32768.0 } else { 16384.0 },
            &b[12..],
        )
    };
    if !(16..=4096).contains(&size)
        || !size.is_power_of_two()
        || payload.is_empty()
        || payload.len() % (size * width) != 0
        || payload.len() / (size * width) > 512
    {
        return Err("Surge 波表帧长或帧数无效".into());
    }
    let mut out = Vec::new();
    for raw in payload.chunks_exact(size * width) {
        let frame: Vec<f64> = raw
            .chunks_exact(width)
            .map(|s| {
                if width == 2 {
                    i16::from_le_bytes([s[0], s[1]]) as f64 / scale
                } else {
                    f32::from_le_bytes(s.try_into().unwrap()) as f64
                }
            })
            .collect();
        if frame
            .iter()
            .any(|v| !v.is_finite() || !(-1.0..=1.0).contains(v))
        {
            return Err("波表含有非有限值或超过满幅的数据".into());
        }
        out.push(resample(&frame));
    }
    Ok(out)
}
pub fn samples(v: &Value, min: usize, max: usize) -> Result<Vec<i16>> {
    let values = v
        .as_array()
        .filter(|a| (min..=max).contains(&a.len()))
        .ok_or("采样点数量无效")?;
    values
        .iter()
        .map(|v| {
            v.as_i64()
                .filter(|n| (-32768..=32767).contains(n))
                .map(|n| n as i16)
                .ok_or("采样点必须是 16 位有符号整数".into())
        })
        .collect()
}
pub fn load_file(path: &Path) -> Result<Vec<Resource>> {
    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();
    if path.is_dir()
        || ext == "jsn"
        || path
            .file_name()
            .is_some_and(|n| n.eq_ignore_ascii_case("TSINDEX.BIN"))
    {
        return load_library(path);
    }
    let name = path
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or("文件名编码无效")?
        .chars()
        .take(80)
        .collect();
    let resource = if ext == "tswt" || ext == "bin" {
        Resource::decode(1, 1, name, &read(path, MAX_BANK)?)?
    } else {
        let frames = match ext.as_str() {
            "wt" | "wav" => load_surge(path)?,
            "json" => {
                let v = read_json(path, 1024 * 1024)?;
                vec![samples(v.get("samples").unwrap_or(&v), 1024, 1024)?]
            }
            "csv" | "txt" => {
                let b = read(path, 1024 * 1024)?;
                let s = std::str::from_utf8(&b)
                    .map_err(|e| e.to_string())?
                    .trim_start_matches('\u{feff}')
                    .replace(',', " ");
                let a: std::result::Result<Vec<i16>, _> =
                    s.split_whitespace().map(str::parse).collect();
                let a = a.map_err(|_| "波表需要 16 位整数")?;
                if a.len() != 1024 {
                    return Err("波表需要 1024 个采样点".into());
                }
                vec![a]
            }
            _ => return Err("不支持的波表文件格式".into()),
        };
        Resource::from_frames(name, frames)?
    };
    Ok(vec![resource])
}
pub fn load_pcm(path: &Path) -> Result<([u16; 4], Vec<i16>)> {
    let v = read_json(path, 1024 * 1024)?;
    if v["format"] != "tang-pcm-v1" || v["sample_rate"].as_u64() != Some(24000) {
        return Err("请选择 tang-pcm-v1 格式的 24 kHz 采样 JSON".into());
    }
    let data = samples(&v["samples"], 512, 16384)?;
    let start = model::integer(&v, "loop_start", 0, data.len() as u64)? as u16;
    let end = model::integer(&v, "loop_end", 0, data.len() as u64)? as u16;
    let root = model::integer(&v, "root_note", 0, 127)? as u16;
    if start >= end || end - start < 512 {
        return Err("循环长度至少 512 点".into());
    }
    Ok(([data.len() as u16, start, end, root], data))
}
pub fn piano_table() -> Vec<i16> {
    let values: Vec<f64> = (0..1024)
        .map(|i| {
            [
                (1.0, 1.0),
                (2.0, 0.32),
                (3.0, 0.18),
                (4.0, 0.09),
                (5.0, 0.045),
                (6.0, 0.02),
            ]
            .iter()
            .map(|(h, a)| a * (2.0 * std::f64::consts::PI * h * i as f64 / 1024.0).sin())
            .sum()
        })
        .collect();
    let peak = values.iter().map(|v| v.abs()).fold(0.0, f64::max);
    values
        .iter()
        .map(|v| (30000.0 * v / peak).round_ties_even() as i16)
        .collect()
}
#[derive(Clone)]
pub struct Timbre {
    pub id: u64,
    pub title: String,
    pub category: String,
    pub description: String,
    pub profile: Value,
    pub resource_id: Value,
    pub samples: Option<Vec<i16>>,
    pub preview: PathBuf,
}
fn requirements(p: &Value, resource: bool) -> Value {
    let mut f = BTreeSet::from([
        "voice_allocator",
        "pitch_phase",
        "amplitude_adsr",
        "velocity_gain",
        "per_key_profile",
        "uart_profile_confirmation",
    ]);
    let mode = model::mode(&p["mode"]).unwrap();
    if (1..=3).contains(&mode) {
        f.extend([
            "second_oscillator",
            "modulation_adsr",
            ["", "fm_pm", "am", "ring_modulation"][mode as usize],
        ]);
    } else if p["gain_b"].as_f64().unwrap() > 0.0 {
        f.extend(["second_oscillator", "oscillator_mix"]);
    }
    if resource {
        f.extend([
            "periodic_wavetable",
            "linear_interpolation",
            "double_bank_commit",
            "uart_resource_upload",
        ]);
    }
    if p["wave_a"] != model::CUSTOM || p["wave_b"] != model::CUSTOM {
        f.insert("basic_waveform");
    }
    json!(f)
}
pub fn load_bank(folder: &Path) -> Result<Vec<Timbre>> {
    let v = read_json(&folder.join("BASICS.JSN"), 1024 * 1024)?;
    let rows = v["timbres"]
        .as_array()
        .filter(|a| (1..=32).contains(&a.len()))
        .ok_or("基础音色库数量无效")?;
    if v["format"] != "tang-basic-bank-v1" || v["version"].as_u64() != Some(1) {
        return Err("基础音色库版本无效".into());
    }
    let resources = load_library(folder)?;
    let mut used = BTreeSet::new();
    let mut out = Vec::new();
    for row in rows {
        let id = model::integer(row, "timbre_id", 1, 65535)?;
        if !used.insert(id) {
            return Err("音色编号重复".into());
        }
        model::validate_profile(&row["profile"])?;
        if row["profile"]["mode"] == "采样钢琴" {
            return Err("基础音色库尚不支持 PCM 资源".into());
        }
        let resource = if row["resource_id"].is_null() {
            None
        } else {
            Some(
                resources
                    .iter()
                    .find(|r| row["resource_id"].as_u64() == Some(r.id as u64))
                    .ok_or("缺少音色波表资源")?,
            )
        };
        if model::custom(&row["profile"]) != resource.is_some()
            || row["requirements"] != requirements(&row["profile"], resource.is_some())
        {
            return Err("音色资源或模块需求不匹配".into());
        }
        if resource.is_some_and(|r| r.frames.len() != 1 || row["resource_sha256"] != r.digest) {
            return Err("音色波表帧数或 SHA-256 不匹配".into());
        }
        let name = model::text(row, "preview_file")?;
        if name.len() != 12
            || !name.starts_with('P')
            || !name.ends_with(".WAV")
            || !name.as_bytes()[1..8]
                .iter()
                .all(|c| c.is_ascii_digit() || (b'A'..=b'F').contains(c))
        {
            return Err("试听文件名无效".into());
        }
        let preview = folder.join(name);
        let raw = asset(&preview, 1024 * 1024)?;
        if row["preview_sha256"] != sha(&raw) {
            return Err("试听文件 SHA-256 不匹配".into());
        }
        let chunks = wav_chunks(&raw, false)?;
        let fmt = chunks.get(b"fmt ".as_slice()).ok_or("试听 WAV 缺少格式")?;
        let data = chunks.get(b"data".as_slice()).ok_or("试听 WAV 缺少样本")?;
        if fmt.len() < 16
            || u16le(fmt, 0) != 1
            || u16le(fmt, 2) != 1
            || u32le(fmt, 4) != 24000
            || u16le(fmt, 14) != 16
            || data.is_empty()
            || data.len() % 2 != 0
        {
            return Err("试听文件需要 24 kHz 单声道 PCM16".into());
        }
        out.push(Timbre {
            id,
            title: title(row, "title", 500)?,
            category: title(row, "category", 500)?,
            description: title(row, "description", 500)?,
            profile: row["profile"].clone(),
            resource_id: row["resource_id"].clone(),
            samples: resource.map(|r| r.frames[0].clone()),
            preview,
        });
    }
    Ok(out)
}
