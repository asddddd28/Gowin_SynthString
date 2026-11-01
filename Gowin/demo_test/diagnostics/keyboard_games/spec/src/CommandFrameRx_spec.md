# CommandFrameRx 模块规范

> RTL: `src/CommandFrameRx.v`

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
| `i_byte` | input | 8 | 未声明 | data | byte |
| `i_valid` | input | 1 | 未声明 | data | valid |
| `i_error` | input | 1 | 未声明 | data | error |
| `o_payload` | output | 80 | 未声明 | data | payload |
| `o_valid` | output | 1 | 未声明 | data | valid |
| `o_crc_error` | output | 1 | 未声明 | data | crc error |

## 5. 周期行为与延迟

- Parse !20HEX*CRC8 LF; CRC8/07 init0 over ten packed payload bytes.
- o_valid pulses for one cycle after newline; o_crc_error accompanies failed CRC.
- New start marker restarts parser. UART error or 100 ms interbyte timeout drops partial frame.

## 6. WaveDrom 时序图

### CommandFrameRx operation

Conceptual phases; exact cycle contract and verification are specified above.

![CommandFrameRx operation](waveforms/CommandFrameRx_operation.svg)

- WaveJSON：[CommandFrameRx_operation.json5](waveforms/CommandFrameRx_operation.json5)

## 7. 边界、反压与错误

- Reset aborts active operation; valid/configured state cleared.
- Bytes and strobes synchronous to i_clk; no backpressure.
- Malformed syntax does not dispatch a command.

## 8. CDC 与综合约束

- Bytes and strobes synchronous to i_clk; no backpressure.
- Malformed syntax does not dispatch a command.

## 9. 验证与验收

- Partial timeout recovery and CRC rejection in tb_keyboard_reactive.

## 10. 可追溯性

- 规格模块：`CommandFrameRx`
- RTL 路径：`src/CommandFrameRx.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
