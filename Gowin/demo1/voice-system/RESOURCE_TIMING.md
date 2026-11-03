# 模块资源与时序：基线及当前候选

**2026-11-02 23:12 当前通过版：** 四类长路径分拍，并按用户要求关闭整板FX。50MHz完整PnR setup/hold0，Fmax50.425MHz，WNS+0.169ns；Logic23087、Register20833、CLS21597、BSRAM62、DSP58。干声整板PCM脉冲实测最大878拍，native压力835拍。固件生成未烧录，详见[分拍与干声版结果](PIPELINED_DRY_ENGINE.md)。以下为历史候选记录。

**2026-11-02 22:34 预取候选：** 满载Voice874→786、整链948→860拍，Register仅+1、BSRAM/DSP不变，Logic+133、CLS+156；但Fmax47.551MHz、WNS−1.030ns、62个setup失败、hold0，未烧录。失败全部落在Voice增益/调制求和（35）与DX包络力度/指数表地址（27）。当前RTL保留候选继续修复，上一个通过版为19:51基线。详见[预取结果与四类紧路径](VOICE_PREFETCH.md)。下文“已撤回”指预取之前的实验。

**2026-11-02 调度阶段：** 保持50MHz。后续加法树、地址锁存、增益/声像提前计算的完整PnR均未通过，已撤回并逐项核对42个构建输入恢复至19:51通过版；没有烧录失败候选。SDP关闭实验确认BSRAM98→77，但实板VCC下限未测，仍只保留离线候选。详见 [RAM实验](SDP_RESOURCE_EXPERIMENT.md)、[撤回的路由/控制实验](VOICE_ROUTE_CONTROL_OPTIMIZATION.md)。当前转向 [调度、队列与冲突设计](SCHEDULING.md)，新增被动仿真统计6133帧，最坏Voice874拍；允许固定多帧延迟，输入事件到DAC响应上限1ms、目标200–500µs，吞吐率单独验收。

**2026-11-02 19:51 当前候选：** FM插值乘积寄存后，现有50MHz约束下setup/hold失败均为0，Fmax50.037MHz，最小setup slack为+0.015ns、TNS0。Logic27110、Register24090、CLS24337，BSRAM98/118、DSP94/118；算子10拍、满载948/1024拍不变。裕量仅15ps，外设I/O预算仍不完整，本轮未烧录。详见 [FM分拍完整结果及后续紧路径](FM_INTERPOLATION_PIPELINE.md)。

19:18 FX控制基线：Logic27474、Register24026、CLS24483，BSRAM98/118、DSP94/118；89个setup失败终点，TNS−84.362ns，WNS−1.862ns，Fmax45.742MHz。详见 [FX控制完整结果](FX_CONTROL_PIPELINE.md)。

18:51声像分拍基线：Logic27386、Register23917、CLS24488，BSRAM98/118、DSP94/118；222个setup失败终点，TNS−115.792ns，WNS−2.062ns，Fmax45.327MHz。详见 [声像分拍结果](VOICE_PAN_PIPELINE.md)。

18:17 的 P0-A 基线：Logic 27531、Register 23787、CLS 24310，BSRAM/DSP 均为 98/118；347 个 setup 失败终点，TNS −625.236 ns，WNS −9.387 ns，Fmax 34.028 MHz，详见 [P0-A 对比](COMPLETION_ISOLATION.md)。以下表格和路径保留为 16:06 原基线。

原基线取自2026-11-02 16:06:18构建。目标50MHz（20ns），未降频。该候选未通过时序、未烧录，当时按用户要求停止调试并发布快照。

2026-11-02 16:58 已完成相同源码与约束的扩大报告分析，5000 条路径覆盖全部 1240 个失败端点，详见 [全系统时序归属与 VoiceSynthEngine 调试计划](TIMING_AUDIT.md)。下文“最新长路径”仍是原始最差 25 条的摘要，完整分布以新分析为准。

## 整板实际布局布线结果

| 资源 | 实际用量 | 报告占比 |
|---|---:|---:|
| Logic | 27189/59904 | 46% |
| CLS | 24379/29952 | 82% |
| Register | 23643/60780 | 39% |
| BSRAM | 98/118 | 84% |
| DSP | 98/118 | 84% |
| I/O Port | 16/297 | 6% |

**最终Fmax35.944MHz；目标50MHz；最差setup -7.821ns；1240个setup端点失败；TNS -1776.880ns。**
综合估算为57.237MHz，只是不含最终实际布线的估计。Hold报告未发现违例。外设I/O预算未完整约束，不能声称板级电气时序验收完成。

## 各模块资源

以下来自同一次构建的综合层级XML，均为**模块自身，不含子模块**，可按列求和。
LUT/ALU是综合器分类，不能直接与布局报告Logic/CLS相加比较。BSRAM综合计数77，实际映射后98；M27×36是乘法原语数量，**不是物理DSP块数**。
DX包络另含1个MULTALU27X18、2个MULT12X12；全设计实际物理DSP98块。AxiSynthEndpoint仅为包装，已优化成连线。

