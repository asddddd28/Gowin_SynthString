# EncoderUartTx 模块规范

> RTL: `src/EncoderUartTx.v`

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
| `i_clk` | input | 1 | 未声明 | clock | 50MHz clock |
| `i_rstn` | input | 1 | 未声明 | reset | Active-low reset |
| `i_start` | input | 1 | 未声明 | data | Start pulse accepted only when idle |
| `i_data` | input | 8 | 未声明 | data | Byte to send |
| `o_busy` | output | 1 | 未声明 | data | High through stop bit |
| `o_tx` | output | 1 | 未声明 | data | UART serial line |

## 5. 周期行为与延迟

- Latch start plus data plus stop when idle. Transmit LSB first, each bit lasts C_BAUD_CYCLES.
- Ignore start while busy. Reset aborts transfer and forces idle high.

## 6. WaveDrom 时序图

### EncoderUartTx conceptual operation

Conceptual phases; not a measured trace.

![EncoderUartTx conceptual operation](waveforms/EncoderUartTx_operation.svg)

- WaveJSON：[EncoderUartTx_operation.json5](waveforms/EncoderUartTx_operation.json5)

## 7. 边界、反压与错误

- Initial stable phase must not generate a rotation.
- Reset aborts UART and clears all counters.
- Double-bit transition is rejected from position, not reconstructed.

## 8. CDC 与综合约束

- C_FILTER_CYCLES >= 2 and <=65535; C_BAUD_CYCLES >=2 and <=65535.
- C_REPORT_CYCLES must exceed full five-line UART transmission for every interval to be serviced.
- AB voltage must be compatible with 3.3V IO. Mechanical CW polarity is not yet calibrated.

## 9. 验证与验收

- xsim positive, negative, short glitch, backtracking bounce, invalid transition, five-channel mapping, exact ASCII and reset during UART.
- Gowin synthesis and timing; hardware rotate test still required.

## 10. 可追溯性

- 规格模块：`EncoderUartTx`
- RTL 路径：`src/EncoderUartTx.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
