//! Local, read-only Surge OSC connection and explicitly limited ADSR mapping.
use crate::{Result, model};
use serde_json::{Value, json};
use std::{collections::BTreeMap, net::UdpSocket};
pub type Messages = Vec<(String, Vec<Value>)>;
pub fn osc_string(s: &str) -> Vec<u8> {
    let mut b = s.as_bytes().to_vec();
    b.push(0);
    while !b.len().is_multiple_of(4) {
        b.push(0);
    }
    b
}
pub fn decode(b: &[u8], depth: usize) -> Result<Messages> {
    if b.is_empty() || b.len() > 65507 || depth > 8 {
        return Err("OSC 长度或嵌套深度无效".into());
    }
    if b.starts_with(b"#bundle\0") {
        if b.len() < 16 {
            return Err("OSC bundle 缺少时间标记".into());
        }
        let mut pos = 16;
        let mut out = Vec::new();
        while pos < b.len() {
            if pos + 4 > b.len() {
                return Err("OSC 子包头被截断".into());
            }
            let len = i32::from_be_bytes(b[pos..pos + 4].try_into().unwrap());
            pos += 4;
            if len <= 0 || len as usize > b.len() - pos {
                return Err("OSC 子包越界".into());
            }
            out.extend(decode(&b[pos..pos + len as usize], depth + 1)?);
            pos += len as usize;
            if out.len() > 1024 {
                return Err("OSC bundle 消息过多".into());
            }
        }
        return Ok(out);
    }
    fn string(b: &[u8], pos: &mut usize) -> Result<String> {
        let end = b
            .get(*pos..)
            .and_then(|s| s.iter().position(|c| *c == 0))
            .map(|n| *pos + n)
            .ok_or("OSC 字符串缺少结束符")?;
        let next = (end + 4) & !3;
        if next > b.len() || b[end..next].iter().any(|c| *c != 0) {
            return Err("OSC 字符串填充无效".into());
        }
        let s = std::str::from_utf8(&b[*pos..end])
            .map_err(|_| "OSC UTF-8 编码无效")?
            .to_string();
        *pos = next;
        Ok(s)
    }
    let mut pos = 0;
    let address = string(b, &mut pos)?;
    let tags = string(b, &mut pos)?;
    if !address.starts_with('/')
        || address.chars().count() > 256
        || !tags.starts_with(',')
        || tags.len() > 33
    {
        return Err("OSC 地址或类型标记无效".into());
    }
    let mut values = Vec::new();
    for tag in tags.chars().skip(1) {
        values.push(match tag {
            's' => json!(string(b, &mut pos)?),
            'T' => json!(true),
            'F' => json!(false),
            'i' | 'f' => {
                if pos + 4 > b.len() {
                    return Err("OSC 数值被截断".into());
                }
                let raw = b[pos..pos + 4].try_into().unwrap();
                pos += 4;
                if tag == 'i' {
                    json!(i32::from_be_bytes(raw))
                } else {
                    let v = f32::from_be_bytes(raw);
                    if !v.is_finite() {
                        return Err("OSC 数值不是有限数".into());
                    }
                    json!(v as f64)
                }
            }
            _ => return Err("不支持的 OSC 类型".into()),
        });
    }
    if pos != b.len() {
        return Err("OSC 消息含未声明的尾部".into());
    }
    Ok(vec![(address, values)])
}
fn display(v: &Value) -> String {
    v.as_str()
        .map(str::to_string)
        .unwrap_or_else(|| v.to_string())
}
#[derive(Default)]
pub struct Snapshot {
    pub patch: String,
    pub parameters: BTreeMap<String, Value>,
    pub docs: BTreeMap<String, Value>,
}
impl Snapshot {
    pub fn feed(&mut self, address: &str, values: &[Value]) -> Result<()> {
        if address == "/patch" || address == "/patch/load" {
            self.parameters.clear();
            self.docs.clear();
            self.patch = values.first().map(display).unwrap_or_default();
            return Ok(());
        }
        if address.starts_with("/param/")
            && values
                .first()
                .and_then(Value::as_f64)
                .is_some_and(f64::is_finite)
        {
            if self.parameters.len() >= 4096 && !self.parameters.contains_key(address) {
                return Err("参数数量超过限制".into());
            }
            self.parameters.insert(
                address.into(),
                json!({"value":values[0],"display":values.get(1).map(display).unwrap_or_default()}),
            );
        } else if address.starts_with("/doc/param/")
            && !address.ends_with("/ext")
            && values.len() == 4
        {
            if self.docs.len() >= 4096 && !self.docs.contains_key(&address[4..]) {
                return Err("参数文档数量超过限制".into());
            }
            self.docs.insert(address[4..].into(),json!({"name":display(&values[0]),"type":display(&values[1]),"minimum":display(&values[2]),"maximum":display(&values[3])}));
        }
        Ok(())
    }
    pub fn export(&self) -> Value {
        json!({"format":"tang-surge-snapshot-v1","captured_at":chrono::Utc::now().to_rfc3339(),"patch":self.patch,"parameters":self.parameters,"docs":self.docs})
    }
    pub fn load(v: &Value) -> Result<Self> {
        if v["format"] != "tang-surge-snapshot-v1" {
            return Err("请选择 Surge OSC 快照 JSON".into());
        }
        let mut s = Self {
            patch: v
                .get("patch")
                .map(display)
                .unwrap_or_default()
                .chars()
                .take(1024)
                .collect(),
            ..Self::default()
        };
        for f in ["parameters", "docs"] {
            let items = v[f]
                .as_object()
                .filter(|m| m.len() <= 4096)
                .ok_or("快照字段或数量无效")?;
            for (address, item) in items {
                if !address.starts_with("/param/")
                    || address.chars().count() > 256
                    || !item.is_object()
                {
                    return Err("快照参数地址无效".into());
                }
                if f == "parameters" {
                    if !item["value"].as_f64().is_some_and(f64::is_finite) {
                        return Err("快照参数必须为有限数".into());
                    }
                    s.feed(
                        address,
                        &[
                            item["value"].clone(),
                            json!(
                                item.get("display")
                                    .map(display)
                                    .unwrap_or_default()
                                    .chars()
                                    .take(1024)
                                    .collect::<String>()
                            ),
                        ],
                    )?;
                } else {
                    let a: Vec<_> = ["name", "type", "minimum", "maximum"]
                        .iter()
                        .map(|k| item.get(*k).cloned().unwrap_or(json!("")))
                        .collect();
                    s.feed(&format!("/doc{address}"), &a)?;
                }
            }
        }
        Ok(s)
    }
    pub fn map_envelope(&self, profile: &Value, scene: &str) -> Result<Value> {
        if !["a", "b"].contains(&scene) {
            return Err("请选择场景 A 或 B".into());
        }
        model::validate_profile(profile)?;
        let prefix = format!("/param/{scene}/aeg/");
        let value = |f: &str| -> Result<f64> {
            let a = format!("{prefix}{f}");
            self.parameters
                .get(&a)
                .and_then(|v| v["value"].as_f64())
                .ok_or_else(|| format!("缺少 {a}；请启用 Surge OSC 后重新读取。"))
        };
        let normalized = |f: &str, lo: f64, hi: f64| -> Result<f64> {
            let a = format!("{prefix}{f}");
            let d = self
                .docs
                .get(&a)
                .ok_or_else(|| format!("缺少参数范围文档：{a}"))?;
            if d["type"] != "float"
                || d["minimum"].as_str().and_then(|s| s.parse::<f64>().ok()) != Some(lo)
                || d["maximum"].as_str().and_then(|s| s.parse::<f64>().ok()) != Some(hi)
            {
                return Err(format!("不兼容的参数范围文档：{a}"));
            }
            let v = value(f)?;
            if !(0.0..=1.0).contains(&v) {
                return Err("参数超出归一化范围".into());
            }
            Ok(v)
        };
        let mut p = profile.clone();
        for f in ["attack", "decay", "release"] {
            if value(&format!("{f}/tempo_sync+"))? != 0.0 {
                return Err(format!("{f} 使用节拍同步，请先关闭该段节拍同步。"));
            }
            let native = normalized(f, -8.0, 5.0)? * 13.0 - 8.0;
            let ms = if f == "attack" && native < -7.99 {
                0.0
            } else {
                2.0f64.powf(native) * 1000.0
            };
            if ms > 5000.0 {
                return Err(format!("{f} 超过硬件界面的 5000 ms 上限。"));
            }
            p[f] = json!(ms);
        }
        p["sustain"] = json!(normalized("sustain", 0.0, 1.0)? * 100.0);
        if value("release/deform+")? != 0.0 {
            return Err("释放段启用了 Freeze 或形变选项，当前硬件不能表达。".into());
        }
        model::validate_profile(&p)?;
        Ok(p)
    }
}
pub struct Connection {
    socket: UdpSocket,
}
impl Connection {
    pub fn open(input: u16, output: u16) -> Result<Self> {
        if input < 1024 || output < 1024 || input == output {
            return Err("两个 OSC 端口须不同，范围 1024..65535".into());
        }
        let socket =
            UdpSocket::bind((std::net::Ipv4Addr::LOCALHOST, output)).map_err(|e| e.to_string())?;
        socket.set_nonblocking(true).map_err(|e| e.to_string())?;
        let mut query = osc_string("/q/all_params");
        query.extend(osc_string(","));
        socket
            .send_to(&query, (std::net::Ipv4Addr::LOCALHOST, input))
            .map_err(|e| e.to_string())?;
        Ok(Self { socket })
    }
    pub fn poll(&self, snapshot: &mut Snapshot) -> Result<usize> {
        let mut b = [0u8; 65507];
        let mut count = 0;
        for _ in 0..512 {
            match self.socket.recv_from(&mut b) {
                Ok((n, peer)) if peer.ip() == std::net::Ipv4Addr::LOCALHOST => {
                    if let Ok(messages) = decode(&b[..n], 0) {
                        for (a, v) in messages {
                            snapshot.feed(&a, &v)?;
                            count += 1;
                        }
                    }
                }
                Ok(_) => {}
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => return Ok(count),
                Err(e) => return Err(e.to_string()),
            }
        }
        // Do not silently keep a potentially incomplete snapshot under sustained flooding.
        if self.socket.peek_from(&mut b).is_ok() {
            return Err("OSC 消息过多，请停止快速操作并重新连接。".into());
        }
        Ok(count)
    }
}
