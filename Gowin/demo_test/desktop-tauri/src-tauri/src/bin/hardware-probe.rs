//! Validation harness using the same Rust service as the actual App.
use std::{
    path::PathBuf,
    time::{Duration, Instant},
};
use tang_hardware_lab::{
    calibration::atomic_json,
    runtime::{Action, Service},
};
fn wait(
    service: &Service,
    timeout: f64,
    predicate: impl Fn(&tang_hardware_lab::runtime::Snapshot) -> bool,
) -> bool {
    let start = Instant::now();
    while start.elapsed().as_secs_f64() < timeout {
        if predicate(&service.snapshot(0)) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    false
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let service = Service::start();
    let out = PathBuf::from(args.get(3).cloned().unwrap_or("probe.json".into()));
    if args.get(1).is_some_and(|a| a == "--replay") {
        service
            .action(Action::Replay {
                path: args.get(2).expect("capture path").clone(),
            })
            .unwrap();
        assert!(wait(&service, 40., |s| s.view.connection == "replay_done"));
        let s = service.snapshot(0);
        assert_eq!(s.view.tx_bytes, 0);
        assert_eq!(s.view.audio.played, 0);
        assert_eq!(s.view.errors, 0);
        assert_eq!(s.view.protocol, "hub");
        atomic_json(&out, &s).unwrap();
        println!("PASS: replay, no TX/audio, all protocols parsed");
    } else {
        let port = args.get(2).cloned().unwrap_or("COM4".into());
        service.action(Action::Connect { port }).unwrap();
        let ready = wait(&service, 15., |s| {
            s.view.protocol == "hub"
                && s.view.fresh_count == 40
                && s.view.board.as_ref().is_some_and(|b| b.configured)
                && !s.view.transfer.busy
        });
        if !ready {
            atomic_json(&out, &service.snapshot(0)).unwrap();
            service.action(Action::Disconnect).unwrap();
            eprintln!("NOT VERIFIED: current board does not provide all integrated hardware telemetry. See {}",out.display());
            std::process::exit(2);
        }
        service.action(Action::Sync).unwrap();
        assert!(wait(&service, 12., |s| s.view.transfer.total == 35
            && s.view.transfer.completed == 35
            && !s.view.transfer.busy));
        let settings = service.snapshot(0).view.settings;
        for mode in [0, 1, 2, 3, 4, 6] {
            service
                .action(Action::Effect { mode, direction: 0 })
                .unwrap();
            assert!(wait(&service, 5., |s| s
                .view
                .board
                .as_ref()
                .is_some_and(|b| b.mode == mode)
                && s.view.transfer.completed == 1
                && !s.view.transfer.busy));
        }
        for game in [1, 2, 3] {
            service.action(Action::GameStart { game }).unwrap();
            assert!(wait(&service, 5., |s| s
                .view
                .game
                .as_ref()
                .is_some_and(|g| g.game == game && g.phase == 1)
                && !s.view.transfer.busy));
            service.action(Action::GameStop).unwrap();
            assert!(wait(&service, 5., |s| s
                .view
                .board
                .as_ref()
                .is_some_and(|b| b.mode != 5)
                && !s.view.transfer.busy));
        }
        service
            .action(Action::Effect {
                mode: settings.effect,
                direction: settings.direction,
            })
            .unwrap();
        assert!(wait(&service, 5., |s| !s.view.transfer.busy
            && s.view
                .board
                .as_ref()
                .is_some_and(|b| b.mode == settings.effect)));
        service.action(Action::Record).unwrap();
        std::thread::sleep(Duration::from_secs(5));
        service.action(Action::Record).unwrap();
        let s = service.snapshot(0);
        atomic_json(&out, &s).unwrap();
        assert_eq!(s.view.errors, 0);
        assert_eq!(s.view.sequence_errors, 0);
        assert_eq!(s.view.transfer.failures, 0);
        assert_eq!(s.view.fresh_count, 40);
        assert!(
            s.view.audio.ready,
            "Native audio failed: {}",
            s.view.audio.error
        );
        service.action(Action::Disconnect).unwrap();
        println!("PASS: live 40/40, 35 calibration ACKs, six effects, three game start/stop, recording, native audio ready");
    }
}
