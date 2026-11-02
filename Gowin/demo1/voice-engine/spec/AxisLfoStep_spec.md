# AxisLfoStep 模块规范

> RTL: `rtl/AxisLfoStep.v`

## 1. 模块目的

无状态LFO单步流水；调用者拥有相位与随机状态。

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
| `i_axis_aclk` | input | 1 | 未声明 | clock | 任务与结果共用时钟 |
| `i_axis_arstn` | input | 1 | 未声明 | reset | 异步清除有效资格；外部同步释放 |
| `i_s_axis_tdata` | input | 256 | 未声明 | data | 本次操作的状态与参数原子快照 |
| `i_s_axis_tuser` | input | 32 | 未声明 | data | 调用者的透明事务编号 |
| `i_s_axis_tvalid` | input | 1 | 未声明 | control | 源端持有完整请求 |
| `o_s_axis_tready` | output | 1 | 未声明 | control | 本拍可以接收快照 |
| `o_m_axis_tdata` | output | 160 | 未声明 | data | 该事务的数值和状态结果 |
| `o_m_axis_tuser` | output | 32 | 未声明 | data | 与结果同步返回的原编号 |
| `o_m_axis_tvalid` | output | 1 | 未声明 | control | 输出寄存器包含可消费事务 |
| `i_m_axis_tready` | input | 1 | 未声明 | control | 调用者可以提交输出结果 |

## 5. 周期行为与延迟

- Request words: phase, increment, RNG state, random ramp origin, waveform/polarity/restart flags, restart phase, seed, pulse width.
- Result words: value Q26, next phase, next RNG, next ramp origin, wrap/restart flags. Tag is opaque.
- Seven shapes, bipolar/unipolar, phase restart. RNG changes exactly on phase wrap or restart.
- Five elastic pipeline stages, II=1; downstream stall freezes every stage; reset cancels in-flight work.

## 6. WaveDrom 时序图

### 流水接纳与反压

请求锁存后运算；结果可以暂停，已驻留声部仍按采样时钟推进。图示握手关系，不按图推断延迟。

![流水接纳与反压](waveforms/AxisLfoStep_stream.svg)

- WaveJSON：[AxisLfoStep_stream.json5](waveforms/AxisLfoStep_stream.json5)

## 7. 边界、反压与错误

- signed minima/maxima and zero
- changing tags and parameters every accepted beat
- long backpressure and bubbles
- reset while pipeline holds transactions

## 8. CDC 与综合约束

- Single 50 MHz clock domain; reset cancels in-flight work.
- See ENGINE.md for exact fixed-point and command ABI.
- Candidate: board timing and strict style gate are separate from functional simulation.

## 9. 验证与验收

- Independent Python integer model versus xsim
- Backpressure stability and reset cancellation
- Illegal parameters and voice lifecycle
- 1024-clock frame deadline under eight voices and six operators

## 10. 可追溯性

- 规格模块：`AxisLfoStep`
- RTL 路径：`rtl/AxisLfoStep.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
