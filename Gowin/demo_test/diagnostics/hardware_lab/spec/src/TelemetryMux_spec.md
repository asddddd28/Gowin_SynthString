# TelemetryMux 模块规范

> RTL: `src/TelemetryMux.v`

## 1. 模块目的

Parameterizable whole-line UART arbiter; C_CHANNELS 1..8 (default 5, HardwareLab uses 6), C_BAUD default 434. Signal widths valid/ready/priority = C_CHANNELS, data = 8*C_CHANNELS.

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_clk", "frequency_mhz": 50, "edge": "posedge"}`
- 复位：`{"name": "i_rstn", "active": "low", "synchronous": false, "description": "Top asynchronous assertion and synchronized release"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | 未声明 | clock | i_clk; requirements.md defines transport/control semantics |
| `i_rstn` | input | 1 | 未声明 | reset | i_rstn; requirements.md defines transport/control semantics |
| `i_valid` | input | 5 | 未声明 | data | i_valid; requirements.md defines transport/control semantics |
| `i_data` | input | 40 | 未声明 | data | i_data; requirements.md defines transport/control semantics |
| `i_priority` | input | 5 | 未声明 | data | i_priority; requirements.md defines transport/control semantics |
| `o_ready` | output | 5 | 未声明 | data | o_ready; requirements.md defines transport/control semantics |
| `o_tx` | output | 1 | 未声明 | data | o_tx; requirements.md defines transport/control semantics |

## 5. 周期行为与延迟

- Lock source until accepted LF. Each byte accepted once into115200 UART.
- Separate round-robin cursors for urgent and ordinary groups; after3 urgent frames service one ordinary frame when pending.

## 6. WaveDrom 时序图

### Held byte transfer

Conceptual ready/valid sequence; not measured timing.

![Held byte transfer](waveforms/TelemetryMux_backpressure.svg)

- WaveJSON：[TelemetryMux_backpressure.json5](waveforms/TelemetryMux_backpressure.json5)

## 7. 边界、反压与错误

- Reset aborts partially sent line; host parser must resynchronize.
- Pending data remains stable under backpressure; physical sampling continues.

## 8. CDC 与综合约束

- Verilog2001; 50MHz; original electrical interfaces unchanged.

## 9. 验证与验收

- Wire-level ADC/UART,32-key atomic calibration,ACK retry,reactive effects and piano game integration.
- Dual-pad guitar mixed with encoder and joystick frames; bounded-priority saturated arbiter.

## 10. 可追溯性

- 规格模块：`TelemetryMux`
- RTL 路径：`src/TelemetryMux.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
