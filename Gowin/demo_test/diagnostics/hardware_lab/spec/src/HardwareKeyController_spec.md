# HardwareKeyController 模块规范

> RTL: `src/HardwareKeyController.v`

## 1. 模块目的

未提供模块目的。

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
| `i_command` | input | 80 | 未声明 | data | i_command; requirements.md defines transport/control semantics |
| `i_command_valid` | input | 1 | 未声明 | data | i_command_valid; requirements.md defines transport/control semantics |
| `i_crc_error` | input | 1 | 未声明 | data | i_crc_error; requirements.md defines transport/control semantics |
| `i_key` | input | 5 | 未声明 | data | i_key; requirements.md defines transport/control semantics |
| `i_raw` | input | 12 | 未声明 | data | i_raw; requirements.md defines transport/control semantics |
| `i_sample_valid` | input | 1 | 未声明 | data | i_sample_valid; requirements.md defines transport/control semantics |
| `o_ack` | output | 1 | 未声明 | data | o_ack; requirements.md defines transport/control semantics |
| `o_ack_seq` | output | 8 | 未声明 | data | o_ack_seq; requirements.md defines transport/control semantics |
| `o_ack_result` | output | 8 | 未声明 | data | o_ack_result; requirements.md defines transport/control semantics |
| `o_configured` | output | 1 | 未声明 | data | o_configured; requirements.md defines transport/control semantics |
| `o_generation` | output | 8 | 未声明 | data | o_generation; requirements.md defines transport/control semantics |
| `o_mode` | output | 4 | 未声明 | data | o_mode; requirements.md defines transport/control semantics |
| `o_direction` | output | 1 | 未声明 | data | o_direction; requirements.md defines transport/control semantics |
| `o_pressed` | output | 32 | 未声明 | data | o_pressed; requirements.md defines transport/control semantics |
| `o_press_pulse` | output | 32 | 未声明 | data | o_press_pulse; requirements.md defines transport/control semantics |
| `o_clear_effect` | output | 1 | 未声明 | data | o_clear_effect; requirements.md defines transport/control semantics |
| `o_game_start` | output | 1 | 未声明 | data | o_game_start; requirements.md defines transport/control semantics |
| `o_game_stop` | output | 1 | 未声明 | data | o_game_stop; requirements.md defines transport/control semantics |
| `o_game_type` | output | 2 | 未声明 | data | o_game_type; requirements.md defines transport/control semantics |

## 5. 周期行为与延迟

- Atomic32-key double-bank calibration with hysteresis and two-sample qualification.
- Support effect6 continuous flow; mode5 reserved for game start. Command validation, duplicate/idempotent ACK unchanged.

## 6. WaveDrom 时序图

### Held byte transfer

Conceptual ready/valid sequence; not measured timing.

![Held byte transfer](waveforms/HardwareKeyController_backpressure.svg)

- WaveJSON：[HardwareKeyController_backpressure.json5](waveforms/HardwareKeyController_backpressure.json5)

## 7. 边界、反压与错误

- Reset aborts partially sent line; host parser must resynchronize.
- Pending data remains stable under backpressure; physical sampling continues.

## 8. CDC 与综合约束

- Verilog2001; 50MHz; original electrical interfaces unchanged.

## 9. 验证与验收

- Wire-level ADC/UART,32-key atomic calibration,ACK retry,reactive effects and piano game integration.
- Dual-pad guitar mixed with encoder and joystick frames; bounded-priority saturated arbiter.

## 10. 可追溯性

- 规格模块：`HardwareKeyController`
- RTL 路径：`src/HardwareKeyController.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
