use tang_hardware_lab::{
    calibration::Profile,
    model::{Model, Settings},
    protocol::{crc8, decode, Frame, Parser},
};

fn packet(sequence: u16, raw: u8, filtered: u8) -> Vec<u8> {
    let mut body = format!("B1{sequence:04X}{raw:02X}{filtered:02X}");
    for count in [1,2,3,4,5,6,6,5,4,3,2,1,7,8,9,10,11,65535] {
        body.push_str(&format!("{count:04X}"));
    }
    format!("{body}*{:02X}\r\n", crc8(body.as_bytes())).into_bytes()
}

#[test]
fn switches_decode_real_rtl_uart_at_every_chunk_size() {
    let data = include_bytes!("fixtures/tactile_uart.bin");
    for size in 1..=data.len() {
        let mut parser = Parser::default();
        let mut records = vec![];
        for part in data.chunks(size) {
            for frame in parser.feed(part) {
                if let Frame::Buttons(r) = frame { records.push(r); }
                else { panic!("Wrong protocol"); }
            }
        }
        assert_eq!(parser.errors, 0);
        assert_eq!(records.len(), 3);
        assert_eq!(records[0].raw, 0x15);
        assert_eq!(records[0].filtered, 0x0a);
        assert_eq!(records[1].raw, 63);
        assert_eq!(records[2].sequence, 2);
        for r in records {
            assert_eq!(r.presses, [1,2,3,4,5,6]);
            assert_eq!(r.releases, [6,5,4,3,2,1]);
            assert_eq!(r.edges, [7,8,9,10,11,65535]);
        }
    }
}

#[test]
fn switch_crc_ranges_and_corrupt_frame_recovery() {
    assert!(decode(&packet(0, 64, 0)).is_none());
    assert!(decode(&packet(0, 0, 64)).is_none());
    let good = packet(7, 63, 3);
    let mut corrupt = good.clone();
    corrupt[10] = b'F';
    assert!(decode(&corrupt).is_none());
    let mut parser = Parser::default();
    parser.feed(&good);
    assert!(parser.feed(&corrupt).is_empty());
    assert_eq!(parser.feed(&good).len(), 1);
    assert_eq!(parser.errors, 1);
}

#[test]
fn switch_model_handles_sequence_wrap_and_stale_data() {
    let mut model = Model::new(Profile::default(), Settings::default());
    model.view.connection = "live".into();
    model.frame(decode(&packet(65535, 1, 1)).unwrap(), 1.0);
    model.frame(decode(&packet(0, 0, 0)).unwrap(), 1.02);
    model.tick(1.03);
    assert_eq!(model.view.protocol, "buttons");
    assert_eq!(model.view.sequence_errors, 0);
    assert!(model.view.buttons.fresh);
    assert_eq!(model.view.fresh_count, 6);
    model.tick(2.0);
    assert!(!model.view.buttons.fresh);
    assert_eq!(model.view.fresh_count, 0);
    assert!(model.view.buttons.record.is_some());
    model.reset();
    assert!(model.view.buttons.record.is_none());
}
