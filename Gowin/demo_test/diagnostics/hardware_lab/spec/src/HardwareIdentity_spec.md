# HardwareIdentity 模块规范

> RTL: `src/HardwareIdentity.v`

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
| `i_ready` | input | 1 | 未声明 | data | i_ready; requirements.md defines transport/control semantics |
| `o_valid` | output | 1 | 未声明 | data | o_valid; requirements.md defines transport/control semantics |
| `o_data` | output | 8 | 未声明 | data | o_data; requirements.md defines transport/control semantics |

## 5. 周期行为与延迟

- Immediately after reset and every250ms send H1007F0100*66 CRLF. Hold byte until ready.

## 6. WaveDrom 时序图

### Held byte transfer

Conceptual ready/valid sequence; not measured timing.

![Held byte transfer](waveforms/HardwareIdentity_backpressure.svg)

- WaveJSON：[HardwareIdentity_backpressure.json5](waveforms/HardwareIdentity_backpressure.json5)

## 7. 边界、反压与错误

- Reset aborts partially sent line; host parser must resynchronize.
- Pending data remains stable under backpressure; physical sampling continues.

## 8. CDC 与综合约束

- Verilog2001; 50MHz; original electrical interfaces unchanged.

## 9. 验证与验收

- Wire-level ADC/UART,32-key atomic calibration,ACK retry,reactive effects and piano game integration.
- Dual-pad guitar mixed with encoder and joystick frames; bounded-priority saturated arbiter.

## 10. 可追溯性

- 规格模块：`HardwareIdentity`
- RTL 路径：`src/HardwareIdentity.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
