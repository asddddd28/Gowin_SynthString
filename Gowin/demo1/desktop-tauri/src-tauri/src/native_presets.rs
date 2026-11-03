//! Curated full six-operator presets, independent of the legacy two-oscillator bank.
use crate::{Result,voice_engine::{NativePatch,compile_native}};
use serde_json::Value;
use std::{collections::BTreeSet,sync::OnceLock};

fn validate_bank(raw:&str)->Result<Value>{
    let bank:Value=serde_json::from_str(raw).map_err(|e|format!("原生音色库 JSON 无效: {e}"))?;
    if bank["format"]!="synthstring-native-presets-v1"||bank["version"]!=1{return Err("原生音色库版本无效".into());}
    let rows=bank["presets"].as_array().filter(|r|!r.is_empty()&&r.len()<=128).ok_or("原生音色库数量无效")?;
    let mut ids=BTreeSet::new();
    for row in rows {
        let id=row["id"].as_str().filter(|s|!s.is_empty()).ok_or("音色 ID 缺失")?;
        if !ids.insert(id){return Err("原生音色 ID 重复".into());}
        let patch:NativePatch=serde_json::from_value(row["patch"].clone()).map_err(|e|format!("{id}: {e}"))?;
        if row["title"]!=patch.name||!matches!(row["category"].as_str(),Some("AM"|"PM"|"Drum"))||row["source"].as_str().unwrap_or("").is_empty(){return Err(format!("{id}: 音色信息不完整"));}
        if patch.operators.iter().any(|op|op.wave=="wavetable"){return Err(format!("{id}: 此库不应依赖全局波表"));}
        if row["percussive"]==true&&patch.operators.iter().any(|op|op.enabled&&op.carrier&&(op.levels[1]!=0.||op.levels[2]!=0.||op.fixed_hz.is_none())){return Err(format!("{id}: 鼓音色必须固定频率且自然衰减至零"));}
        compile_native(patch,0,1).map_err(|e|format!("{id}: {e}"))?;
    }
    Ok(Value::Array(rows.clone()))
}

pub fn catalog()->Result<Value>{
    static BANK:OnceLock<Result<Value>>=OnceLock::new();
    BANK.get_or_init(||validate_bank(include_str!("../assets/native-presets.json"))).clone()
}

#[cfg(test)]mod tests {
    use super::*;
    #[test]fn complete_bank_and_fixed_drums_compile(){
        let rows=catalog().unwrap();let rows=rows.as_array().unwrap();assert_eq!(rows.len(),20);
        for (category,count) in [("AM",6),("PM",6),("Drum",8)]{assert_eq!(rows.iter().filter(|p|p["category"]==category).count(),count);}
        for row in rows {
            let p:NativePatch=serde_json::from_value(row["patch"].clone()).unwrap();
            for slot in 0..4 {let (commands,_)=compile_native(p.clone(),slot,7).unwrap();assert_eq!(commands.len(),14);assert_eq!(commands.last().unwrap().address,slot);}
        }
    }
    #[test]fn bank_rejects_sustaining_drums_and_bad_routes(){
        let mut bank:Value=serde_json::from_str(include_str!("../assets/native-presets.json")).unwrap();
        let row=bank["presets"].as_array_mut().unwrap().iter_mut().find(|p|p["category"]=="Drum").unwrap();row["patch"]["operators"][1]["levels"][1]=serde_json::json!(0.2);
        assert!(validate_bank(&bank.to_string()).unwrap_err().contains("自然衰减"));
        let mut bank:Value=serde_json::from_str(include_str!("../assets/native-presets.json")).unwrap();bank["presets"][0]["patch"]["operators"][0]["sources"]=serde_json::json!([1]);assert!(validate_bank(&bank.to_string()).is_err());
    }
    #[test]fn exact_integer_model_compiler_parity(){
        let expected:Value=serde_json::from_str(include_str!("../assets/native-preset-oracle.json")).unwrap();
        let rows=catalog().unwrap();assert_eq!(rows.as_array().unwrap().len(),expected.as_array().unwrap().len());
        for (row,reference) in rows.as_array().unwrap().iter().zip(expected.as_array().unwrap()){
            assert_eq!(row["id"],reference["id"]);
            let patch:NativePatch=serde_json::from_value(row["patch"].clone()).unwrap();
            let (commands,_)=compile_native(patch,0,1).unwrap();
            let actual:Vec<Value>=commands.iter().map(|c|serde_json::json!({"opcode":c.opcode,"address":c.address,"words":c.words})).collect();
            assert_eq!(serde_json::json!(actual),reference["commands"],"{}",row["id"]);
        }
    }
}
