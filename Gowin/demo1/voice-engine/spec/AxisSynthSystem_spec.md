# AxisSynthSystem 模块规范

> RTL: `rtl/AxisSynthSystem.v`

## 1. 模块目的

兼容旧任务的内部互联与持续采样时钟、PCM 队列。

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| LEGACY_ENABLE | 1 | 启用旧上下文执行器；板级 AxiSynthEndpoint 设为 0。 |
| C_DELAY_ADDR_BITS | 15 | Delay 环形 RAM 地址位数；当前板级设为 13。 |

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
| `i_touch_gain` | input | 18 | 未声明 | data | i_touch_gain |
| `i_touch_pitch` | input | 32 | 未声明 | data | i_touch_pitch |
| `i_touch_cutoff` | input | 20 | 未声明 | data | i_touch_cutoff |
| `i_touch_cutoff_active` | input | 1 | 未声明 | data | i_touch_cutoff_active |

## 5. 周期行为与延迟

- Single-beat A0..A9 and B0..B3 route to the resident engine; C0..C4 route to the independent shared FX domain.
- LEGACY_ENABLE defaults to one for compatibility; the AxiSynthEndpoint wrapper sets zero and returns unsupported status 1 to old raw/context commands.
- Malformed packet head and tails remain in the legacy drain domain.
- Two-entry ingress queue adapts voice PCM pulses to AxisFxEngine; Delay then Reverb own shared tail state; output FIFO full drops new frames without freezing feedback.
- Sample tick every 1024 clocks; PCM full drops new frame and increments telemetry without blocking synthesis.
- 完成通道含输出槽与备用槽，各保存 168 位 opcode/tag/result；备用有效必然意味着输出槽有效。上游接收仅依赖本地备用槽有效位和轮询选择，不组合依赖 i_m_axis_tready。
- 轮询顺序为 Legacy → Voice → FX，初始优先 Legacy；仅在实际接收完成包时推进优先级。每个源在 VALID && READY 时提交。
- 空队列接收后下一拍输出有效；只有输出槽有效时可同时出队与入队，连续 READY 下吞吐为每拍一包。输出暂停时数据与标签稳定。
- 两槽全满时不允许同拍借用出队空间：本拍只出队、下拍恢复接收。该满载恢复边界产生一拍上游接收气泡，且不引入无反压场景的额外首包延迟。
- 复位清空两个完成槽和轮询优先级，并取消所有在途完成包；PCM/FX 队列和音频计算状态机的时序保持原行为。
- C_DELAY_ADDR_BITS defaults15 in the library; board top uses13. Depth=2**bits, Q16.16 maximum delay=(depth<<16)-1; capability registers report actual depth. Supported board configurations13/14/15.
- C_FX_ENABLE编译期选择；整板SynthSystemTop默认0，内核默认1保留回归。关闭时不实例化Delay/Reverb，Voice PCM直接进入原四项PCM队列，FX能力/容量/遥测为0，C0..C4通过不支持完成路径返回状态1。开机使用剔除FX命令的boot_dry.hex，正常音色、键床、UART及音频频率不变。
- D0/D1 filter completion shares FX arbitration lane independently of optionalDelay/Reverb. Global lowpass aftervoice/FX beforePCMqueue; adds30clocks toframe path; missed filterinput increments pcm_dropped.
- C_TOUCH_ENABLE默认0，透传注册的硬件触摸调制源到Voice和Lowpass；AXI继续管理基础参数和音色程序。开启触摸的AxiVoiceEndpoint报告ABI1.7，否则保持1.6。

## 6. WaveDrom 时序图

### 触摸事件与调制提交

触摸采集在系统域提交，调制每毫秒平滑；音频帧独立执行，NoteOff确认之后才重新起音。

![触摸事件与调制提交](waveforms/AxisSynthSystem_touch.svg)

- WaveJSON：[AxisSynthSystem_touch.json5](waveforms/AxisSynthSystem_touch.json5)

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
- tb_completion_isolation：受控三源、独立队列计分板、长暂停、满载恢复、同时入出、满队列复位、轮询公平性和无时钟 READY 翻转隔离检查；实际 DSP 行为由整链测试另行覆盖。
- tb_axi_fx / tb_axi_voice_endpoint / tb_axi_synth_engine / tb_axi_lfo / tb_synth_system：真实子模块、AXI 回读、整数 PCM 参考模型和 1024 拍期限回归。
- 关闭FX的整板启动、真实键床/UART、不支持命令和重放、PCM/PT8211一致性；保留FX配置兼容回归。

## 10. 可追溯性

- 规格模块：`AxisSynthSystem`
- RTL 路径：`rtl/AxisSynthSystem.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
