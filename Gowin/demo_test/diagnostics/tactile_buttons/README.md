# Six tactile switches — bring-up

Standalone, input-only switch diagnostic for Tang Mega 60K (50 MHz). RGB is held
low and the speaker amplifier disabled. Other peripheral scanning is paused.

## Confirmed wiring

The interface schematic in the 2026-10-23 project archive maps the eight-pin
connector to the following FPGA pins. The spreadsheet has a typo: **SW2 is AB18,
not AA18**. AA18 remains the second touchpad SCL. The switch schematic has a
10 kΩ pulldown and connects the signal to 3.3 V when pressed: active high.

| Switch | Connector pin | FPGA ball |
|---|---:|---|
| SW1 | 8 | AA19 |
| SW2 | 7 | AB18 |
| SW3 | 6 | Y18 |
| SW4 | 5 | N15 |
| SW5 | 4 | U17 |
| SW6 | 3 | P15 |
| Supply / ground | 2 / 1 | 3.3 V / GND |

The initial concern about shared AA18 was resolved by checking the actual
schematic. No physical rewiring is requested.

## Design contract

`TactileInput`: two-stage input synchronization; each switch independently needs
250000 consecutive different samples (5 ms) to change its debounced level.
Press, release and synchronized raw-edge counters are unsigned 16-bit wrapping
counts. Holding a key never repeats a press. A key held through reset is counted
once after the stable window; counters restart on FPGA reset/download.

`TactileReport`: coherent snapshot every 20 ms, 115200 8N1; skips a timer tick if
the previous frame is still transmitting. Six inputs continue counting while TX
is busy. CRC-8 polynomial 0x07, initial zero, covers ASCII before `*`.

Packet: `B1` + 4 hex sequence + 2 hex raw mask + 2 hex filtered mask +
six 4-hex press counts + six 4-hex release counts + six 4-hex raw-edge counts +
`*` + 2 hex CRC + CR LF. Length 87 bytes. Masks use bit 0 for SW1 through bit 5
for SW6; count arrays list SW1 first. Raw level is sampled telemetry, not a
logic-analyzer trace; counters retain clicks shorter than a report interval.

Validation covers bounce rejection on both edges, simultaneous inputs, short
pulses, held inputs, reset while held, counter wrap, snapshot coherence and real
UART framing/CRC. Reports distinguish strict style checks, simulation, timing,
programming and physical user tests; no unrun hardware check is a pass.


2026-11-02 更新：用户修复连接后，App 实际收到全部六键动作；按下与释放计数均为 [8,17,24,32,28,15]，SW1/SW4 不再是零计数。快照存于 ../hardware_lab/reports/buttons_merge/switches_after_repair.json（相对于项目目录）。六键现已并入综合测试和 HDMI 项目，独立六键位流仍保留用于回退。
