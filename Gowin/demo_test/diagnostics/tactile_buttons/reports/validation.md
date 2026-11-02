# Six-switch validation — 2026-11-02

## Mapping and electrical behavior

User confirmed the original eight-pin switch connector and requested no RGB test.
The spreadsheet incorrectly lists SW2 as AA18. The actual interface schematic
shows AB18; AA18 is a separate pad SCL. The switch schematic connects a pressed
switch to 3.3 V and uses a 10 kΩ pulldown. All six FPGA switch signals are inputs,
with weak pulldowns. No physical rewiring or driver changes were performed.

## Functional evidence

- Independent reference debounce model passed.
- Vivado xsim passed press/release bounce, six-channel mapping, simultaneous
  operation, long hold, counter wrap and reset-held checks. The real UART TX
  generated three frames; an independent Python decoder checked every field,
  CRC, sequence and snapshot isolation.
- Rust tests include actual RTL UART bytes at all 261 split sizes, CRC/range
  rejection, corrupt-frame recovery, sequence wrap, stale-state clearing and
  model reset. The existing hardware capture compatibility test still compares
  the original eight frame categories; the ninth is B1 switches.
- TypeScript/Vite and Tauri release builds passed. Original App executable and
  changed source files are preserved under `baseline/app`.
- Gowin first routing invocation exited with Windows access violation. An
  unchanged retry completed. Final report: 1263 logic, 948 registers, 50 MHz
  constraint, fMax 145.626 MHz, no reported timing violations. The routing log
  contains a generic clock routing warning; the actual timed implementation and
  physical UART were checked separately.

The strict readable-Verilog gate did **not** pass: compact control syntax causes
a formatter-AST failure and there are header, formatting and comment findings.
This is not a claim of full skill certification. External xsim compilation and
simulation, actual Gowin synthesis/routing and physical UART are distinct
evidence; the exported failure summary is `reports/readable-summary.json`; full style reports remain local.

## SRAM and serial

Before download: GW5AT-60B ID 0x0001481B, audio firmware User Code FED2.
New file: `impl/pnr/tactile_buttons.fs`, SHA-256
`f59c66ac3652b2298f4e3d7ce3c962d3a46f5783cf76e29634b8b7283815d6ce`.
SRAM download finished: User Code **5CC2**, Status **76026238**. No external
Flash write or full SRAM readback verification was performed.

First six-second COM4 capture: 298 valid frames, zero CRC/sequence errors,
all six raw/filtered levels low, all press/release/edge counts zero. The App
subsequently recognized B1, displayed six fresh inputs at approximately 50 Hz,
and sent zero UART command bytes. Native UI layout and status were inspected.

Physical per-key validation was captured locally in `guided.jsonl` and
`guided.json` (App diagnostic snapshots, approximately one per second, not a
lossless event trace). The repository exports `guided-summary.json` without personal profiles. Counters reside in FPGA and retain events between GUI
updates. SW2/SW3/SW5/SW6 actions were observed before the guided sequence;
these observations alone do not complete the SW1/SW4 or simultaneous-key check.


2026-11-02 更新：用户修复连接后，App 实际收到全部六键动作；按下与释放计数均为 [8,17,24,32,28,15]，SW1/SW4 不再是零计数。快照存于 ../hardware_lab/reports/buttons_merge/switches_after_repair.json（相对于项目目录）。六键现已并入综合测试和 HDMI 项目，独立六键位流仍保留用于回退。
