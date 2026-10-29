use crate::{Result, engine::Engine};
use serde_json::Value;
use std::{
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, SyncSender},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};
struct Request {
    method: String,
    params: Value,
    response: SyncSender<Result<Value>>,
    queued: Instant,
}
pub struct Runtime {
    sender: SyncSender<Request>,
    stop: Arc<AtomicBool>,
    thread: Mutex<Option<JoinHandle<()>>>,
}
impl Runtime {
    pub fn start(assets: &Path, config: Option<PathBuf>) -> Result<Self> {
        let mut engine = Engine::new(assets, config)?;
        let (sender, rx) = mpsc::sync_channel::<Request>(32);
        let stop = Arc::new(AtomicBool::new(false));
        let stopped = stop.clone();
        let thread = thread::Builder::new()
            .name("tang-engine".into())
            .spawn(move || {
                while !stopped.load(Ordering::Acquire) {
                    // Tick between requests so a busy UI cannot starve the watchdog.
                    engine.tick();
                    match rx.recv_timeout(Duration::from_millis(20)) {
                        Ok(r) => {
                            let result = if r.queued.elapsed() > Duration::from_secs(5) {
                                Err("后台请求已过期，请重试。".into())
                            } else {
                                engine.dispatch(&r.method, r.params)
                            };
                            let _ = r.response.send(result);
                        }
                        Err(mpsc::RecvTimeoutError::Timeout) => {}
                        Err(mpsc::RecvTimeoutError::Disconnected) => break,
                    }
                }
                engine.close();
            })
            .map_err(|e| e.to_string())?;
        Ok(Self {
            sender,
            stop,
            thread: Mutex::new(Some(thread)),
        })
    }
    pub fn request(&self, method: String, params: Value) -> Result<Value> {
        if self.stop.load(Ordering::Acquire) {
            return Err("后台已关闭".into());
        }
        let (response, rx) = mpsc::sync_channel(1);
        self.sender
            .try_send(Request {
                method,
                params,
                response,
                queued: Instant::now(),
            })
            .map_err(|_| "后台繁忙或已停止，请稍后重试。")?;
        rx.recv()
            .map_err(|_| "Rust 后台工作线程已停止，请重新打开应用。".to_string())?
    }
    pub fn close(&self) {
        self.stop.store(true, Ordering::Release);
        if let Ok(mut lock) = self.thread.lock()
            && let Some(thread) = lock.take()
        {
            let _ = thread.join();
        }
    }
}
impl Drop for Runtime {
    fn drop(&mut self) {
        self.close();
    }
}
