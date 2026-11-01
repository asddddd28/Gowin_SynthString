# UartRx 模块规范

> RTL: `src/UartRx.v`

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
| `i_rx` | input | 1 | 未声明 | data | rx |
| `o_byte` | output | 8 | 未声明 | data | byte |
| `o_valid` | output | 1 | 未声明 | data | valid |
| `o_error` | output | 1 | 未声明 | data | error |

## 5. 周期行为与延迟

- Reuse validated demo1 receiver unchanged. Synchronize asynchronous RX then sample8N1 at configured baud.
- One-cycle valid on completed byte; framing failure raises error.

## 6. WaveDrom 时序图

### UartRx operation

Conceptual phases; exact cycle contract and verification are specified above.

![UartRx operation](waveforms/UartRx_operation.svg)

- WaveJSON：[UartRx_operation.json5](waveforms/UartRx_operation.json5)

## 7. 边界、反压与错误

- Reset aborts active operation; valid/configured state cleared.
- C_CLOCK_HZ=50MHz equivalent434*115200 for exact434 cycles/bit; baud115200.
- Asynchronous input only crosses through receiver synchronizer.

## 8. CDC 与综合约束

- C_CLOCK_HZ=50MHz equivalent434*115200 for exact434 cycles/bit; baud115200.
- Asynchronous input only crosses through receiver synchronizer.

## 9. 验证与验收

- Real UART command traffic and accelerated wire-level integration test.

## 10. 可追溯性

- 规格模块：`UartRx`
- RTL 路径：`src/UartRx.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
