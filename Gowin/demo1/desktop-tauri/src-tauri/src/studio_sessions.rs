//! A single gate serializes protocol switches; offline editing remains available.
use crate::{runtime::Runtime, voice_engine::{Action, State, View}};
use std::sync::{Arc, Mutex};

#[derive(Clone, Default)]
pub struct SessionGate(pub Arc<Mutex<()>>);

pub fn check_owner(want_voice: bool, legacy_open: bool, voice_open: bool) -> Result<(), String> {
    if want_voice && legacy_open {return Err("旧版工作台已连接设备，请先断开，再连接 FM Voice 固件".into());}
    if !want_voice && voice_open {return Err("Voice 已连接设备，请先在声音设计的 Voice 硬件配置中断开；旧版上传协议不适用于当前固件".into());}
    Ok(())
}

#[tauri::command]
pub async fn studio_voice_action(action: Action, voice: tauri::State<'_, State>,
    legacy: tauri::State<'_, Arc<Runtime>>, gate: tauri::State<'_, SessionGate>) -> Result<View,String> {
    let voice=voice.inner().clone();let legacy=legacy.inner().clone();let gate=gate.inner().clone();
    tauri::async_runtime::spawn_blocking(move||{
        let _guard=gate.0.lock().map_err(|e|e.to_string())?;
        if matches!(&action, Action::Connect{..}) {
            let state=legacy.request("get_state".into(),serde_json::json!({}))?;
            check_owner(true,state["online"]==true||state["connecting"]==true,false)?;
        }
        voice.lock().map_err(|e|e.to_string())?.action(action)
    }).await.map_err(|e|e.to_string())?
}

#[tauri::command]
pub fn studio_ports() -> Result<serde_json::Value,String> {crate::voice_engine::port_catalog()}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn protocols_cannot_share_a_connection() {
        assert!(check_owner(true,true,false).is_err());
        assert!(check_owner(false,false,true).is_err());
        assert!(check_owner(true,false,false).is_ok());
        assert!(check_owner(false,false,false).is_ok());
    }
}
