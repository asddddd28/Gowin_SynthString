# TactileButtons Module Specification

> RTL: `src/TactileButtons.v`

## 1. 模块目的

未提供模块目的。

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_clk", "frequency_mhz": 50, "edge": "posedge"}`
- 复位：`{"name": "i_rstn", "active": "low", "synchronous": false, "description": "Top synchronizes release for child modules"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | 未声明 | clock | clock |
| `i_rstn` | input | 1 | 未声明 | reset | reset |
| `i_buttons` | input | 6 | 未声明 | data | six active-high asynchronous switches |
| `o_uart_tx` | output | 1 | 未声明 | data | DEBUG UART telemetry |
| `o_rgb` | output | 1 | 未声明 | data | constant low RGB data |
| `o_pa_disable` | output | 1 | 未声明 | data | constant high disables speaker amplifier |

## 5. 周期行为与延迟

- Hold internal reset until two-stage external release and power counter bit 15 (32768 cycles). Initialize startup counters to zero.
- Instantiate six independent TactileInput channels, SW1 on bit zero and highest 16-bit counter slice. Reporter continuously captures coherent data.
- SW2 is AB18 according to actual interface schematic, not the spreadsheet AA18 typo. All button ports are input-only; other peripherals are not scanned. RGB stays low and PA disable high.

## 6. WaveDrom 时序图

### TactileButtons conceptual timing

Conceptual phases, not a measured trace; synchronization precedes the five-millisecond stability window.

![TactileButtons conceptual timing](waveforms/TactileButtons_stable-window.svg)

- WaveJSON：[TactileButtons_stable-window.json5](waveforms/TactileButtons_stable-window.json5)

## 7. 边界、反压与错误

- Reset clears all counters; held-at-reset input counts once.
- Simultaneous keys do not share filter state. Counters and sequence wrap unsigned.
- Raw telemetry is a sampled snapshot, not a lossless waveform.

## 8. CDC 与综合约束

- 50 MHz clock, 3.3 V switch inputs; C_STABLE_CYCLES >= 1, C_REPORT_CYCLES >= 1, C_BAUD_CYCLES >= 2.
- Production debounce 250000 cycles; report 1000000 cycles; UART divisor 434. Logical press counters survive any missed display refresh.

## 9. 验证与验收

- xsim: bounce both edges, channel mapping, simultaneous press/release, long hold, modulo wrap, reset held.
- Actual UART bits decoded independently in Python and Rust; CRC, fields, sequence, snapshot isolation.
- Gowin routing/timing and SRAM download; physical per-switch test is separate evidence.

## 10. 可追溯性

- 规格模块：`TactileButtons`
- RTL 路径：`src/TactileButtons.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
