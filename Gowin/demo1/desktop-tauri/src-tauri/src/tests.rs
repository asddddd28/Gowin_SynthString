use crate::{
    engine::Engine,
    model,
    protocol::{self, Kind, Transfer},
    resources,
    surge::{self, Snapshot},
    transport::Event,
};
use serde_json::{Value, json};
use std::{
    fs,
    path::{Path, PathBuf},
};
fn assets() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets")
}
fn vectors() -> Value {
    serde_json::from_str(include_str!("../tests/fixtures/legacy-vectors.json")).unwrap()
}
fn setup() -> (tempfile::TempDir, Engine) {
    let temp = tempfile::tempdir().unwrap();
    let e = Engine::new(&assets(), Some(temp.path().join("settings.json"))).unwrap();
    (temp, e)
}
fn call(e: &mut Engine, method: &str, params: Value) -> Value {
    e.dispatch(method, params).unwrap()
}
fn frames(e: &Engine, op: u8) -> usize {
    e.test_frames()
        .as_array()
        .unwrap()
        .iter()
        .filter(|f| f[1] == op)
        .count()
}
#[test]
fn profile_words_match_223_legacy_profiles() {
    for row in vectors()["profiles"].as_array().unwrap() {
        assert_eq!(json!(model::words(&row["profile"]).unwrap()), row["words"]);
    }
}
#[test]
fn global_packets_match_20_legacy_cases() {
    for row in vectors()["sounds"].as_array().unwrap() {
        assert_eq!(json!(protocol::sound_packets(&row["sound"])), row["frames"]);
    }
}
#[test]
fn defaults_migrate_without_changing_mapping() {
    let mut expected = vectors()["defaults"].clone();
    expected["tauri_bindings"] = json!({});
    assert_eq!(model::defaults(), expected);
    let mut old = expected.clone();
    old["version"] = json!(1);
    old["keys"][0].as_object_mut().unwrap().remove("synth");
    assert_eq!(model::validate_config(old).unwrap(), expected);
}
#[test]
fn transfers_match_legacy_transcripts_byte_for_byte() {
    for case in vectors()["transfers"].as_array().unwrap() {
        let token = case["token"].as_u64().unwrap() as u16;
        let mut t = match case["kind"].as_str().unwrap() {
            "table" | "pair" => {
                let f: Vec<Vec<i16>> = serde_json::from_value(case["init"].clone()).unwrap();
                Transfer::table(&f, 0.0, token).unwrap()
            }
            "pcm" => {
                let i = &case["init"];
                let s = resources::samples(&i["samples"], 512, 16384).unwrap();
                Transfer::pcm(
                    [
                        s.len() as u16,
                        i["loop_start"].as_u64().unwrap() as u16,
                        i["loop_end"].as_u64().unwrap() as u16,
                        i["root_note"].as_u64().unwrap() as u16,
                    ],
                    s,
                    0.0,
                    token,
                )
                .unwrap()
            }
            _ => {
                let p: Vec<(u8, Value)> = serde_json::from_value(case["init"].clone()).unwrap();
                Transfer::profiles(&p, 0.0, token).unwrap()
            }
        };
        for (i, step) in case["steps"].as_array().unwrap().iter().enumerate() {
            let out = t.advance(
                step["now"].as_f64().unwrap(),
                if step["status"].is_null() {
                    None
                } else {
                    Some(&step["status"])
                },
            );
            assert_eq!(json!(out), step["frames"], "{} step {i}", case["kind"]);
            assert_eq!(json!(t.count), step["count"]);
            assert_eq!(json!(t.done), step["done"]);
            assert_eq!(json!(t.error.is_some()), step["error"]);
        }
    }
}
#[test]
fn piano_and_library_pairs_match_legacy() {
    let v = vectors();
    assert_eq!(json!(resources::piano_table()), v["piano"]);
    let lib = resources::load_library(&assets().join("wavetable_library")).unwrap();
    for row in v["pairs"].as_array().unwrap() {
        let (frames, job) = lib[row["index"].as_u64().unwrap() as usize]
            .pair(row["position"].as_f64().unwrap())
            .unwrap();
        assert_eq!(json!(frames), row["frames"]);
        assert_eq!(job, row["job"]);
    }
}
#[test]
fn parser_handles_noise_crc_corruption_and_arbitrary_fragmentation() {
    let mut frame = [0u8; 16];
    frame[0] = 0xa5;
    frame[1] = 0x86;
    frame[2] = 3;
    frame[3] = 3;
    frame[12] = 128 | 31;
    frame[13] = 0x34;
    frame[14] = 0x12;
    frame[15] = frame[..15].iter().fold(0, |a, b| a ^ b);
    let mut corrupt = frame;
    corrupt[6] ^= 1;
    let mut raw = vec![1, 2, 0xa5, 0x80, 5];
    raw.extend(corrupt);
    raw.extend(frame);
    raw.extend(frame);
    for chunk in 1..=33 {
        let mut parser = protocol::Parser::default();
        let out: Vec<_> = raw.chunks(chunk).flat_map(|b| parser.feed(b)).collect();
        assert_eq!(out.len(), 2);
        assert_eq!(out[0]["query_key"], 63);
        assert_eq!(out[0]["frame_position"], 0x1234);
        assert_eq!(out[0]["pair_capable"], true);
    }
}
#[test]
fn invalid_config_is_rejected_without_mutation() {
    let (tmp, mut e) = setup();
    let original = e.config.clone();
    let mut k = e.config["keys"][0].clone();
    k["keycode"] = e.config["keys"][1]["keycode"].clone();
    assert!(
        e.dispatch("save_key", json!({"index":0,"key":k}))
            .unwrap_err()
            .contains("快捷键不能重复")
    );
    assert_eq!(e.config, original);
    assert!(!tmp.path().join("settings.json").exists());
    for value in [json!(true), json!("12"), json!(-1), json!(101), Value::Null] {
        assert!(
            e.dispatch("set_output", json!({"volume":value,"boost":0}))
                .is_err()
        );
        assert_eq!(e.config, original);
    }
    assert!(
        e.dispatch("save_key", json!({"index":0,"key":null}))
            .is_err()
    );
}
#[test]
fn atomic_save_preserves_memory_on_filesystem_failure() {
    let (tmp, mut e) = setup();
    let original = e.config.clone();
    fs::create_dir(tmp.path().join("settings.json")).unwrap();
    assert!(
        e.dispatch("set_output", json!({"volume":37,"boost":2}))
            .is_err()
    );
    assert_eq!(e.config, original);
    assert_eq!(e.state()["revision"], 0);
    assert_eq!(fs::read_dir(tmp.path()).unwrap().count(), 1);
}
#[test]
fn save_replaces_existing_file_and_reloads_unicode() {
    let (tmp, mut e) = setup();
    let mut k = e.config["keys"][0].clone();
    k["name"] = json!("我的贝斯 🎹");
    call(&mut e, "save_key", json!({"index":0,"key":k}));
    call(&mut e, "set_output", json!({"volume":37,"boost":2}));
    let loaded = Engine::new(&assets(), Some(tmp.path().join("settings.json"))).unwrap();
    assert_eq!(loaded.config, e.config);
    assert_eq!(loaded.config["keys"][1]["name"], "KEY 02");
}
#[test]
fn notes_require_ack_and_release_only_after_last_owner() {
    let (_temp, mut e) = setup();
    assert!(
        e.dispatch("note_on", json!({"index":0,"owner":"keyboard"}))
            .is_err()
    );
    e.test_connect();
    call(&mut e, "note_on", json!({"index":0,"owner":"keyboard"}));
    call(&mut e, "note_on", json!({"index":0,"owner":"keyboard"}));
    call(&mut e, "note_on", json!({"index":0,"owner":"mouse"}));
    assert_eq!(frames(&e, 1), 1);
    call(&mut e, "note_off", json!({"index":0,"owner":"keyboard"}));
    assert_eq!(frames(&e, 2), 0);
    call(&mut e, "note_off", json!({"index":0,"owner":"mouse"}));
    assert_eq!(frames(&e, 2), 1);
    let k = e.config["keys"][0].clone();
    call(&mut e, "save_key", json!({"index":0,"key":k}));
    assert!(
        e.dispatch("note_on", json!({"index":0,"owner":"mouse"}))
            .is_err()
    );
}
#[test]
fn watchdog_releases_notes_without_ui_polling() {
    let (_temp, mut e) = setup();
    e.test_connect();
    call(&mut e, "note_on", json!({"index":0,"owner":"keyboard"}));
    e.expire_ui();
    e.tick();
    assert_eq!(frames(&e, 2), 1);
    assert_eq!(e.state()["held"], json!([]));
}
#[test]
fn wave_commit_then_profile_commit_are_both_required() {
    let (_temp, mut e) = setup();
    e.test_connect();
    let original = e.config.clone();
    call(
        &mut e,
        "upload_wave",
        json!({"index":2,"resource_id":0,"position":75}),
    );
    assert_eq!(e.config, original);
    assert!(
        e.dispatch("note_on", json!({"index":2,"owner":"mouse"}))
            .is_err()
    );
    e.handle_event(Event::Done(Kind::Pair)).unwrap();
    assert_eq!(e.config["keys"][2]["synth"]["wave_a"], model::CUSTOM);
    assert_eq!(e.state()["transfer"], "profiles");
    assert!(!e.state()["synced"].as_array().unwrap().contains(&json!(2)));
    e.handle_event(Event::Done(Kind::Profiles)).unwrap();
    call(&mut e, "note_on", json!({"index":2,"owner":"mouse"}));
    assert_eq!(frames(&e, 1), 1);
    assert_eq!(e.config["keys"][0], original["keys"][0]);
}
#[test]
fn failed_wave_or_late_ack_does_not_change_configuration() {
    let (_temp, mut e) = setup();
    e.test_connect();
    let original = e.config.clone();
    call(
        &mut e,
        "upload_wave",
        json!({"index":3,"resource_id":0,"position":50}),
    );
    e.handle_event(Event::TransferError("CRC".into())).unwrap();
    e.handle_event(Event::Done(Kind::Pair)).unwrap();
    assert_eq!(e.config, original);
    assert!(e.state()["active_resource"].is_null());
}
#[test]
fn resource_ack_save_failure_never_confirms_key() {
    let (tmp, mut e) = setup();
    e.test_connect();
    call(
        &mut e,
        "upload_wave",
        json!({"index":0,"resource_id":0,"position":25}),
    );
    fs::create_dir(tmp.path().join("settings.json")).unwrap();
    let original = e.config.clone();
    assert!(e.handle_event(Event::Done(Kind::Pair)).is_err());
    assert_eq!(e.config, original);
    assert_eq!(e.state()["transfer"], Value::Null);
}
#[test]
fn custom_bank_bindings_persist_and_conflicting_shared_resources_reject() {
    let (tmp, mut e) = setup();
    let catalog = call(&mut e, "bank_catalog", json!({}));
    let ids: Vec<_> = catalog
        .as_array()
        .unwrap()
        .iter()
        .filter(|v| !v["resource_id"].is_null())
        .map(|v| v["id"].clone())
        .collect();
    call(&mut e, "load_preset", json!({"index":0,"timbre_id":ids[0]}));
    call(&mut e, "load_preset", json!({"index":1,"timbre_id":ids[1]}));
    let mut e = Engine::new(&assets(), Some(tmp.path().join("settings.json"))).unwrap();
    e.test_connect();
    assert!(e.dispatch("sync", json!({"indices":[0,1]})).is_err());
    call(&mut e, "sync", json!({"indices":[0]}));
    assert_eq!(e.state()["transfer"], "wavetable");
    e.handle_event(Event::Done(Kind::Pair)).unwrap();
    e.handle_event(Event::Done(Kind::Profiles)).unwrap();
    call(&mut e, "note_on", json!({"index":0,"owner":"keyboard"}));
    call(&mut e, "sync", json!({"indices":[1]}));
    assert!(!e.state()["synced"].as_array().unwrap().contains(&json!(0)));
    e.handle_event(Event::Done(Kind::Pair)).unwrap();
    e.handle_event(Event::Done(Kind::Profiles)).unwrap();
    assert!(
        e.dispatch("note_on", json!({"index":0,"owner":"mouse"}))
            .is_err()
    );
}
#[test]
fn output_changes_preserve_per_key_profiles() {
    let (_temp, mut e) = setup();
    let keys = e.config["keys"].clone();
    call(&mut e, "set_output", json!({"volume":37,"boost":2}));
    assert_eq!(e.config["keys"], keys);
}
#[test]
fn disconnect_and_panic_upload_clear_transient_state() {
    let (_temp, mut e) = setup();
    e.test_connect();
    call(
        &mut e,
        "upload_wave",
        json!({"index":0,"resource_id":0,"position":0}),
    );
    call(&mut e, "panic", json!({}));
    let s = e.state();
    assert_eq!(s["online"], false);
    assert_eq!(s["synced"], json!([]));
    assert!(s["transfer"].is_null());
    assert!(s["active_resource"].is_null());
}
fn copy_folder(from: &Path, to: &Path) {
    fs::create_dir_all(to).unwrap();
    for e in fs::read_dir(from).unwrap() {
        let e = e.unwrap();
        if e.file_type().unwrap().is_dir() {
            copy_folder(&e.path(), &to.join(e.file_name()));
        } else {
            fs::copy(e.path(), to.join(e.file_name())).unwrap();
        }
    }
}
#[test]
fn corrupted_index_resource_and_preview_are_rejected() {
    let temp = tempfile::tempdir().unwrap();
    let folder = temp.path();
    copy_folder(&assets().join("basic_bank"), folder);
    for name in ["TSINDEX.BIN", "00000101.BIN", "P0000001.WAV"] {
        let path = folder.join(name);
        let original = fs::read(&path).unwrap();
        let mut bad = original.clone();
        let i = bad.len() - 1;
        bad[i] ^= 1;
        fs::write(&path, bad).unwrap();
        assert!(resources::load_bank(folder).is_err(), "{name}");
        fs::write(path, original).unwrap();
    }
    assert_eq!(resources::load_bank(folder).unwrap().len(), 16);
}
#[test]
fn wavetable_binary_boundaries_and_nan_rejected() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("test.wt");
    let mut raw = b"vawt".to_vec();
    raw.extend(16u32.to_le_bytes());
    raw.extend(1u16.to_le_bytes());
    raw.extend(0u16.to_le_bytes());
    for _ in 0..16 {
        raw.extend(0.25f32.to_le_bytes());
    }
    fs::write(&path, &raw).unwrap();
    assert!(
        resources::load_surge(&path).unwrap()[0]
            .iter()
            .all(|v| *v == 8192)
    );
    raw[12..16].copy_from_slice(&f32::NAN.to_le_bytes());
    fs::write(&path, raw).unwrap();
    assert!(resources::load_surge(&path).is_err());
    let good = resources::encode_bank(&[vec![0; 1024]]).unwrap();
    for end in 0..good.len() {
        if end > 40 && end % 31 != 0 {
            continue;
        }
        assert!(resources::Resource::decode(1, 1, "x".into(), &good[..end]).is_err());
    }
}
#[test]
fn pcm_rejects_boolean_sample_bad_loop_and_oversized_input() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("sample.json");
    let mut v = json!({"format":"tang-pcm-v1","sample_rate":24000,"samples":vec![0;512],"loop_start":0,"loop_end":512,"root_note":60});
    fs::write(&path, v.to_string()).unwrap();
    assert!(resources::load_pcm(&path).is_ok());
    v["samples"][0] = json!(true);
    fs::write(&path, v.to_string()).unwrap();
    assert!(resources::load_pcm(&path).is_err());
    v["samples"][0] = json!(0);
    v["loop_start"] = json!(1);
    fs::write(&path, v.to_string()).unwrap();
    assert!(resources::load_pcm(&path).is_err());
    fs::write(&path, vec![0; 1024 * 1024 + 1]).unwrap();
    assert!(resources::load_pcm(&path).is_err());
}
fn snapshot() -> Snapshot {
    let mut s = Snapshot::default();
    for (f, v, lo, hi) in [
        ("attack", 0.0, -8, 5),
        ("decay", 8.0 / 13.0, -8, 5),
        ("sustain", 0.7, 0, 1),
        ("release", 6.0 / 13.0, -8, 5),
    ] {
        let a = format!("/param/a/aeg/{f}");
        s.feed(&a, &[json!(v)]).unwrap();
        s.feed(
            &format!("/doc{a}"),
            &[
                json!(f),
                json!("float"),
                json!(lo.to_string()),
                json!(hi.to_string()),
            ],
        )
        .unwrap();
        if f != "sustain" {
            s.feed(&format!("{a}/tempo_sync+"), &[json!(0)]).unwrap();
        }
    }
    s.feed("/param/a/aeg/release/deform+", &[json!(0)]).unwrap();
    s
}
#[test]
fn surge_mapping_preserves_oscillators_and_rejects_unsupported_options() {
    let original = model::defaults()["keys"][0]["synth"].clone();
    let mut s = snapshot();
    let mapped = s.map_envelope(&original, "a").unwrap();
    assert_eq!(mapped["attack"], 0.0);
    assert!((mapped["decay"].as_f64().unwrap() - 1000.0).abs() < 1e-8);
    assert_eq!(mapped["wave_a"], original["wave_a"]);
    assert_eq!(mapped["m_decay"], original["m_decay"]);
    let restored = Snapshot::load(&s.export()).unwrap();
    assert_eq!(restored.parameters, s.parameters);
    s.feed("/param/a/aeg/attack/tempo_sync+", &[json!(1)])
        .unwrap();
    assert!(s.map_envelope(&original, "a").is_err());
    s.feed("/patch/load", &[json!("新音色")]).unwrap();
    assert!(s.parameters.is_empty());
    assert!(s.docs.is_empty());
}
#[test]
fn osc_codec_rejects_truncation_padding_and_floods() {
    let mut raw = surge::osc_string("/param/a/aeg/attack");
    raw.extend(surge::osc_string(",fs"));
    raw.extend(0.25f32.to_be_bytes());
    raw.extend(surge::osc_string("四分之一"));
    let good = surge::decode(&raw, 0).unwrap();
    assert_eq!(good[0].1[0], 0.25);
    for end in 0..raw.len() {
        assert!(surge::decode(&raw[..end], 0).is_err());
    }
    let mut invalid = raw.clone();
    invalid.push(0);
    assert!(surge::decode(&invalid, 0).is_err());
    let mut bundle = b"#bundle\0".to_vec();
    bundle.extend([0; 8]);
    bundle.extend((raw.len() as i32).to_be_bytes());
    bundle.extend(&raw);
    assert_eq!(surge::decode(&bundle, 0).unwrap(), good);
    assert!(surge::decode(&bundle, 9).is_err());
}
#[test]
fn real_loopback_osc_queries_and_receives_without_parameter_writes() {
    use std::{net::UdpSocket, time::Duration};
    let server = UdpSocket::bind("127.0.0.1:0").unwrap();
    server
        .set_read_timeout(Some(Duration::from_secs(1)))
        .unwrap();
    let reserved = UdpSocket::bind("127.0.0.1:0").unwrap();
    let output = reserved.local_addr().unwrap().port();
    drop(reserved);
    let link = surge::Connection::open(server.local_addr().unwrap().port(), output).unwrap();
    let mut b = [0; 1024];
    let (n, peer) = server.recv_from(&mut b).unwrap();
    assert_eq!(
        surge::decode(&b[..n], 0).unwrap(),
        vec![("/q/all_params".into(), vec![])]
    );
    let mut packet = surge::osc_string("/param/a/aeg/attack");
    packet.extend(surge::osc_string(",f"));
    packet.extend(0.25f32.to_be_bytes());
    server.send_to(&packet, peer).unwrap();
    let mut s = Snapshot::default();
    for _ in 0..20 {
        if link.poll(&mut s).unwrap() > 0 {
            break;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(s.parameters["/param/a/aeg/attack"]["value"], 0.25);
}
#[test]
fn bounded_binary_decoders_do_not_panic_on_noise() {
    let mut seed = 17u32;
    for len in 0..2048 {
        let b: Vec<u8> = (0..len)
            .map(|_| {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                (seed >> 24) as u8
            })
            .collect();
        let _ = surge::decode(&b, 0);
        let _ = resources::Resource::decode(1, 1, "x".into(), &b);
        let _ = protocol::Parser::default().feed(&b);
    }
}
