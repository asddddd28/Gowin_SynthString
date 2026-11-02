# SynthSystemTop 模块规范

> RTL: `rtl/SynthSystemTop.v`

## 1. 模块目的

Single50MHz board hierarchy: ADC scanner and hysteresis → note source; UART → framed control; boot/keys/host → arbiter → AXI master → AxiSynthEndpoint → PT8211.

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_axis_aclk", "edge": "posedge", "frequency_hz": 50000000}`
- 复位：`{"name": "i_axis_arstn", "active": "low", "style": "asynchronous", "values": "all pipeline valid and output data/tag registers clear; external synchronous release"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | 未声明 | clock | i_clk |
| `i_rstn` | input | 1 | 未声明 | reset | i_rstn |
| `i_adc_dout` | input | 1 | 未声明 | control | i_adc_dout |
| `i_uart_rx` | input | 1 | 未声明 | control | i_uart_rx |
| `o_mux_sel` | output | 3 | 未声明 | data | o_mux_sel |
| `o_mux_en` | output | 1 | 未声明 | control | o_mux_en |
| `o_adc_cs_n` | output | 1 | 未声明 | control | o_adc_cs_n |
| `o_adc_sclk` | output | 1 | 未声明 | control | o_adc_sclk |
| `o_adc_din` | output | 1 | 未声明 | control | o_adc_din |
| `o_uart_tx` | output | 1 | 未声明 | control | o_uart_tx |
| `HP_BCK` | output | 1 | 未声明 | control | HP_BCK |
| `HP_WS` | output | 1 | 未声明 | control | HP_WS |
| `HP_DIN` | output | 1 | 未声明 | control | HP_DIN |
| `PA_EN` | output | 1 | 未声明 | control | PA_EN |

## 5. 周期行为与延迟

- Single50MHz board hierarchy: ADC scanner and hysteresis → note source; UART → framed control; boot/keys/host → arbiter → AXI master → AxiSynthEndpoint → PT8211.
- Reset synchronously released after powerup delay; ADC/UART inputs synchronized. PA_EN active low, enabled only after successful boot and amplifier delay and no faults.
- Core subsystem is shared with voice-engine. No generic AXI crossbar/DMA or external RAM master is claimed.
- C_DELAY_ADDR_BITS=13 board default; core library defaults to15. Capability registers and parameter limits follow the synthesized depth.

## 6. WaveDrom 时序图

### 流水接纳与反压

事件或命令稳定保持至握手，执行后完成返回；音频按固定帧节拍独立运行。示意图不表示绝对运算周期。

![流水接纳与反压](waveforms/SynthSystemTop_stream.svg)

- WaveJSON：[SynthSystemTop_stream.json5](waveforms/SynthSystemTop_stream.json5)

## 7. 边界、反压与错误

- signed minima/maxima and zero
- changing tags and parameters every accepted beat
- long backpressure and bubbles
- reset while pipeline holds transactions

## 8. CDC 与综合约束

- Verilog-2001, single50MHz clock; asynchronous reset assertion, externally synchronized release.
- See SYSTEM.md and model/system_model.py for ABI, numerical behavior, memory images and validation scope.

## 9. 验证与验收

- Independent protocol/PCM model
- Real UART/ADC pins to serial DAC simulation
- AXI stalls, transaction ownership, duplicate/conflicting/invalid requests and reset
- Boot, physical chord, release, host voice/FX commands and resource/timing checks

## 10. 可追溯性

- 规格模块：`SynthSystemTop`
- RTL 路径：`rtl/SynthSystemTop.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
