# Tang Mega 60K HDMI hardware dashboard

Independent project for the existing comprehensive peripheral debug firmware. All
shared `hardware_lab` RTL is referenced directly. No CPU, instruction memory,
software graphics stack, DDR controller, or full-screen framebuffer is used.

## Six-switch integration (2026-11-02)

The current build includes SW1..SW6 alongside all existing peripherals. It emits
H1 capabilities 0x00FF / build 0x0101 and 10 Hz B1 snapshots. Use the updated
Rust/Tauri App; the HDMI layout remains unchanged and ignores B1. The App shows
switch states/counters and 46 total input channels. This round leaves RGB off.
Current evidence: `../hardware_lab/reports/buttons_merge/validation.md`.
The User Code 0x89B5 board test below refers to the previous HDMI build.

## Display

- 1280 × 720, positive sync, total 1650 × 750 pixels.
- Uses the official Sipeed `cam_dvi` TMDS PLL and Gowin DVI transmitter.
- The **actual** reference PLL output is 73.333333 MHz / 366.666667 MHz, giving
  59.259259 Hz. The timing constraints deliberately match that rate, rather than
  the nominal 74.25 MHz used in the example's SDC.
- 32 key ADC values (hexadecimal), calibrated pressed-key highlights, five
  encoder counts (16-bit two's-complement hex), joystick and switch, two 5 × 7
  touch grids, calibration/effect/link status.
- Both pad electrode maps are transposed, matching the current App default.
- Bottom-right plot is **K01 raw keyboard ADC**, 64 samples at approximately
  10 samples/second. It is not an audio waveform or FFT spectrum.
- HDMI connector carries DVI-compatible video only; no HDMI audio or EDID
  negotiation. The connected screen has been confirmed to display this 720p
  timing correctly; other monitor models have not been tested.

## Architecture and boundaries

`HardwareLab` runs at the original 50 MHz. A second `UartRx` observes its TX net
inside the FPGA at the pixel clock; its two-flop input synchronizer is the only
data CDC into the display. There is no external loopback wiring and the display
does not transmit UART commands. The existing App protocol remains unchanged.

`DashboardTelemetry` stages a line until LF and checks length, delimiters and
displayed numeric fields. Because its source is trusted local RTL, it does not
recheck telemetry CRC; it must not be repurposed as an external command parser.
Key-bank writes use a registered address/data stage and commit one clock after
the complete line is accepted. This keeps decimal key decoding off the bank's
write-enable path.
An overflow discards the line, and newline restores parsing. Recognized-frame
inactivity of one second clears LINK. Individual stale fields retain their last
values; LINK reflects the aggregate stream, not per-sensor freshness. Touch
error status is shown with a muted red pad.

`DashboardVideo` snapshots values in vertical blank and pipelines geometry,
text ROM/font lookup, and RGB with matching sync delays. The small ADC history
is continuously updated; its read origin is latched at vertical blank. The
layout ROM contains 4096 bytes and the original font is a 5 × 7 ASCII bitmap.
The vendor DVI core uses the official example's asynchronous reset (`i_rstn`
AND PLL lock), independently of the dashboard's synchronized pixel reset.

The existing calibration remains owned by Tang Hardware Lab App. Start that
App to resend its saved calibration after SRAM download. Do not use the old
`TangKeyboardLab` profile, which may differ from the current Tauri calibration.

## Build and verify

From this directory:

```powershell
python prepare_assets.py
python spec/semantic_model.py
python prepare_sim.py
& 'C:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' build.tcl
```

Simulation uses the local Vivado 2025.1 `xvlog`, `xelab`, and `xsim` commands in
`sim/`. `sim/compile.f` lists only unencrypted dashboard logic and the UART RX.
The vendor PLL/serializer and physical TMDS electrical output are verified by
Gowin implementation and the real monitor, not behavioral stubs.

The self-checking bench checks actual UART baud sampling, key/encoder/joystick/
touch/status parsing, malformed/overflow recovery, inactivity timeout, black
blanking, 921600 active pixels, HS/VS widths and unknown RGB. It saves the RTL
frame to `sim/frame.ppm`; `reports/rtl-preview.png` is converted from that frame.

`reports/readable.*` records the strict style-skill audit. It does **not** pass
the skill's complete packaging/naming/style gates; no claim of full strict
style certification is made. Functional simulation and Gowin timing reports
are recorded separately. First synthesis exposed a long coordinate division
path; it was replaced with fixed text-cell decode before final implementation.

Do not run `optimize_text.py` again: it is the retained one-time source migration
record. `prepare_assets.py` regenerates assets/contracts/project but preserves
the handwritten RTL. Paths currently target this workspace.

## Board testing

Only SRAM programming is intended. The project does not update external flash,
debugger firmware, external clock configuration, Windows drivers, or App files.
The board was observed running a separate synthesizer firmware (User Code
0x180A) with TangSynthStudio. The user explicitly chose to switch temporarily
to this HDMI debug firmware to validate the screen. The retained rollback file
is `Gowin/demo1/keyboard-parallel/baseline/Studio_180A.fs` (SHA-256:
`f44b5e1e65ca5fb407c65a79a3b5207483f5cc4cff5002640dee95d77001a5e4`).

The HDMI build has now passed simulation and final Gowin timing and was loaded
to SRAM (User Code 0x89B5). Tang Hardware Lab has reconnected and restored the
saved calibration and effect 4. On 2026-11-01 the user confirmed the actual HDMI
picture is normal and the displayed data and highlights change with input.
See `reports/validation.md` for measured results, direct screen confirmation
and test limitations.
