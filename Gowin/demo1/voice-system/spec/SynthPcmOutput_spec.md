# SynthPcmOutput 模块规范

> RTL: `rtl/SynthPcmOutput.v`

## 1. 模块目的

Q26 stereo to saturated signed16 with symmetric nearest rounding; consume PCM only at fixed1024-clock frame boundaries.

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
| `i_valid` | input | 1 | 未声明 | control | i_valid |
| `i_data` | input | 64 | 未声明 | data | i_data |
| `o_ready` | output | 1 | 未声明 | control | o_ready |
| `o_bclk` | output | 1 | 未声明 | control | o_bclk |
| `o_ws` | output | 1 | 未声明 | control | o_ws |
| `o_data` | output | 1 | 未声明 | control | o_data |
| `o_frames` | output | 32 | 未声明 | data | o_frames |
| `o_underruns` | output | 32 | 未声明 | data | o_underruns |

## 5. 周期行为与延迟

- Q26 stereo to saturated signed16 with symmetric nearest rounding; consume PCM only at fixed1024-clock frame boundaries.
- PT8211: 16 BCK per channel, WS high left, MSB first. BCK rises at counts16+32n; serial data changes near preceding falling edge.
- Startup silence is not an underrun; after first consumed sample missing frames output zero and increment underrun counter.

## 6. WaveDrom 时序图

### 流水接纳与反压

事件或命令稳定保持至握手，执行后完成返回；音频按固定帧节拍独立运行。示意图不表示绝对运算周期。

![流水接纳与反压](waveforms/SynthPcmOutput_stream.svg)

- WaveJSON：[SynthPcmOutput_stream.json5](waveforms/SynthPcmOutput_stream.json5)

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

- 规格模块：`SynthPcmOutput`
- RTL 路径：`rtl/SynthPcmOutput.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
