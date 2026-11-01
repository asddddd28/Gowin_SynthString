# KeyboardTelemetry 模块规范

> RTL: `src/KeyboardTelemetry.v`

## 1. 模块目的

未提供模块目的。

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_clk", "frequency_mhz": 50, "edge": "posedge"}`
- 复位：`{"name": "i_rstn", "active": "low", "synchronous": false, "description": "Async assertion; synchronous release provided by top"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | 未声明 | clock | 50 MHz rising-edge clock |
| `i_rstn` | input | 1 | 未声明 | reset | Active-low reset; top synchronizes release |
| `i_key` | input | 5 | 未声明 | data | key |
| `i_raw` | input | 12 | 未声明 | data | raw |
| `i_valid` | input | 1 | 未声明 | data | valid |
| `i_ack` | input | 1 | 未声明 | data | ack |
| `i_ack_seq` | input | 8 | 未声明 | data | ack seq |
| `i_ack_result` | input | 8 | 未声明 | data | ack result |
| `i_configured` | input | 1 | 未声明 | data | configured |
| `i_generation` | input | 8 | 未声明 | data | generation |
| `i_mode` | input | 4 | 未声明 | data | mode |
| `i_direction` | input | 1 | 未声明 | data | direction |
| `i_pressed` | input | 32 | 未声明 | data | pressed |
| `o_ready` | output | 1 | 未声明 | data | ready |
| `o_tx` | output | 1 | 未声明 | data | tx |
| `i_game_status` | input | 128 | 未声明 | data | Game metadata and32 two-bit pixels |

## 5. 周期行为与延迟

- Arbitrate whole UART records: command ACK before periodic state before raw sample.
- Raw K01:ABC CRLF format retained; one CRC-protected state per scan.
- Response @18HEX*CRC LF; capture ACK state after controller update; stop-and-wait one-slot pending.
- 434 cycles/bit at50MHz, 8N1; ready transfers sample only when idle and no queued state.
- Every scan includes #32HEX*CRC LF game status, CRC over16bytes.
- ACK > normal status > game status > raw; game payload snapshotted before CRC/serialization.

## 6. WaveDrom 时序图

### KeyboardTelemetry operation

Conceptual phases; exact cycle contract and verification are specified above.

![KeyboardTelemetry operation](waveforms/KeyboardTelemetry_operation.svg)

- WaveJSON：[KeyboardTelemetry_operation.json5](waveforms/KeyboardTelemetry_operation.json5)

## 7. 边界、反压与错误

- Reset aborts active operation; valid/configured state cleared.
- C_UART_CYCLES>=4; one outstanding host command.
- Backpressure pauses scanner without dropping or reordering raw samples.

## 8. CDC 与综合约束

- C_UART_CYCLES>=4; one outstanding host command.
- Backpressure pauses scanner without dropping or reordering raw samples.

## 9. 验证与验收

- Wire-level UART decoder checks start/stop, raw order, reply CRC and returned mode/generation/pressed mask.
- Integrated UART CRC128 decoder, game epoch/mode/score and calibrated ADC piano play.

## 10. 可追溯性

- 规格模块：`KeyboardTelemetry`
- RTL 路径：`src/KeyboardTelemetry.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
