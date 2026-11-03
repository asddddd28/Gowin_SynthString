//! Native application backend. No interpreter, child process or frontend dependency.
pub mod engine;
pub mod midi;
pub mod model;
pub mod performance;
#[cfg(test)]
mod performance_tests;
pub mod protocol;
pub mod resources;
pub mod native_presets;
pub mod runtime;
pub mod surge;
pub mod transport;
// One implementation of protocol 5 is shared by the full studio and probe app.
#[path = "../../../../demo_test/desktop-tauri/src-tauri/src/voice_engine.rs"]
pub mod voice_engine;
#[path = "../../../../demo_test/desktop-tauri/src-tauri/src/synth_midi.rs"]
pub mod synth_midi;
pub mod studio_sessions;

#[tauri::command]
fn list_ports() -> Result<serde_json::Value> {
    let ports=transport::ports()?;
    Ok(serde_json::Value::Array(ports.as_array().ok_or("Invalid port list")?.iter()
        .map(|p|serde_json::json!({"name":p["device"],"description":p["description"]})).collect()))
}

pub type Result<T> = std::result::Result<T, String>;
#[cfg(test)]
mod tests;
