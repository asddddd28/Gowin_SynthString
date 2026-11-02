# KeyboardSampler 模块规范

> RTL: `src/KeyboardSampler.v`

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
| `i_adc_dout` | input | 1 | 未声明 | data | adc dout |
| `i_ready` | input | 1 | 未声明 | data | ready |
| `o_mux_sel` | output | 3 | 未声明 | data | mux sel |
| `o_mux_en` | output | 1 | 未声明 | data | mux en |
| `o_adc_cs_n` | output | 1 | 未声明 | data | adc cs n |
| `o_adc_sclk` | output | 1 | 未声明 | data | adc sclk |
| `o_adc_din` | output | 1 | 未声明 | data | adc din |
| `o_key` | output | 5 | 未声明 | data | key |
| `o_raw` | output | 12 | 未声明 | data | raw |
| `o_valid` | output | 1 | 未声明 | data | valid |

## 5. 周期行为与延迟

- Scan row-major 32 keys. Column select order4,5,6,7,3,2,1,0.
- Wait10000 cycles for mux settle; two16-clock ADC conversions per key, discard first pipelined conversion.
- SPI half-period6 cycles. Hold sample/key/valid until ready; then advance.

## 6. WaveDrom 时序图

### KeyboardSampler operation

Conceptual phases; exact cycle contract and verification are specified above.

![KeyboardSampler operation](waveforms/KeyboardSampler_operation.svg)

- WaveJSON：[KeyboardSampler_operation.json5](waveforms/KeyboardSampler_operation.json5)

## 7. 边界、反压与错误

- Reset aborts active operation; valid/configured state cleared.
- ADC pins match existing KeyboardDebug; 50MHz only.
- C_SETTLE_CYCLES>=1; C_HALF_CYCLES>=4; DOUT sampled after external falling edge settling.

## 8. CDC 与综合约束

- ADC pins match existing KeyboardDebug; 50MHz only.
- C_SETTLE_CYCLES>=1; C_HALF_CYCLES>=4; DOUT sampled after external falling edge settling.

## 9. 验证与验收

- ADC behavioral model includes30ns delay; 623 raw records, mux/channel order and reset.

## 10. 可追溯性

- 规格模块：`KeyboardSampler`
- RTL 路径：`src/KeyboardSampler.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
