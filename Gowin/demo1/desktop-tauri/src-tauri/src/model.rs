use crate::Result;
use serde_json::{Value, json};
use std::collections::BTreeSet;

pub const SAMPLE_RATE: f64 = 96001.059322;
pub const CUSTOM: &str = "自定义波表";
pub const PIANO: &str = "钢琴（合成）";
pub fn num(v: &Value, field: &str, lo: f64, hi: f64) -> Result<f64> {
    v[field]
        .as_f64()
        .filter(|n| n.is_finite() && *n >= lo && *n <= hi)
        .ok_or_else(|| format!("{field} 必须在 {lo}..{hi} 范围内"))
}
pub fn integer(v: &Value, field: &str, lo: u64, hi: u64) -> Result<u64> {
    v[field]
        .as_u64()
        .filter(|n| *n >= lo && *n <= hi)
        .ok_or_else(|| format!("{field} 必须是 {lo}..{hi} 范围内的整数"))
}
pub fn text<'a>(v: &'a Value, field: &str) -> Result<&'a str> {
    v[field]
        .as_str()
        .ok_or_else(|| format!("{field} 必须是字符串"))
}
pub fn wave(v: &Value) -> Option<u16> {
    match v.as_str()? {
        "正弦" => Some(0),
        "方波" => Some(1),
        "锯齿" => Some(2),
        "三角" | PIANO => Some(3),
        CUSTOM => Some(4),
        _ => None,
    }
}
pub fn mode(v: &Value) -> Option<u16> {
    match v.as_str()? {
        "波表混合" => Some(0),
        "FM / PM" => Some(1),
        "AM" => Some(2),
        "环形调制" => Some(3),
        "采样钢琴" => Some(4),
        _ => None,
    }
}
pub fn custom(p: &Value) -> bool {
    p["wave_a"] == CUSTOM || p["wave_b"] == CUSTOM
}
pub fn from_sound(s: &Value) -> Value {
    let piano = s["wave"] == PIANO;
    json!({"mode":"波表混合", "wave_a":if piano { json!("三角") } else { s["wave"].clone() }, "wave_b":"正弦",
        "ratio":1.0,"depth":0.0,"mod_hz":0.0,"sensitivity":0.0,"gain_a":if piano {80.0} else {100.0},"gain_b":if piano {20.0} else {0.0},
        "attack":s["attack"],"decay":s["decay"],"sustain":s["sustain"],"release":s["release"],"m_attack":0.0,"m_decay":0.0,"m_sustain":100.0,"m_release":120.0})
}
pub fn piano_sound() -> Value {
    json!({"attack":2.0,"decay":1400.0,"sustain":0.0,"release":120.0,"volume":25.0,"wave":PIANO,"output_boost":0})
}
pub fn pcm_profile() -> Value {
    let mut p = from_sound(
        &json!({"wave":"正弦","attack":0.0,"decay":2500.0,"sustain":0.0,"release":180.0}),
    );
    p["mode"] = json!("采样钢琴");
    p
}
pub fn defaults() -> Value {
    let sound = json!({"attack":10.0,"decay":25.3,"sustain":75.0,"release":75.9,"volume":25.0,"wave":"正弦","output_boost":0});
    let keys: Vec<Value> = "12345678QWERTYUIASDFGHJKZXCVBNM,".chars().enumerate().map(|(i,c)| json!({
        "name":format!("KEY {:02}",i+1),"note":48+i,"velocity":96,"keycode":if c==',' {188} else {c as u32},"shortcut":c.to_string(),"synth":from_sound(&sound)
    })).collect();
    json!({"version":2,"keys":keys,"sound":sound,"tauri_bindings":{}})
}
pub fn validate_profile(p: &Value) -> Result<()> {
    let m = mode(&p["mode"]).ok_or("合成器模式不合法")?;
    for f in ["wave_a", "wave_b"] {
        if wave(&p[f]).is_none() || p[f] == PIANO {
            return Err("振荡器波形不合法".into());
        }
    }
    for (f, lo, hi) in [
        ("ratio", 1.0 / 256.0, 8.0),
        ("depth", 0.0, if m < 2 { 2.0 } else { 1.0 }),
        ("mod_hz", 0.0, 1000.0),
        ("sensitivity", 0.0, 100.0),
        ("gain_a", 0.0, 100.0),
        ("gain_b", 0.0, 100.0),
    ] {
        num(p, f, lo, hi)?;
    }
    if p.get("frame_position").is_some() {
        num(p, "frame_position", 0.0, 100.0)?;
    }
    for prefix in ["", "m_"] {
        for f in ["attack", "decay", "sustain", "release"] {
            num(
                p,
                &format!("{prefix}{f}"),
                0.0,
                if f == "sustain" { 100.0 } else { 5000.0 },
            )?;
        }
    }
    Ok(())
}
/// Preserve unknown document fields for compatibility with older editors.
pub fn validate_config(mut c: Value) -> Result<Value> {
    if !matches!(c["version"].as_u64(), Some(1 | 2))
        || c["keys"].as_array().map(Vec::len) != Some(32)
    {
        return Err("配置必须包含版本 1/2 和恰好 32 个音键。".into());
    }
    let sound = c
        .get_mut("sound")
        .and_then(Value::as_object_mut)
        .ok_or("音色配置必须是对象")?;
    sound.entry("output_boost").or_insert(json!(0));
    integer(&c["sound"], "output_boost", 0, 4)?;
    for f in ["attack", "decay", "sustain", "release", "volume"] {
        num(
            &c["sound"],
            f,
            0.0,
            if f == "sustain" || f == "volume" {
                100.0
            } else {
                5000.0
            },
        )?;
    }
    if wave(&c["sound"]["wave"]).is_none() {
        return Err("未知波形".into());
    }
    let fallback = from_sound(&c["sound"]);
    let mut used = BTreeSet::new();
    for k in c["keys"].as_array_mut().unwrap() {
        integer(k, "note", 0, 127)?;
        integer(k, "velocity", 1, 127)?;
        let code = integer(k, "keycode", 1, 255)?;
        if [16, 17, 18, 27, 91, 92].contains(&code) || !used.insert(code) {
            return Err("快捷键不能重复，也不能使用 Esc、修饰键或 Windows 键。".into());
        }
        for f in ["name", "shortcut"] {
            if !(1..=24).contains(&text(k, f)?.chars().count()) {
                return Err("名称与快捷键说明需为 1..24 个字符。".into());
            }
        }
        k.as_object_mut()
            .ok_or("音键配置必须是对象")?
            .entry("synth")
            .or_insert_with(|| fallback.clone());
        validate_profile(&k["synth"])?;
    }
    c["version"] = json!(2);
    c.as_object_mut()
        .unwrap()
        .entry("tauri_bindings")
        .or_insert(json!({}));
    let b = c["tauri_bindings"]
        .as_object()
        .ok_or("音色资源绑定格式无效")?;
    for (k, v) in b {
        if !k
            .parse::<usize>()
            .is_ok_and(|i| i < 32 && i.to_string() == *k)
            || v.as_u64().is_none()
        {
            return Err("资源绑定的音键或音色编号无效".into());
        }
    }
    Ok(c)
}
pub fn encode_step(distance: u64, ms: f64) -> u16 {
    if ms == 0.0 || distance == 0 {
        return 0;
    }
    let raw = (((distance << 14) as f64 * 1000.0 / (ms * SAMPLE_RATE)).round_ties_even() as u64)
        .clamp(1, 262143 << 14);
    let mut exp = (64 - raw.leading_zeros()).saturating_sub(11);
    let mut mantissa = if exp == 0 {
        raw
    } else {
        (raw + (1 << (exp - 1))) >> exp
    };
    if mantissa == 2048 {
        exp += 1;
        mantissa = 1024;
    }
    ((exp << 11) as u64 | mantissa) as u16
}
pub fn words(p: &Value) -> Result<Vec<u16>> {
    validate_profile(p)?;
    let n = |f: &str| p[f].as_f64().unwrap();
    let r = |f: &str, scale: f64| (n(f) * scale).round_ties_even() as u16;
    let mut w = vec![
        mode(&p["mode"]).unwrap() | 0x8000,
        wave(&p["wave_a"]).unwrap(),
        wave(&p["wave_b"]).unwrap(),
        r("ratio", 256.0),
        r("depth", 4096.0),
    ];
    for prefix in ["", "m_"] {
        let s = (n(&format!("{prefix}sustain")) * 65535.0 / 100.0).round_ties_even() as u16;
        w.extend([
            encode_step(262143, n(&format!("{prefix}attack"))),
            encode_step(262143 - 4 * s as u64, n(&format!("{prefix}decay"))),
            s,
            encode_step(262143, n(&format!("{prefix}release"))),
        ]);
    }
    // Keep multiplication/division order identical to the established wire codec.
    w.extend([
        (n("gain_b") * 65535.0 / 100.0).round_ties_even() as u16,
        (n("sensitivity") * 127.0 / 100.0).round_ties_even() as u16,
        r("mod_hz", 16.0),
        (n("gain_a") * 65535.0 / 100.0).round_ties_even() as u16,
        0,
    ]);
    Ok(w)
}
