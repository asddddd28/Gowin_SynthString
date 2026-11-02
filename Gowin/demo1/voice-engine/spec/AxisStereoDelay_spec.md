# AxisStereoDelay 模块规范

> RTL: `rtl/AxisStereoDelay.v`

## 1. 模块目的

共享立体声分数延迟；32K采样/声道，参数随输入握手锁存。

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
| `i_axis_aclk` | input | 1 | 未声明 | clock | i_axis_aclk |
| `i_axis_arstn` | input | 1 | 未声明 | reset | i_axis_arstn |
| `i_s_axis_tdata` | input | 64 | 未声明 | data | i_s_axis_tdata |
| `i_s_axis_tuser` | input | 32 | 未声明 | data | i_s_axis_tuser |
| `i_s_axis_tvalid` | input | 1 | 未声明 | control | i_s_axis_tvalid |
| `o_s_axis_tready` | output | 1 | 未声明 | control | o_s_axis_tready |
| `o_m_axis_tdata` | output | 64 | 未声明 | data | o_m_axis_tdata |
| `o_m_axis_tuser` | output | 32 | 未声明 | data | o_m_axis_tuser |
| `o_m_axis_tvalid` | output | 1 | 未声明 | control | o_m_axis_tvalid |
| `i_m_axis_tready` | input | 1 | 未声明 | control | i_m_axis_tready |
| `i_config` | input | 160 | 未声明 | data | i_config |
| `i_clear` | input | 1 | 未声明 | control | i_clear |
| `o_clipped` | output | 1 | 未声明 | control | o_clipped |

## 5. 周期行为与延迟

- 共享立体声分数延迟；32K采样/声道，参数随输入握手锁存。
- Config words: Q16.16 left/right delay (1..32767.99998 samples), signed Q26 feedback, Q26 wet, flags enable/pingpong.
- Synchronous read RAM, linear interpolation, Q52 feedback sum quantized toward zero to Q16; state saturation ±2, output saturation ±1.
- Disabled effect returns dry input exactly; zero injection lets the hidden tail decay. Clear invalidates history in constant time.
- One input in flight; sample tag unchanged; output stalls do not repeat state writes.
- C_DELAY_ADDR_BITS defaults15 in the library; board top uses14. Depth=2**bits, Q16.16 maximum delay=(depth<<16)-1; capability registers report actual depth. Supported board configurations14/15.
- C_DELAY_ADDR_BITS defaults15 in the library; board top uses13. Depth=2**bits, Q16.16 maximum delay=(depth<<16)-1; capability registers report actual depth. Supported board configurations13/14/15.

## 6. WaveDrom 时序图

### 流水接纳与反压

在输入握手时锁存一帧及配置，多周期读写反馈RAM。完成结果暂停期间保持不变。示意图不代表实际时钟延迟。

![流水接纳与反压](waveforms/AxisStereoDelay_stream.svg)

- WaveJSON：[AxisStereoDelay_stream.json5](waveforms/AxisStereoDelay_stream.json5)

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

- 规格模块：`AxisStereoDelay`
- RTL 路径：`rtl/AxisStereoDelay.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
