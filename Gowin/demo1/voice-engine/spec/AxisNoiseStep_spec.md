# AxisNoiseStep 模块规范

> RTL: `rtl/AxisNoiseStep.v`

## 1. 模块目的

显式状态的 xorshift 噪声源；不同声部各自保存随机状态。

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
| `i_s_axis_tdata` | input | 128 | 未声明 | data | 本次操作的状态与参数原子快照 |
| `i_s_axis_tuser` | input | 32 | 未声明 | data | 调用者的透明事务编号 |
| `i_s_axis_tvalid` | input | 1 | 未声明 | control | 源端持有完整请求 |
| `o_s_axis_tready` | output | 1 | 未声明 | control | 本拍可以接收快照 |
| `o_m_axis_tdata` | output | 64 | 未声明 | data | 该事务的数值和状态结果 |
| `o_m_axis_tuser` | output | 32 | 未声明 | data | 与结果同步返回的原编号 |
| `o_m_axis_tvalid` | output | 1 | 未声明 | control | 输出寄存器包含可消费事务 |
| `i_m_axis_tready` | input | 1 | 未声明 | control | 调用者可以提交输出结果 |

## 5. 周期行为与延迟

- No stalls: accept at E0, earliest output transfer E4; initiation interval one.
- input[31:0]=old state; [127:32] reserved/ignored; zero state maps to one.
- output[31:0]=new state; [63:32]=signed(new state) >>> 5, a signed Q26 sample.
- Output backpressure freezes every stage. Input and output transfers require valid and ready.
- Operator never owns voice state; caller prevents using stale state in a subsequent sample.

## 6. WaveDrom 时序图

### 流水接纳与反压

输入 E0 接纳；无反压时最早 E4 消费。图为握手关系示意，暂停时数据与编号整体冻结。

![流水接纳与反压](waveforms/AxisNoiseStep_stream.svg)

- WaveJSON：[AxisNoiseStep_stream.json5](waveforms/AxisNoiseStep_stream.json5)

## 7. 边界、反压与错误

- signed minima/maxima and zero
- changing tags and parameters every accepted beat
- long backpressure and bubbles
- reset while pipeline holds transactions

## 8. CDC 与综合约束

- Verilog-2001, single clock domain, no TLAST/TKEEP; this is one atomic task per beat.
- Reserved input bits are ignored. Tags are opaque 32-bit values.
- No board integration or timing capacity claim; independent operator library only.

## 9. 验证与验收

- Python wide-integer reference comparison
- minimum latency and one accepted task per unstalled clock
- output stability while stalled
- reset cancellation followed by a fresh sequence

## 10. 可追溯性

- 规格模块：`AxisNoiseStep`
- RTL 路径：`rtl/AxisNoiseStep.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
