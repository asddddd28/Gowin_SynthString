# AxisSynthSystem 模块规范

> RTL: `rtl/AxisSynthSystem.v`

## 1. 模块目的

兼容旧任务的内部互联与持续采样时钟、PCM 队列。

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
| `i_s_axis_tdata` | input | 384 | 未声明 | data | 本次操作的状态与参数原子快照 |
| `i_s_axis_tuser` | input | 32 | 未声明 | data | 调用者的透明事务编号 |
| `i_s_axis_tvalid` | input | 1 | 未声明 | control | 源端持有完整请求 |
| `o_s_axis_tready` | output | 1 | 未声明 | control | 本拍可以接收快照 |
| `o_m_axis_tdata` | output | 128 | 未声明 | data | 该事务的数值和状态结果 |
| `o_m_axis_tuser` | output | 32 | 未声明 | data | 与结果同步返回的原编号 |
| `o_m_axis_tvalid` | output | 1 | 未声明 | control | 输出寄存器包含可消费事务 |
| `i_m_axis_tready` | input | 1 | 未声明 | control | 调用者可以提交输出结果 |
| `i_s_axis_tdest` | input | 8 | 未声明 | data | 任务目的操作码 |
| `i_s_axis_tlast` | input | 1 | 未声明 | control | 原子命令边界 |
| `o_m_axis_tdest` | output | 8 | 未声明 | data | 完成操作码 |
| `o_m_axis_tlast` | output | 1 | 未声明 | control | 完成均为单拍 |
| `o_count_executed` | output | 32 | 未声明 | data | 旧上下文计数 |
| `o_count_replayed` | output | 32 | 未声明 | data | 旧上下文计数 |
| `o_count_rejected` | output | 32 | 未声明 | data | 旧上下文计数 |
| `o_count_bound` | output | 32 | 未声明 | data | 旧上下文计数 |
| `o_pcm_valid` | output | 1 | 未声明 | control | PCM 队列有数据 |
| `i_pcm_ready` | input | 1 | 未声明 | control | 消费 PCM |
| `o_pcm_data` | output | 64 | 未声明 | data | 左右 Q26 采样 |
| `o_pcm_frame` | output | 32 | 未声明 | data | 对应完成帧 |
| `o_overruns` | output | 32 | 未声明 | data | 采样期限错过 |
| `o_pcm_dropped` | output | 32 | 未声明 | data | PCM 队列满丢弃新帧 |
| `o_render_cycles` | output | 32 | 未声明 | data | 最近渲染周期 |
| `o_active` | output | 8 | 未声明 | data | 活动声部位图 |
| `o_fx_frames` | output | 32 | 未声明 | data | FX处理帧数 |
| `o_fx_clipped` | output | 32 | 未声明 | data | FX削波帧数 |
| `o_fx_dropped` | output | 32 | 未声明 | data | FX输入丢帧数 |
| `o_fx_cycles` | output | 32 | 未声明 | data | FX处理时钟数 |

## 5. 周期行为与延迟

- Single-beat A0..A9 and B0..B3 route to the resident engine; C0..C4 route to the independent shared FX domain.
- LEGACY_ENABLE defaults to one for compatibility; the AxiSynthEndpoint wrapper sets zero and returns unsupported status 1 to old raw/context commands.
- Malformed packet head and tails remain in the legacy drain domain.
- Three-way round-robin completion arbitration latches ownership while stalled. PCM uses a separate four-entry FIFO.
- Two-entry ingress queue adapts voice PCM pulses to AxisFxEngine; Delay then Reverb own shared tail state; output FIFO full drops new frames without freezing feedback.
- Sample tick every 1024 clocks; PCM full drops new frame and increments telemetry without blocking synthesis.
- C_DELAY_ADDR_BITS defaults15 in the library; board top uses14. Depth=2**bits, Q16.16 maximum delay=(depth<<16)-1; capability registers report actual depth. Supported board configurations14/15.
- C_DELAY_ADDR_BITS defaults15 in the library; board top uses13. Depth=2**bits, Q16.16 maximum delay=(depth<<16)-1; capability registers report actual depth. Supported board configurations13/14/15.

## 6. WaveDrom 时序图

### 流水接纳与反压

请求锁存后运算；结果可以暂停，已驻留声部仍按采样时钟推进。图示握手关系，不按图推断延迟。

![流水接纳与反压](waveforms/AxisSynthSystem_stream.svg)

- WaveJSON：[AxisSynthSystem_stream.json5](waveforms/AxisSynthSystem_stream.json5)

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

- 规格模块：`AxisSynthSystem`
- RTL 路径：`rtl/AxisSynthSystem.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
