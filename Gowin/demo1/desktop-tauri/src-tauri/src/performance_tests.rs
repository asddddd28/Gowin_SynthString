use crate::{
    engine::Engine,
    midi::{self, Message},
    protocol::Kind,
    transport::Event,
};
use serde_json::{Value, json};
fn setup() -> (tempfile::TempDir, Engine) {
    let dir = tempfile::tempdir().unwrap();
    let mut e = Engine::new(
        &std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets"),
        Some(dir.path().join("settings.json")),
    )
    .unwrap();
    e.test_connect();
    (dir, e)
}
fn call(e: &mut Engine, m: &str, p: Value) -> Value {
    e.dispatch(m, p).unwrap()
}
fn on(e: &mut Engine, index: usize, owner: &str) {
    call(e, "note_on", json!({"index":index,"owner":owner}));
}
fn off(e: &mut Engine, index: usize, owner: &str) {
    call(e, "note_off", json!({"index":index,"owner":owner}));
}
fn pedal(e: &mut Engine, down: bool) {
    call(e, "set_sustain", json!({"down":down}));
}
fn frames(e: &Engine, op: u8) -> Vec<Value> {
    e.test_frames()
        .as_array()
        .unwrap()
        .iter()
        .filter(|f| f[1] == op)
        .cloned()
        .collect()
}
fn edit(e: &mut Engine, gain: f64) {
    let mut p = e.config["keys"][0]["synth"].clone();
    p["gain_a"] = json!(gain);
    call(e, "live_edit", json!({"index":0,"profile":p}));
}
fn live(e: &mut Engine) {
    call(e, "live_mode", json!({"enabled":true}));
}
fn ack(e: &mut Engine) {
    e.handle_event(Event::Done(Kind::Profiles)).unwrap();
}

