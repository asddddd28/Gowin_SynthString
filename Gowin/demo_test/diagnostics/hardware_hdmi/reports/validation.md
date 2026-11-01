# HDMI dashboard validation — 2026-11-01

## Implemented and downloaded

- `hardware_hdmi.fs` was built with Gowin V1.9.11.03 Education for
  GW5AT-LV60PG484AC1/I0 and downloaded to SRAM through USB Debugger A.
- Programmer reports Finished, User Code **0x89B5**, Status **0x76026238**.
- SHA-256: `cae3436f173edcbfd88775a8c2cb458f1cb8132a56d23827d3fe8503ead6873f`.
- No external flash programming or SRAM full readback was performed.
- User explicitly authorized temporary replacement of the synthesizer firmware.
  TangSynthStudio was closed gracefully to release COM4. Its baseline 0x180A
  bitstream remains available at the path recorded in README.

## Functional and implementation evidence

- `sim/run.log`: PASS for the UART receiver, displayed telemetry decoding,
  malformed/overflow recovery, stale timeout, full raster counts, blanking and
  defined active RGB. Final xsim run exited normally with code 0.
- `reports/rtl-preview.png`: converted from the actual RTL-generated PPM,
  using synthetic verification data. This is not a photograph of the monitor.
- An earlier xsim run completed assertions but crashed during tool shutdown;
  the final runs completed and exited successfully. The earlier crash dump
  remains in `sim/hs_err_pid71836.log`.
- Final Gowin placement/routing: **no timing violations**. Worst setup slack
  +0.122 ns; worst reported hold slack +0.071 ns. Pixel fMax 73.994 MHz versus
  73.333 MHz required; peripheral fMax 59.164 MHz versus 50 MHz required.
- Resources: logic 15338/59904 (26%), registers 9909/60780 (17%), BSRAM 11/118
  (10%), DSP 9.5/118 (9%).
- Gowin emits PR1014 for a generic-routing segment of `i_clk_d`; the constrained
  design passes timing. Serializer output has no ordinary fabric timing path.
  Physical TMDS and compatibility with the connected monitor were subsequently
  confirmed by the user, as recorded below.
- Strict readable-Verilog skill audit is retained separately in `readable.*`
  and does not pass; it is not substituted for simulation or timing evidence.

## Real serial checks

- `live-first-open.*` preserves the initial buffered capture (1 key sequence
  discontinuity and 2 encoder parsing errors). No bridge reboot was needed.
- `live_validation.json`/`live_serial.bin`: after a one-second startup drain
  and LF alignment, 8.125-second passive capture received all 32 keys,
  2561 key values, 401 encoder frames, 160 joystick frames, 160 touch frames,
  160 guitar frames, 32 identities, 80 status frames and 80 game frames.
  All recorded protocol/sequence error counters are zero. The script sent no
  bytes and did not change calibration or modes.
- TangHardwareLab App was then started on COM4. `app-live.json` confirms live
  connection, capability 127, configured=true, generation=1 and effect=4.
  Initial App errors were zero; at about 123 seconds its cumulative count was
  1 (106 discarded bytes), with sequence_errors=0 and all 40 inputs fresh.
  That isolated App parse error has not been attributed to a specific cause;
  the separate eight-second raw capture above remains error-free. Calibration
  file hash remained
  `b369177f98a3a3292556fbe6de1efb4f4400f8a0d905d0478be2f33d5cd2c079`.

## Physical screen confirmation

On 2026-11-01, the user confirmed: “画面正常，数据和高亮会变化”
(picture is normal, data and highlights change). This completes the initial
HDMI picture and live-update check on the connected monitor. The evidence is
the user's direct observation, separate from simulation, JTAG and UART checks;
it does not establish compatibility with other monitors or exhaustive per-input
verification. No audio waveform/FFT or HDMI audio is implemented; the plotted
signal is K01 keyboard ADC. The current SRAM firmware is retained.
