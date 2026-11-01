pub mod audio;
pub mod calibration;
pub mod link;
pub mod model;
pub mod protocol;
pub mod runtime;
pub mod synth_debug;
pub mod synth_studio;
pub mod synth_midi;
use runtime::{Action, Service, Snapshot};
use tauri::Manager;

#[tauri::command]
fn snapshot(service: tauri::State<Service>, selected: usize) -> Snapshot {
    service.snapshot(selected)
}
#[tauri::command]
fn list_ports() -> Result<serde_json::Value, String> {
    runtime::ports()
}
#[tauri::command]
async fn perform(service: tauri::State<'_, Service>, action: Action) -> Result<String, String> {
    service.action(action)
}
#[tauri::command]
async fn file_action(service: tauri::State<'_, Service>, kind: String) -> Result<String, String> {
    match kind.as_str() {
        "replay" => {
            if let Some(path) = rfd::AsyncFileDialog::new()
                .set_title("回放原始遥测")
                .add_filter("原始帧", &["bin", "txt"])
                .pick_file()
                .await
            {
                service.action(Action::Replay {
                    path: path.path().display().to_string(),
                })
            } else {
                Ok("已取消".into())
            }
        }
        "import" => {
            if let Some(path) = rfd::AsyncFileDialog::new()
                .set_title("导入键盘校准")
                .add_filter("校准 JSON", &["json"])
                .pick_file()
                .await
            {
                service.action(Action::Import {
                    path: path.path().display().to_string(),
                })
            } else {
                Ok("已取消".into())
            }
        }
        "export" | "diagnostics" => {
            let name = if kind == "export" {
                "calibration.json"
            } else {
                "hardware-diagnostics.json"
            };
            if let Some(path) = rfd::AsyncFileDialog::new()
                .set_title("保存配置 / 诊断")
                .set_file_name(name)
                .add_filter("JSON", &["json"])
                .save_file()
                .await
            {
                let s = service.snapshot(0);
                if kind == "export" {
                    calibration::atomic_json(path.path(), &s.view.profile)?;
                } else {
                    calibration::atomic_json(path.path(), &s)?;
                }
                Ok(format!("已保存：{}", path.path().display()))
            } else {
                Ok("已取消".into())
            }
        }
        _ => Err("未知文件操作".into()),
    }
}
pub fn run() {
    let service = Service::start();
    tauri::Builder::default()
        .manage(service)
        .invoke_handler(tauri::generate_handler![
            snapshot,
            list_ports,
            perform,
            file_action
        ])
        .setup(|app| {
            let args: Vec<_> = std::env::args().collect();
            if let Some(i) = args.iter().position(|a| a == "--replay") {
                if let Some(path) = args.get(i + 1) {
                    let _ = app
                        .state::<Service>()
                        .action(Action::Replay { path: path.clone() });
                }
            } else if let Some(i) = args.iter().position(|a| a == "--port") {
                if let Some(port) = args.get(i + 1) {
                    let _ = app
                        .state::<Service>()
                        .action(Action::Connect { port: port.clone() });
                }
            }
            if let Some(i) = args.iter().position(|a| a == "--diagnostics") {
                if let Some(path) = args.get(i + 1) {
                    let handle = app.handle().clone();
                    let path = std::path::PathBuf::from(path);
                    std::thread::spawn(move || loop {
                        let snapshot = handle.state::<Service>().snapshot(0);
                        let _ = calibration::atomic_json(&path, &snapshot);
                        std::thread::sleep(std::time::Duration::from_secs(1));
                    });
                }
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if matches!(event, tauri::WindowEvent::CloseRequested { .. }) {
                let s = window.state::<Service>();
                s.audio.configure(false, 0.);
                let _ = s.action(Action::Disconnect);
            }
        })
        .run(tauri::generate_context!())
        .expect("Tang Hardware Lab failed to start");
}