| 模块 | LUT | ALU | FF | BSRAM | SSRAM | M27×36 |
|---|---:|---:|---:|---:|---:|---:|
| SynthSystemTop | 40 | 62 | 68 | 0 | 0 | 0 |
| KeyboardSampler | 217 | 4 | 93 | 0 | 0 | 0 |
| LatencyKeyThresholds | 141 | 18 | 64 | 0 | 0 | 0 |
| SynthBootSequencer | 122 | 0 | 404 | 2 | 0 | 0 |
| SynthKeyboardSource | 795 | 35 | 1255 | 0 | 0 | 0 |
| SynthUartControl | 820 | 468 | 2110 | 0 | 0 | 0 |
| UartRx | 55 | 0 | 33 | 0 | 0 | 0 |
| EncoderUartTx | 243 | 0 | 30 | 0 | 0 | 0 |
| SynthCommandArbiter | 507 | 0 | 392 | 0 | 0 | 0 |
| SynthAxiMaster | 664 | 94 | 678 | 0 | 0 | 0 |
| AxiSynthEndpoint | 0 | 0 | 0 | 0 | 0 | 0 |
| AxiVoiceEndpoint | 2058 | 93 | 2966 | 0 | 36 | 0 |
| AxisSynthSystem | 226 | 102 | 304 | 0 | 48 | 0 |
| VoiceSynthEngine | 5553 | 1919 | 5113 | 19 | 0 | 16 |
| VoiceModulation | 4017 | 71 | 4247 | 2 | 34 | 2 |
| AxisLfoStep | 540 | 241 | 665 | 4 | 3 | 3 |
| AxisFmOperator | 1059 | 461 | 935 | 12 | 0 | 7 |
| AxisEnvelopeMulti | 237 | 0 | 153 | 0 | 0 | 0 |
| AxisEnvelopeSegment | 92 | 96 | 361 | 0 | 0 | 0 |
| AxisDxEnvelope | 605 | 238 | 375 | 2 | 0 | 2 |
| AxisFxEngine | 689 | 497 | 1343 | 0 | 0 | 0 |
| AxisStereoDelay | 546 | 632 | 850 | 18 | 0 | 14 |
| AxisSchroederReverb | 1348 | 399 | 1098 | 18 | 0 | 4 |
| SynthPcmOutput | 227 | 71 | 106 | 0 | 0 | 0 |
| **合计（综合）** | 20801 | 5501 | 23643 | 77 | 121 | 48 |

## 运算周期不是单拍组合延迟

50MHz每拍20ns。一个模块可以执行多拍，但其每一段寄存器之间的组合逻辑与布线仍必须满足20ns。
现有实现并非把整个模块压在一拍：

| 单元/工作量 | 当前周期 | 50MHz下对应时间 | 依据 |
|---|---:|---:|---|
| AxisFmOperator（原生及DX） | 10拍/算子任务 | 0.20μs | 4256组算子向量 |
| AxisDxEnvelope | 最多6拍 | 0.12μs | 10096组EG向量 |
| AxisLfoStep | 5级，II=1 | 0.10μs | RTL流水/接口合同 |
| VoiceModulation八条路由 | 13拍/声部 | 0.26μs | 描述符/操作数/乘积/累加流水 |
| AxisStereoDelay | 10拍 | 0.20μs | 80000采样仿真 |
| AxisSchroederReverb | 60拍 | 1.20μs | 100000采样仿真 |
| 共享FX整链 | 72拍 | 1.44μs | AXI整链仿真 |
| Voice+LFO，8声部×6算子 | 最重866拍 | 17.32μs | 混合调制仿真 |
| Voice+LFO+FX+接口 | 最重940拍 | 18.80μs | 整板仿真 |
| 一个音频采样周期 | 1024拍 | 20.48μs | 50MHz/1024=48828.125Hz |

数值正确和940/1024的调度预算已验证，但它们不能替代50MHz的物理时序。UART/AXI控制具有反压及音频优先等待，不是固定单拍事务。键床扫描包含ADC串行采集与去抖，不能用940拍代表按键到耳机的总延迟。

## 最新长路径

| 路径 | 数据延迟 | Setup余量 | 定位 |
|---|---:|---:|---|
| reg_mod_pan[0] → reg_left_product[47] | 27.776ns | -7.821ns | Unity减声像后接乘法，包含明显布线延迟 |
| reg_voice[1] → n13722_s4/A[23] | 26.975ns | -7.656ns | 声部数组选择→smooth→wire_pan_sum→限幅→后级输入 |

第一条延迟中包含实际布局连线；不能将27.776ns全归因于乘法器本体。第二条的n13722_s4是工具生成名称，路径明细确认经过wire_pan_sum，未仅凭名称猜测RTL对象。
当前报告只列最差25条setup路径，主要集中于上述两类；**其他模块没有出现在这25条里，不表示其已单独证明通过50MHz**。目前没有按每个模块单独约束、布局得到的Fmax，不能提供虚构数字。

## 已定位但暂停实施的修复

1. 在声部路由计算期间预读gain/pan及目标值，提前计算平滑值，切断数组选择、平滑、调制相加、限幅连续长链。
2. 提前寄存32位左声道增益Unity-pan，再执行纯乘法，固定表达式位宽。
3. 重新评估命令浅队列的分布式RAM映射，降低寄存器与跨区布线压力。

用户要求先停止调试并上传GitHub，因此以上尚未改入RTL。当前共享算子保留两条相位/增益乘法通道，并为插值和morph保留独立乘法器，算子总延迟仍为10拍。

## 证据

- [整板JSON](reports/gowin-board-summary.json)
- [16组回归与源码哈希](reports/board-tested-inputs.json)
- 发布快照附同一构建的资源层级XML、PnR报告与timing_paths。严格RTL风格/组合深度门禁仍有失败项，不能称为全部交付门禁通过。
