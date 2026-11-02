# LedFrameTx 模块规范

> RTL: `src/LedFrameTx.v`

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
| `i_grb` | input | 24 | 未声明 | data | grb |
| `o_pixel` | output | 5 | 未声明 | data | pixel |
| `o_frame_tick` | output | 1 | 未声明 | data | frame tick |
| `o_data` | output | 1 | 未声明 | data | data |

## 5. 周期行为与延迟

- Emit32 GRB24-bit pixels MSB-first; zero high15 clocks, one high42, bit period63.
- Frame tick allows source snapshot one cycle before pixel load.
- Two-clock gap between pixels; frame-period counter starts a frame every configured interval.

## 6. WaveDrom 时序图

### LedFrameTx operation

Conceptual phases; exact cycle contract and verification are specified above.

![LedFrameTx operation](waveforms/LedFrameTx_operation.svg)

- WaveJSON：[LedFrameTx_operation.json5](waveforms/LedFrameTx_operation.json5)

## 7. 边界、反压与错误

- Reset aborts active operation; valid/configured state cleared.
- 50MHz only; C_FRAME_CYCLES>=65000; default1000000 gives50Hz.
- At minimum period latch low remains above300us; reset immediately forces low.

## 8. CDC 与综合约束

- 50MHz only; C_FRAME_CYCLES>=65000; default1000000 gives50Hz.
- At minimum period latch low remains above300us; reset immediately forces low.

## 9. 验证与验收

- 165120 decoded pulses check widths, interpixel period1300ns, bit1260ns, frame interval and reset midpulse.

## 10. 可追溯性

- 规格模块：`LedFrameTx`
- RTL 路径：`src/LedFrameTx.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
