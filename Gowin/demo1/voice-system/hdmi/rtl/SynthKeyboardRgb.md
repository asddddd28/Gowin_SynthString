# SynthKeyboardRgb

50 MHz keyboard RGB adapter. Reuses the board-validated `HardwareKeyLightEffects`
and `LedFrameTx` from demo_test. Does not scan keys or stall the audio engine.

- Input: synchronous 32-bit debounced physical pressed mask. Only rising edges
  trigger lights; calibration suppresses events and clears active effects.
- Output: R19 / CN1.1, 32 WS2812 LEDs, row-major 4 × 8, 24-bit GRB.
- Refresh: 50 Hz; bit period 63 cycles; high time 15/42 cycles for zero/one.
  Default peak channel value 32/255. Inter-frame low exceeds reset time.
- Modes: 0 off, 1 individual key, 2 ripple, 3 sweep, 4 cross, 6 rainbow flow.
  Sweep direction 0 horizontal, 1 vertical. Default mode 1, direction 0.
- Requests arrive through the existing display command path (target 3).
  0x18 query requires zero argument and words. Payload words: `RGB1`,
  mode | direction << 8, ABI 0x00010000, physical pressed mask.
  0x19 set: argument=mode, words[0]=direction. Other bits must be zero.
  Status 5 rejects invalid requests without mutation. Response valid follows
  each request by one clock; upstream transport owns retry deduplication.
- Configuration applies to the next frame; valid mode changes clear effects.
  Current settings remain in FPGA registers across App disconnect, reset to
  defaults after FPGA reset. SD storage is not required or accessed.

Validation: `hdmi/sim/tb_keyboard_rgb.v` checks real output pulse widths,
held/released keys, calibration, supported modes and rejected requests.
The reused effect reference-model regression separately checks pixel colors.
