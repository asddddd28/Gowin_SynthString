use serde_json::{json, Value};
use tang_hardware_lab::{
    calibration::Profile,
    model::{Model, Settings},
    protocol::{self, Frame, Parser},
};

#[test]
fn every_split_size_matches_previous_app_and_real_capture() {
    let data = include_bytes!("fixtures/hardware_live.bin");
    let expected: Value = serde_json::from_str(include_str!("fixtures/expected.json")).unwrap();
    for chunk in [1, 2, 7, 31, 128, 4096, data.len()] {
        let mut parser = Parser::default();
        let mut model = Model::new(Profile::default(), Settings::default());
        for part in data.chunks(chunk) {
            for frame in parser.feed(part) {
                model.frame(frame, 1.);
            }
        }
        assert_eq!(
            json!(parser.counts),
            expected["counts"],
            "chunk size {chunk}"
        );
        assert_eq!(parser.errors, 0);
        assert_eq!(parser.discarded, 0);
        assert_eq!(
            json!(model.view.keys.iter().map(|k| k.raw).collect::<Vec<_>>()),
            expected["keys"]
        );
        assert_eq!(
            serde_json::to_value(&model.view.board).unwrap(),
            expected["status"]
        );
        assert_eq!(
            serde_json::to_value(&model.view.joystick.record).unwrap(),
            expected["joystick"]
        );
        assert_eq!(model.view.protocol, "hub");
        assert_eq!(model.view.sequence_errors, 0);
        for pad in expected["pads"].as_array().unwrap() {
            let i = pad["board"].as_u64().unwrap() as usize - 1;
            let r = serde_json::to_value(&model.view.pads[i].record).unwrap();
            for key in ["mask", "filtered", "baseline", "delta", "error"] {
                assert_eq!(r[key], pad[key]);
            }
        }
        for r in expected["encoders"].as_array().unwrap() {
            let i = r["channel"].as_u64().unwrap() as usize - 1;
            assert_eq!(
                serde_json::to_value(&model.view.encoders[i].record).unwrap(),
                *r
            );
        }
        for r in expected["guitar"].as_array().unwrap() {
            let i = r["board"].as_u64().unwrap() as usize - 1;
            assert_eq!(
                serde_json::to_value(&model.view.guitar.records[i]).unwrap(),
                *r
            );
        }
    }
}
#[test]
fn calibration_command_bytes_match_legacy_including_rounding() {
    let profile: Profile =
        serde_json::from_str(include_str!("fixtures/legacy_calibration.json")).unwrap();
    let expected: Vec<String> =
        serde_json::from_str(include_str!("fixtures/commands.json")).unwrap();
    let commands = profile.commands().unwrap();
    assert_eq!(commands.len(), 34);
    for (i, cmd) in commands.iter().enumerate() {
        assert_eq!(String::from_utf8(cmd.encode(i as u8)).unwrap(), expected[i]);
        assert!(cmd
            .encode(i as u8)
            .iter()
            .all(|c| *c == b'\n' || (32..=126).contains(c)));
    }
}
#[test]
fn bad_crc_unsupported_identity_noise_and_partial_line_recover() {
    let valid = b"H1007F0100*66\r\n";
    assert!(matches!(protocol::decode(valid), Some(Frame::Identity(_))));
    let mut invalid = *valid;
    invalid[11] = b'7';
    assert!(protocol::decode(&invalid).is_none());
    let mut parser = Parser::default();
    assert!(parser.feed(b"noise").is_empty());
    assert_eq!(parser.feed(valid).len(), 1);
    assert_eq!(parser.discarded, 5);
    assert!(parser.feed(&invalid).is_empty());
    assert_eq!(parser.errors, 1);
    assert_eq!(parser.feed(valid).len(), 1);
    let body = b"H1007F0200";
    let packet = format!(
        "{}*{:02X}\r\n",
        std::str::from_utf8(body).unwrap(),
        protocol::crc8(body)
    );
    assert!(protocol::decode(packet.as_bytes()).is_none());
    assert!(parser.feed(&vec![b'X'; 1000]).is_empty());
    assert_eq!(parser.feed(valid).len(), 1);
}
#[test]
fn range_errors_never_reach_model() {
    for line in [
        b"K00:FFF\r\n".as_slice(),
        b"K33:FFF\r\n",
        b"K01:fff\r\n",
        b"J0000 R20 F00 P0000\r\n",
        b"E1 A3 F3 Q0001 P0000 N0000 X0000\r\n",
    ] {
        assert!(protocol::decode(line).is_none());
    }
}

#[test]
fn opening_mid_frame_does_not_count_a_transport_error() {
    let mut p = Parser::default();
    assert!(p.feed(b"ABC\r\n").is_empty());
    assert_eq!(p.errors, 0);
    assert_eq!(p.discarded, 5);
    assert_eq!(p.feed(b"K01:ABC\r\n").len(), 1);
    assert!(p.feed(b"K02:XXZ\r\n").is_empty());
    assert_eq!(p.errors, 1);
}
