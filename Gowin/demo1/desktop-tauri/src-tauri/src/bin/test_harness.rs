//! Test-only IPC adapter. Not built or shipped in the desktop release.
use serde_json::{Value, json};
use std::{
    io::{self, BufRead, Write},
    path::PathBuf,
    sync::mpsc,
    time::Duration,
};
use tang_synth_studio::engine::Engine;
fn main() {
    let args: Vec<_> = std::env::args_os().collect();
    let mut engine =
        Engine::new(&PathBuf::from(&args[1]), Some(PathBuf::from(&args[2]))).expect("test engine");
    let (tx, rx) = mpsc::sync_channel(32);
    std::thread::spawn(move || {
        for line in io::stdin().lock().lines() {
            match line {
                Ok(l) => {
                    if tx.send(l).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });
    loop {
        engine.tick();
        match rx.recv_timeout(Duration::from_millis(20)) {
            Ok(line) => {
                let result = (|| -> Result<Value, String> {
                    let v: Value = serde_json::from_str(&line).map_err(|e| e.to_string())?;
                    let method = v["method"].as_str().ok_or("missing method")?;
                    match method {
                        "test_connect" => {
                            engine.test_connect();
                            Ok(Value::Null)
                        }
                        "test_frames" => Ok(engine.test_frames()),
                        "test_midi" => {
                            let bytes: Vec<u8> =
                                serde_json::from_value(v["params"]["bytes"].clone())
                                    .map_err(|e| e.to_string())?;
                            engine.test_midi(&bytes);
                            Ok(Value::Null)
                        }
                        "test_ack" => {
                            engine.handle_event(tang_synth_studio::transport::Event::Done(
                                tang_synth_studio::protocol::Kind::Profiles,
                            ))?;
                            Ok(Value::Null)
                        }
                        "test_transfer_error" => {
                            engine.handle_event(
                                tang_synth_studio::transport::Event::TransferError(
                                    "测试确认超时".into(),
                                ),
                            )?;
                            Ok(Value::Null)
                        }
                        _ => engine.dispatch(method, v["params"].clone()),
                    }
                })();
                let response = match result {
                    Ok(v) => json!({"ok":true,"result":v}),
                    Err(e) => json!({"ok":false,"error":e}),
                };
                println!("{response}");
                io::stdout().flush().unwrap();
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }
    engine.close();
}
