# tb_fx_delay 模块规范

> RTL: `sim/tb_fx_delay.v`

## 1. 模块目的

逐样本独立整数模型比对，包含清空、旁路、饱和、尾音衰减及输出暂停。

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
| `o_done` | output | 1 | 未声明 | control | o_done |

## 5. 周期行为与延迟

- 逐样本独立整数模型比对，包含清空、旁路、饱和、尾音衰减及输出暂停。

## 6. WaveDrom 时序图

### 流水接纳与反压

在输入握手时锁存一帧及配置，多周期读写反馈RAM。完成结果暂停期间保持不变。示意图不代表实际时钟延迟。

![流水接纳与反压](waveforms/tb_fx_delay_stream.svg)

- WaveJSON：[tb_fx_delay_stream.json5](waveforms/tb_fx_delay_stream.json5)

## 7. 边界、反压与错误

- signed minima/maxima and zero
- changing tags and parameters every accepted beat
- long backpressure and bubbles
- reset while pipeline holds transactions

## 8. CDC 与综合约束

- Verilog-2001; single 50MHz clock; signed Q26 audio, signed 18-bit Q16 feedback RAM.
- See FX.md for numerical equations, command layout and limits. No board timing claim.
- Clear only while idle, RAM validity reset without clearing memory contents. Reset cancels in-flight work.

## 9. 验证与验收

- Independent integer model, stereo impulses and random full-scale inputs
- Fractional and maximum delay, bypass, clipping and zero-input tail decay
- Backpressure and reset; independent command replay; atomic parameter commit; 1024-clock deadline

## 10. 可追溯性

- 规格模块：`tb_fx_delay`
- RTL 路径：`sim/tb_fx_delay.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