#[test]
fn midi_parser_supports_channels_note_zero_and_rejects_invalid_packets() {
    assert_eq!(
        midi::decode(&[0x9f, 60, 127]),
        Some(Message::On {
            channel: 15,
            note: 60,
            velocity: 127
        })
    );
    assert_eq!(
        midi::decode(&[0x90, 60, 0]),
        Some(Message::Off {
            channel: 0,
            note: 60
        })
    );
    assert_eq!(
        midi::decode(&[0x82, 60, 40]),
        Some(Message::Off {
            channel: 2,
            note: 60
        })
    );
    assert_eq!(
        midi::decode(&[0xb0, 64, 127]),
        Some(Message::Control {
            channel: 0,
            cc: 64,
            value: 127
        })
    );
    for b in [
        &[][..],
        &[0x90, 60],
        &[0x90, 128, 20],
        &[0x90, 60, 255],
        &[0xe0, 30, 50],
        &[0x90, 60, 1, 2],
    ] {
        assert_eq!(midi::decode(b), None);
    }
}
#[test]
fn transpose_and_velocity_are_temporary_validated_and_release_old_notes() {
    let (_d, mut e) = setup();
    let saved = e.config.clone();
    on(&mut e, 0, "keyboard");
    assert!(
        e.dispatch(
            "performance_settings",
            json!({"transpose":12,"velocity":128})
        )
        .is_err()
    );
    assert_eq!(e.state()["performance"]["transpose"], 0);
    assert_eq!(e.state()["held"], json!([0]));
    call(
        &mut e,
        "performance_settings",
        json!({"transpose":12,"velocity":45}),
    );
    assert_eq!(e.state()["held"], json!([]));
    assert_eq!(frames(&e, 2).len(), 1);
    on(&mut e, 0, "pointer:44");
    let frame = frames(&e, 1).pop().unwrap();
    assert_eq!(frame[3], saved["keys"][0]["note"].as_u64().unwrap() + 12);
    assert_eq!(frame[4], 45);
    assert_eq!(e.config, saved);
    assert_eq!(e.state()["revision"], 0);
    for v in [json!(-25), json!(25), json!(0.5), json!("12")] {
        assert!(
            e.dispatch("performance_settings", json!({"transpose":v}))
                .is_err()
        );
    }
}
#[test]
fn transpose_rejects_out_of_range_notes_and_untrusted_owners() {
    let (_d, mut e) = setup();
    e.config["keys"][0]["note"] = json!(120);
    call(&mut e, "performance_settings", json!({"transpose":12}));
    assert!(
        e.dispatch("note_on", json!({"index":0,"owner":"keyboard"}))
            .is_err()
    );
    assert!(
        e.dispatch("perform_note_on", json!({"index":0,"owner":"midi:0:60"}))
            .is_err()
    );
    assert!(
        e.dispatch("perform_note_on", json!({"index":32,"owner":"pointer:1"}))
            .is_err()
    );
    assert!(frames(&e, 1).is_empty());
}
#[test]
fn sustain_retrigger_and_multi_owner_release_are_balanced() {
    let (_d, mut e) = setup();
    pedal(&mut e, true);
    on(&mut e, 0, "keyboard");
    on(&mut e, 0, "pointer:1");
    off(&mut e, 0, "keyboard");
    off(&mut e, 0, "pointer:1");
    assert!(frames(&e, 2).is_empty());
    on(&mut e, 0, "pointer:2");
    assert_eq!(frames(&e, 1).len(), 2);
    assert_eq!(frames(&e, 2).len(), 1);
    off(&mut e, 0, "pointer:2");
    pedal(&mut e, false);
    off(&mut e, 0, "pointer:2");
    assert_eq!(frames(&e, 2).len(), 2);
    assert_eq!(e.state()["held"], json!([]));
    pedal(&mut e, true);
    off(&mut e, 0, "keyboard");
    assert_eq!(e.state()["held"], json!([]));
}
#[test]
fn releasing_pedal_does_not_release_a_physically_held_key() {
    let (_d, mut e) = setup();
    pedal(&mut e, true);
    on(&mut e, 0, "keyboard");
    on(&mut e, 0, "pointer:1");
    off(&mut e, 0, "keyboard");
    pedal(&mut e, false);
    assert!(frames(&e, 2).is_empty());
    off(&mut e, 0, "pointer:1");
    assert_eq!(frames(&e, 2).len(), 1);
}
#[test]
fn midi_routes_original_note_velocity_channel_and_session_transpose() {
    let (_d, mut e) = setup();
    let note = e.config["keys"][0]["note"].as_u64().unwrap() as u8;
    call(
        &mut e,
        "performance_settings",
        json!({"channel":2,"velocity":99,"transpose":12}),
    );
    e.test_midi(&[0x90, note, 80]);
    assert!(frames(&e, 1).is_empty());
    e.test_midi(&[0x91, note, 40]);
    let f = frames(&e, 1).pop().unwrap();
    assert_eq!(f[3], note + 12);
    assert_eq!(f[4], 40);
    e.test_midi(&[0x91, note, 0]);
    assert_eq!(e.state()["held"], json!([]));
    e.test_midi(&[0x91, 127, 40]);
    assert!(
        e.state()["midi"]["message"]
            .as_str()
            .unwrap()
            .contains("未分配")
    );
}
#[test]
fn midi_channel_sustain_and_cc_all_notes_off_do_not_leave_hanging_owners() {
    let (_d, mut e) = setup();
    let note = e.config["keys"][0]["note"].as_u64().unwrap() as u8;
    e.test_midi(&[0xb0, 64, 127]);
    e.test_midi(&[0x90, note, 70]);
    e.test_midi(&[0x91, note, 71]);
    e.test_midi(&[0x80, note, 0]);
    e.test_midi(&[0x81, note, 0]);
    assert_eq!(e.state()["held"], json!([0]));
    e.test_midi(&[0xb1, 64, 0]);
    assert_eq!(e.state()["held"], json!([0]));
    e.test_midi(&[0xb0, 64, 0]);
    assert_eq!(e.state()["held"], json!([]));
    e.test_midi(&[0x90, note, 70]);
    e.test_midi(&[0xb0, 123, 0]);
    assert_eq!(e.state()["held"], json!([]));
}
#[test]
fn midi_cannot_rearm_hidden_or_stale_ui() {
    let (_d, mut e) = setup();
    let note = e.config["keys"][0]["note"].as_u64().unwrap() as u8;
    e.test_midi(&[0x90, note, 70]);
    call(&mut e, "performance_arm", json!({"enabled":false}));
    e.test_midi(&[0x90, note, 70]);
    e.test_midi(&[0xb0, 64, 127]);
    assert_eq!(e.state()["held"], json!([]));
    assert_eq!(e.state()["performance"]["sustain"], false);
    call(&mut e, "performance_arm", json!({"enabled":true}));
    e.expire_ui();
    e.test_midi(&[0x90, note, 70]);
    assert_eq!(e.state()["held"], json!([]));
    call(&mut e, "get_state", json!({}));
    e.test_midi(&[0x90, note, 70]);
    assert_eq!(e.state()["held"], json!([0]));
    e.expire_ui();
    e.tick();
    assert_eq!(e.state()["held"], json!([]));
}
#[test]
fn live_edit_coalesces_latest_profile_and_requires_ack_without_retriggering() {
    let (_d, mut e) = setup();
    let saved = e.config.clone();
    on(&mut e, 0, "keyboard");
    live(&mut e);
    edit(&mut e, 20.0);
    edit(&mut e, 30.0);
    edit(&mut e, 40.0);
    assert_eq!(e.state()["live"]["pending"], json!([0]));
    e.advance_performance();
    assert_eq!(e.state()["live"]["inflight"], 0);
    assert!(
        e.dispatch("note_on", json!({"index":0,"owner":"pointer:1"}))
            .is_err()
    );
    on(&mut e, 1, "pointer:1");
    assert_eq!(frames(&e, 2).len(), 0);
    edit(&mut e, 55.0);
    ack(&mut e);
    assert_eq!(e.state()["live"]["applied"]["0"]["gain_a"], 40.0);
    assert!(
        e.dispatch("note_on", json!({"index":0,"owner":"pointer:2"}))
            .is_err()
    );
    e.tick();
    assert!(e.state()["live"]["inflight"].is_null()); // 150 ms send cap
    e.advance_performance();
    ack(&mut e);
    assert_eq!(e.state()["live"]["applied"]["0"]["gain_a"], 55.0);
    assert_eq!(e.config, saved);
    assert_eq!(e.state()["revision"], 0);
    assert_eq!(frames(&e, 2).len(), 0);
    off(&mut e, 0, "keyboard");
    on(&mut e, 0, "keyboard");
    assert_eq!(frames(&e, 1).len(), 3);
}
#[test]
fn saving_confirmed_preview_keeps_the_held_voice_and_hardware_confirmation() {
    let (d, mut e) = setup();
    on(&mut e, 0, "keyboard");
    live(&mut e);
    edit(&mut e, 30.0);
    e.advance_performance();
    ack(&mut e);
    let mut key = e.config["keys"][0].clone();
    key["synth"]["gain_a"] = json!(30.0);
    call(&mut e, "save_key", json!({"index":0,"key":key}));
    assert_eq!(frames(&e, 2).len(), 0);
    assert!(e.state()["synced"].as_array().unwrap().contains(&json!(0)));
    assert!(e.state()["live"]["applied"]["0"].is_null());
    let disk: Value =
        serde_json::from_slice(&std::fs::read(d.path().join("settings.json")).unwrap()).unwrap();
    assert_eq!(disk["keys"][0], key);
}
#[test]
fn discard_while_uploading_restores_saved_profile_after_first_ack() {
    let (_d, mut e) = setup();
    live(&mut e);
    edit(&mut e, 30.0);
    e.advance_performance();
    call(&mut e, "live_mode", json!({"enabled":false}));
    call(&mut e, "live_discard", json!({"index":0}));
    ack(&mut e);
    assert_eq!(e.state()["live"]["pending"], json!([0]));
    e.advance_performance();
    ack(&mut e);
    assert!(e.state()["live"]["applied"]["0"].is_null());
    assert!(e.state()["synced"].as_array().unwrap().contains(&json!(0)));
    assert_eq!(e.state()["live"]["enabled"], false);
}
#[test]
fn failed_live_ack_stops_queue_and_keeps_failed_key_unconfirmed() {
    let (_d, mut e) = setup();
    live(&mut e);
    edit(&mut e, 30.0);
    e.advance_performance();
    edit(&mut e, 40.0);
    e.handle_event(Event::TransferError("ACK timeout".into()))
        .unwrap();
    ack(&mut e);
    assert_eq!(e.state()["live"]["enabled"], false);
    assert_eq!(e.state()["live"]["pending"], json!([]));
    assert_eq!(e.state()["live"]["error"], "ACK timeout");
    assert!(!e.state()["synced"].as_array().unwrap().contains(&json!(0)));
    assert!(e.state()["live"]["applied"]["0"].is_null());
}
#[test]
fn live_volume_is_latest_only_bounded_and_does_not_write_settings() {
    let (_d, mut e) = setup();
    let saved = e.config.clone();
    for volume in [20, 30, 40] {
        call(&mut e, "set_live_volume", json!({"volume":volume}));
    }
    e.advance_performance();
    assert_eq!(frames(&e, 3).len(), 1);
    let f = frames(&e, 3).pop().unwrap();
    assert_eq!(f[5], 0x66);
    assert_eq!(f[6], 0x66);
    call(&mut e, "set_live_volume", json!({"volume":50}));
    e.tick();
    assert_eq!(frames(&e, 3).len(), 1);
    e.test_midi(&[0xb0, 7, 127]);
    e.advance_performance();
    assert_eq!(frames(&e, 3).len(), 2);
    assert_eq!(e.state()["performance"]["volume"], 100.0);
    assert_eq!(e.config, saved);
    assert_eq!(e.state()["revision"], 0);
}
#[test]
fn real_time_mode_rejects_unavailable_resources_and_disconnect_clears_transients() {
    let (_d, mut e) = setup();
    live(&mut e);
    let mut profile = e.config["keys"][0]["synth"].clone();
    profile["wave_a"] = json!("自定义波表");
    assert!(
        e.dispatch("live_edit", json!({"index":0,"profile":profile}))
            .is_err()
    );
    edit(&mut e, 30.0);
    let key = e.config["keys"][0].clone();
    assert!(
        e.dispatch("save_key", json!({"index":0,"key":key}))
            .is_err()
    );
    pedal(&mut e, true);
    call(&mut e, "disconnect", json!({}));
    assert_eq!(e.state()["live"]["enabled"], false);
    assert_eq!(e.state()["live"]["pending"], json!([]));
    assert_eq!(e.state()["performance"]["sustain"], false);
    assert!(e.dispatch("set_live_volume", json!({"volume":40})).is_err());
}
