#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use serde_json::Value;
use std::{path::PathBuf, sync::{Arc,Mutex}};
use tang_synth_studio::{runtime::Runtime, voice_engine, synth_midi, studio_sessions::{self,SessionGate}};
use tauri::Manager;

#[tauri::command]
async fn studio_request(
    method: String,
    params: Value,
    state: tauri::State<'_, Arc<Runtime>>,
    voice: tauri::State<'_, voice_engine::State>,
    gate: tauri::State<'_, SessionGate>,
) -> Result<Value, String> {
    let runtime = state.inner().clone();
    let voice=voice.inner().clone();let gate=gate.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        if method=="connect"||method=="disconnect" {
            let _guard=gate.0.lock().map_err(|e|e.to_string())?;
            if method=="connect" {studio_sessions::check_owner(false,false,voice.lock().map_err(|e|e.to_string())?.is_connected())?;}
            runtime.request(method,params)
        } else {runtime.request(method,params)}
    })
        .await
        .map_err(|e| e.to_string())?
}
fn main() {
    // The bundled UI shares one key mapping and protocol-5 hardware session.
    let root=std::env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(std::env::temp_dir).join("SynthString/voice-engine");
    let voice:voice_engine::State=Arc::new(Mutex::new(voice_engine::Engine::new(root)));
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(voice).manage(SessionGate::default()).manage(Mutex::new(synth_midi::Midi::default()))
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
            let args:Vec<_>=std::env::args().collect();
            if let Some(port)=args.iter().position(|s|s=="--port").and_then(|i|args.get(i+1)).cloned(){
                let voice=app.state::<voice_engine::State>().inner().clone();
                let fresh=args.iter().any(|s|s=="--fresh");
                std::thread::spawn(move||{if let Ok(mut e)=voice.lock(){let _=e.action(voice_engine::Action::Connect{port,fresh});}});
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![studio_request,studio_sessions::studio_voice_action,
            voice_engine::voice_catalog,voice_engine::voice_snapshot,studio_sessions::studio_ports,
            synth_midi::synth_midi_ports,synth_midi::synth_midi_connect,synth_midi::synth_midi_events])
        .build(tauri::generate_context!())
        .expect("无法启动 Tang Synth Studio");
    app.run(|handle, event| {
        if let tauri::RunEvent::Exit = event {
            if let Ok(mut engine)=handle.state::<voice_engine::State>().lock(){let _=engine.action(voice_engine::Action::Disconnect);}
            handle.state::<Arc<Runtime>>().close();
        }
    });
}
