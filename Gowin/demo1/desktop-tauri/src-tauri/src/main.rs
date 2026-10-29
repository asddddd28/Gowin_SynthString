#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use serde_json::Value;
use std::{path::PathBuf, sync::Arc};
use tang_synth_studio::runtime::Runtime;
use tauri::Manager;

#[tauri::command]
async fn studio_request(
    method: String,
    params: Value,
    state: tauri::State<'_, Arc<Runtime>>,
) -> Result<Value, String> {
    let runtime = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || runtime.request(method, params))
        .await
        .map_err(|e| e.to_string())?
}
fn main() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let assets = app.path().resource_dir()?.join("assets");
            let assets = if assets.is_dir() {
                assets
            } else if cfg!(debug_assertions) {
                PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets")
            } else {
                assets
            };
            // Isolated configuration is available only in debug builds for native QA.
            let config = if cfg!(debug_assertions) {
                std::env::var_os("TANG_STUDIO_TEST_CONFIG").map(PathBuf::from)
            } else {
                None
            };
            let runtime = Runtime::start(&assets, config).map_err(std::io::Error::other)?;
            app.manage(Arc::new(runtime));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![studio_request])
        .build(tauri::generate_context!())
        .expect("无法启动 Tang Synth Studio");
    app.run(|handle, event| {
        if let tauri::RunEvent::Exit = event {
            handle.state::<Arc<Runtime>>().close();
        }
    });
}
