use tang_hardware_lab::{
    calibration::Profile,
    model::{Model, Settings},
    protocol::{decode, Frame, Parser},
};

#[test]
fn new_identity_and_buttons_coexist_with_all_original_frame_types() {
    // Actual UART wire output from the combined FPGA simulation, not generated
    // expected frames. Includes calibration commands, touch and keyboard games.
    let bytes = include_bytes!("fixtures/hardware_buttons_uart.bin");
    for size in [1, 7, 32, 87, 256, bytes.len()] {
        let mut parser = Parser::default();
        let mut model = Model::new(Profile::default(), Settings::default());
        model.view.connection = "live".into();
        for chunk in bytes.chunks(size) {
            for frame in parser.feed(chunk) {
                model.frame(frame, 1.0);
            }
        }
        assert_eq!(parser.errors, 0, "chunk {size}");
        assert_eq!(parser.discarded, 0);
        assert!(parser.counts.iter().all(|n| *n > 0), "{:?}", parser.counts);
        assert_eq!(model.view.protocol, "hub");
        let identity = model.view.identity.as_ref().unwrap();
        assert_eq!(identity.capabilities, 255);
        assert_eq!(identity.build, 0x0101);
        let buttons = model.view.buttons.record.as_ref().unwrap();
        assert_eq!(buttons.presses, [1; 6]);
        assert_eq!(buttons.releases, [1; 6]);
        assert_eq!(buttons.filtered, 0);
        assert_eq!(model.view.sequence_errors, 0);
        model.tick(1.1);
        assert_eq!(model.view.fresh_count, 46);
    }
}

#[test]
fn identity_before_or_after_button_packet_keeps_hub_mode() {
    let button = include_bytes!("fixtures/tactile_uart.bin");
    for order in [false, true] {
        let mut model = Model::new(Profile::default(), Settings::default());
        let id = decode(b"H100FF0101*9B\r\n").unwrap();
        let sw = decode(&button[..87]).unwrap();
        assert!(matches!(id, Frame::Identity(_)));
        let frames = if order { [id, sw] } else { [sw, id] };
        for frame in frames { model.frame(frame, 1.); }
        assert_eq!(model.view.protocol, "hub");
        assert_eq!(model.view.identity.as_ref().unwrap().capabilities, 255);
    }
}
