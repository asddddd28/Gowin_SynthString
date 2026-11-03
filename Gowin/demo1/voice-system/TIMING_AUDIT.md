# 全系统时序归属分析与 VoiceSynthEngine 优先调试计划

**19:51 更新：FM插值乘法已寄存，现有50MHz约束下setup/hold违例为0。** Fmax50.037MHz，最小setup slack仅+0.015ns，TNS0；5000条展开setup路径逐弧核对通过。算子10拍、整链948/1024拍不变，DSP94、BSRAM98不增加。本轮未烧录；余量仍小，下一步优先处理Voice音色RAM到请求构造路径。详见 [完整结果、资源与近临界路径](FM_INTERPOLATION_PIPELINE.md)。下文保留各历史基线，不代表当前仍有失败终点。

**19:18 更新：FX命令校验及执行动作寄存完成。** FX/Delay/Reverb失败终点164→0，整板222→89，Fmax45.742MHz，WNS−1.862ns，TNS−84.362ns；音频仍948/1024拍。剩余为FM波表插值27个、Voice内部57个、命令头到Voice5个，仍未通过50MHz、未烧录。见 [P0-B控制路径结果](FX_CONTROL_PIPELINE.md)。下述记录保留为历史基线。

**18:51 更新：Voice 声像乘法分拍已完成。** 相对 P0-A，Fmax 34.028 → 45.327 MHz，WNS −9.387 → −2.062 ns，失败终点 347 → 222，DSP 98 → 94；声像失败路径已消除，满载整链948/1024拍。当前主要瓶颈为命令头到 FX/Reverb 的控制长链，仍未通过50MHz、未烧录。详见 [声像分拍与最新完整分布](VOICE_PAN_PIPELINE.md)。下述 P0-A 与原始分析保留为历史基线。

**18:17 更新：P0-A 完成反压隔离已实施并回归。** 50 MHz 独立构建的失败终点为 347（原 1240），TNS −625.236 ns；完成计数器起点违例为 0。但 Voice 声像乘法 WNS 变为 −9.387 ns、Fmax 34.028 MHz，仍未达到目标。完整修改、资源、验证与下一步见 [P0-A 实验结果](COMPLETION_ISOLATION.md)。以下保留的是修改前全覆盖分析及建议审查，不能当作当前候选的端点分布。

分析日期：2026-11-02。目标保持 **50 MHz / 20 ns**。
本轮扩大时序报告、分析 RTL 与寄存边界，没有修改设计 RTL、没有烧录。

## 结论

1. 已展开 5000 条 setup 路径，覆盖报告中的 **全部 1240 个失败端点**，每个端点取其最差路径。不是只分析原来的最差 25 条。
2. **VoiceSynthEngine 优先**：709 个失败终点，占 57.2%；其中 145 条源于模块内部，564 条由 AxiVoiceEndpoint 跨模块进入。
3. 全系统 **1023 条失败路径从 AxiVoiceEndpoint 的 cnt_completion 出发**，占 82.5%。主要是完成队列反压、接收判定、配置/清空控制到寄存器使能的长链。
4. 按终点引脚分类，1007 条落在 CE/CEA（使能）上，179 条在 D，54 条在 DSP 的 A 输入。处理控制路径与处理音频算术路径同样重要。
5. 后加模块中，Delay、FM 插值、DX 包络存在本体计算违例；Reverb 和 Modulation 本次失败终点主要由外部命令控制长链造成。**AxisLfoStep 本次没有失败 setup 终点。**

因此先执行独立的 **P0：公共完成反压隔离 → 单独回归/构建 → 重新建立基线**。之后以 VoiceSynthEngine 为第一个计算模块，采用“单模块定位与修改 → 带真实反压的接口联调 → 整板回归”。共享控制问题不再列为后续第 5 步。

## 分析依据与覆盖范围

原候选构建：`reports/gowin-shared-operator`，16:06 完成。
独立诊断构建：`reports/timing-audit-20261102`，16:58 完成。它只在 SDC 中增加报告命令；时钟、CST 和布局布线选项保持不变。Gowin 为独立工程自动补跑了综合。

- 42 个源码、约束与素材文件的哈希与原候选一致。
- 综合层级资源 XML、PnR device.cfg 与原候选一致。
- 原候选最差 25 条路径的起终点、slack、数据延迟、时钟偏移与新报告逐条一致。
- 总体仍为 Fmax **35.944 MHz**，setup WNS **−7.821 ns**，TNS **−1776.880 ns**，1240 个失败端点。
- 当前资源仍为 Logic 46%、CLS 82%、BSRAM 84%、DSP 84%。

本轮实际使用的报告请求：

```tcl
report_timing -setup -max_paths 5000 -max_common_paths 1
report_timing -hold -max_paths 100 -max_common_paths 1
report_timing -recovery -max_paths 100 -max_common_paths 1
report_timing -removal -max_paths 100 -max_common_paths 1
report_high_fanout_nets -max_nets 200
```

`max_common_paths 1` 表示每个端点保留最差一条；覆盖的是所有失败端点，并非列举同一端点的全部次差组合路径。语法依据 [Gowin 时序约束指南](https://cdn.gowinsemi.com.cn/SUG940-1.3_Gowin%E8%AE%BE%E8%AE%A1%E6%97%B6%E5%BA%8F%E7%BA%A6%E6%9D%9F%E7%94%A8%E6%88%B7%E6%8C%87%E5%8D%97.pdf)。

第 1239、1240 条显示为 `−0.000 ns`，是负数舍入，仍计入失败。不能用浮点数 `< 0` 筛选后误报只有 1238 条。逐条显示值求和为 −1776.939 ns，与工具内部未舍入 TNS 相差 0.059 ns；总体 TNS 采用工具值。

已逐条核对 5000 条路径的数据弧延迟和与摘要数据延迟一致（容许报告小数舍入误差）。Hold 失败端点为 0；报告的最小 hold / recovery / removal 余量分别为 +0.072 / +3.520 / +1.597 ns。

本结果针对当前 SDC 的已约束路径。ADC、UART、I2S 等外部接口的 input/output delay 预算尚未完整建立，不能据此宣称板级 I/O 时序已验收。

## 按失败终点所属模块统计

以下为叶级归属，不把子模块再次计入父模块。数量是位级端点数，不是独立算法数。

| 终点模块 | 失败端点 | 最差 setup slack | 主要来源 |
|---|---:|---:|---|
| VoiceSynthEngine | 709 | −7.821 ns | 内部 gain/pan/调制求和 145；Endpoint 控制输入 564 |
| AxisSchroederReverb | 388 | −2.531 ns | 全部来自 Endpoint 控制链，落在状态/参数/计算寄存器使能 |
| VoiceModulation | 60 | −0.958 ns | Endpoint 控制链到 LFO/路由启用标志 |
| AxisStereoDelay | 29 | −4.867 ns | 干湿混合的补系数、乘法与求和 |
| AxisFmOperator | 29 | −4.854 ns | 波表差分、插值乘法、插值求和 |
| AxisDxEnvelope | 11 | −1.827 ns | 本体电平更新 7；Operator 接收使能输入 4 |
| AxiVoiceEndpoint | 10 | −3.051 ns | 完成队列状态经运行时 ready 返回命令队列 |
| AxisFxEngine | 4 | −1.970 ns | 命令译码/接受条件到 draft 参数使能 |
| **合计** | **1240** | **−7.821 ns** | |

本次没有失败 setup **终点**的模块：SynthSystemTop、KeyboardSampler、LatencyKeyThresholds、SynthBootSequencer、SynthKeyboardSource、SynthUartControl、UartRx、EncoderUartTx、SynthCommandArbiter、SynthAxiMaster、AxiSynthEndpoint、AxisSynthSystem、AxisLfoStep、AxisEnvelopeMulti、AxisEnvelopeSegment、SynthPcmOutput。

其中 AxiSynthEndpoint 是包装层。AxisSynthSystem 虽然没有失败终点，其组合 `flag_advance`、结果仲裁、ready 连线处于多条跨模块失败路径中；“没有失败终点”不等于“不参与长路径”。

## 跨模块路径与模块内部路径

数据延迟包含 clock-to-Q、单元组合弧和布线，不包含起点时钟树延迟。单元列包含 clock-to-Q；各项因小数舍入可有数 ps 差异。

| 起点模块 → 终点模块 | 失败端点 | 最差 slack | 数据延迟 | 布线 | 单元 |
|---|---:|---:|---:|---:|---:|
| VoiceSynthEngine → 自身 | 145 | −7.821 | 27.776 | 21.526 | 6.249 |
| AxiVoiceEndpoint → VoiceSynthEngine | 564 | −6.615 | 26.304 | 23.442 | 2.862 |
| AxisStereoDelay → 自身 | 29 | −4.867 | 24.794 | 17.579 | 7.213 |
| AxisFmOperator → 自身 | 29 | −4.854 | 24.809 | 17.528 | 7.282 |
| AxiVoiceEndpoint → 自身 | 10 | −3.051 | 22.996 | 19.991 | 3.005 |
| AxiVoiceEndpoint → AxisSchroederReverb | 388 | −2.531 | 22.239 | 18.562 | 3.676 |
| AxiVoiceEndpoint → AxisFxEngine | 4 | −1.970 | 21.659 | 17.863 | 3.794 |
| AxisDxEnvelope → 自身 | 7 | −1.827 | 21.754 | 11.371 | 10.381 |
| AxiVoiceEndpoint → VoiceModulation | 60 | −0.958 | 20.656 | 17.604 | 3.051 |
| AxisFmOperator → AxisDxEnvelope | 4 | −0.934 | 20.521 | 16.982 | 3.538 |

单位均为 ns。每行的延迟拆分来自该组最差路径，不代表组内所有路径相同。

## VoiceSynthEngine：第一优先对象

### 内部 145 个端点的具体归属

| 路径族 | 端点数 | 最差 slack | RTL 定位 |
|---|---:|---:|---|
| `reg_mod_pan → reg_left_product` | 32 | −7.821 ns | VoiceSynthEngine.v:492，`audio * (Q_UNITY-pan)` |
| `reg_voice → pan 平滑/调制/限幅 → DSP 输入或 reg_mod_pan` | 54 | −7.656 ns | :138、:159、:512；27 个 DSP 输入端点及 27 个 FF 端点 |
| `reg_operator → 调制求和/限幅 → reg_operator_request` | 32 | −3.196 ns | :193、:466；按算子拓扑选择并累加已有算子输出 |
| `reg_voice → gain 平滑/调制/限幅 → DSP 输入` | 27 | −2.647 ns | :137、:159、:511 |

pan/gain 的 DSP 输入名为 `n13722_s4/s5`、`n13529_s4/s5`。路径中分别可见 `wire_pan_sum`、`wire_gain_sum`，并以 DSP A 引脚结束；不能因为网表合并后的终点不是 RTL 寄存器名，就把这类路径漏掉。

最差左声像路径中，布线占 **77.5%**：进入 DSP 的一段线为 **6.494 ns**，DSP 输出返回逻辑的一段线为 **11.926 ns**；该路径经过的 DSP 组合弧为 **2.875 ns**。因此它同时涉及算术链切分和物理映射/连线，不能把 27.776 ns 全记为“乘法器慢”。

`reg_voice` 选择、比较差值、计算平滑步长、加减平滑、叠加调制、限幅，仍处于同一寄存器间路径中。`smooth()` 是组合函数，写成函数不会自动增加流水级。

### 入口/完成接口的 564 个端点

代表路径：

```text
AxiVoiceEndpoint.cnt_completion
  → cnt_completion < 4
  → AxisSynthSystem.flag_advance / 完成仲裁
  → VoiceSynthEngine.i_m_axis_tready
  → o_s_axis_tready / flag_accept / flag_control_apply
  → mem_gain、mem_pan、目标值、increment、age 等寄存器使能
```

最差为 `cnt_completion[2] → mem_pan[7][13]/CE`：26.304 ns，其中布线 23.442 ns，约 **89.1%**。这类路径不是 gain/pan 数值乘法，而是“本拍是否允许接受/更新”的控制。

相关 RTL：AxiVoiceEndpoint.v:173、:525；AxisSynthSystem.v:55、:95、:194；VoiceSynthEngine.v:95、:127、:179。具体逐引脚路径以 CSV/JSON 为准。

### 单模块调试顺序与验收

1. **先完成公共 P0**：切点优先选择 AxisSynthSystem.v:55 的公共完成汇聚处，覆盖 Voice、FX 和 Legacy 三支。以现有 168 位输出保持寄存器加一个备用槽，构成总容量 2 项的完成缓冲；上游是否接受只由本地占用状态决定，不组合依赖 Endpoint ready。Endpoint 的 `cnt_completion < 4` 仍只控制缓冲的出队。此为待实现方案，不是已经验证的 RTL。仅在 Voice 输出加缓冲不能同时切断 Reverb 分支。注册 credit 是另一个可选设计，不要求与该缓冲同时引入。
2. **gain/pan 预取与分段平滑**：缓存声部值与目标值，拆开比较/差值、步长与更新、调制相加与限幅。优先利用现有调制等待阶段，缓存携带 voice/valid，保证一次声部只更新一次。
3. **声像增益与乘法边界**：提前寄存明确位宽的 `Q_UNITY-pan`，核查乘法输入/输出寄存器是否映射进 DSP，以及乘积重组是否仍跨远距离逻辑。保留 Q26 的截断、符号和饱和顺序。
4. **算子调制求和**：把有条件累加梳理成受控的加法树或分段求和，尽可能放在既有程序/状态预取阶段。继续核查音高比例计算，但本次报告未把它列为失败路径族，不能将其写成已确认根因。

必须覆盖：8 声部 × 6 算子、活动/空闲声部交替、禁用快通路、voice stealing、释放尾音、实时参数目标变化、零/满声像、正负满幅、提交/清空/重试、复位、完成结果持续反压。

**当前快速分支安全，修改时需保留不变量**：空闲声部和禁用状态从 state 1 转 state 8，state 1 显式清零左右乘积，因此不会消费陈旧的调制增益/声像产生音频。此前提醒针对未来预计算改动，并非已发现当前数据串音。与此同时，state 1 在这些分支仍会更新 `mem_gain/mem_pan`；把写回全部搬到只在活动声部执行的 state 15 并不严格等价。

现有验收使用采样 tick 到最终 PCM 小于 1024 拍的合同，最重值 940 拍，合同内余量 84 拍。每算子增加 2 拍，在当前串行调度下增加 48×2=96 拍；每声部增加 2 拍为 16 拍。Voice 单独的 866+96=962 拍只证明 Voice 服务时间可小于采样周期，不证明下游 FX 和固定 DAC 取样点仍满足现有合同。Voice/FX 之间确有队列，未来可以另行设计跨帧流水及 PCM 预填充，让总延迟大于一周期而吞吐保持一采样/周期；这需要重验队列占用、时延变化和 underrun，不能仅靠 962<1024 判通过。P0 完成通道隔离不直接增加音频算子拍数；零新增音频拍数的优化不消耗这 84 拍。修改不用未经证明的 multicycle/false-path 掩盖单拍长路径。

单模块必须同时验证数值、状态、握手与 50 MHz 布局后时序。独立实现通过后，回到 Voice + Endpoint/Runtime 小系统测试，再做整板 PnR；独立布局的频率不能直接当作整板频率。

## 后续新模块的调试顺序

| 顺序 | 模块/边界 | 本版定位 | 需要检查的具体切分 |
|---|---|---|---|
| P0-A | 公共完成汇聚与反压 | 1023 条从 cnt_completion 出发的失败路径 | AxisSynthSystem 本地两项缓冲；独立回归/PnR后重新统计，不能保证全部消失 |
| P0-B | FX 命令字段译码 | 3 条从 reg_command_head[322] 出发的失败路径 | 独立于完成反压检查，寄存必要字段或本地预译码，再建立基线 |
| 1 | VoiceSynthEngine | 内部 145 个失败终点及 P0 后剩余入口问题 | 逐项对照实验：DSP 映射、平滑与求和、声像补系数；先保数值和状态等价 |
| 2 | AxisFmOperator | 插值路径 29 个端点 | 差值、分数乘法、加回基值的流水边界；与每采样 48 次任务预算联算 |
| 3 | AxisStereoDelay | 干湿混合 29 个端点 | `UNITY-wet` 预计算；dry/wet 乘积与求和分级；帧号随数据移动 |
| 4 | AxisDxEnvelope + Operator 接口 | 本体 7、接口 4 | rising level 更新与指数/shift 生成分开；使能本地化；保持 DX 速率/电平语义 |
| 5 | 存储与布局拥塞 | 宽浅命令队列与本地状态选择 | 依据当前 RAM 实际映射比较 FF、SSRAM、BSRAM 方案；不预设 CLS 降幅 |
| 6 | AxisLfoStep | 本次无 setup 失败终点 | 保留现有 5 级流水，随调制联调验证，不因“后加入”就重写 |

Reverb 的 388 个失败终点不能解释成 388 处混响算法故障。代表路径经过 FX 的命令接受与 `flag_clear_reverb`，影响混响状态/工作寄存器；在 P0 中处理公共传播，之后复查是否仍需本地隔离清空控制，同时保留音频空闲边界和清尾音语义。VoiceModulation 同样先随 P0 处理，之后按新报告决定是否还需局部修改。

### 布线压力与时钟

高扇出报告中，时钟约 23988 个负载、复位别名 `o_mux_en_d` 约 21826 个负载，命令头位 `reg_command_head[320]` 为 1837，Voice `reg_voice[0]` 为 774。`o_mux_en` 在 KeyboardSampler 中直接等于复位输入，不应误认成新的音频控制信号。

局部拥塞报告列出多个 100% 网格；结合 CLS 82%、DSP/BSRAM 84% 和具体路径的布线占比，物理拥塞需要持续跟踪，但不能只凭网格列表断言每条长线都由该网格造成。

时钟仍有 PR1014 通用布线警告。最差数据路径的 clock skew 仅 −0.019 ns，说明这条路径的主要超时是数据路径；时钟网络警告需要单独处理，不能用它替代数据路径诊断。

## 现有验证证据与门禁

本轮没有 RTL 修改，不重复运行已经通过的 16 组功能回归。输入哈希与相应证据匹配；功能正确不等于 50 MHz 时序合格。

VoiceSynthEngine 现存严格门禁 `voice-engine/reports/board-engine-gate.json`：compile=passed；ast、readability、comment、naming、profile=failed；testbench、toolchain=not_requested（该静态命令的范围）。外部功能仿真通过、Gowin 构建完成但物理时序失败，均作为独立证据，不能合并成“全部门禁通过”。

## 外部建议复核（2026-11-02）

复核范围为本轮用户提供的文本、当前 RTL、5000 条路径 JSON、综合日志/资源 XML，以及本机 Gowin GW5A 原语库。以下为分析结果，未执行 RTL 修改或新的 A/B 构建。

### 采纳的部分

- 将公共完成反压隔离设为独立 P0，单独回归、PnR、更新全端点基线，再按新的最差路径处理 VoiceSynthEngine。原排期把共享控制项另列为第 5 步容易造成误读，已修正。
- 明确公共切点为 AxisSynthSystem 的 `flag_advance`/完成汇聚处；补充命令字段译码、缓冲守恒、反压保持和有效输出 X 检查。
- 声像/干湿补系数预计算、去除不必要的算术寄存器复位、显式复用平滑结果，均可作为独立候选实验；按数值和状态语义逐项验证，不一次修改三个模块后无法区分收益。
- 当前非活动/禁用分支安全，给其状态转移与清零行为加保护性检查；继续保留 LFO 本体，使用完整时序覆盖判断是否需要修改。

### 必须纠正或限定的判断

**1. DSP 支持异步复位；“复位必然把乘积寄存器赶出 DSP”不成立。**

本机 `IDE/simlib/gw5a/prim_sim.v` 中，MULT27X36 的定义位于 7015 行，具有 `PREG_RESET`、`OREG_RESET` 和 `MULT_RESET_MODE="SYNC" // SYNC,ASYNC`（7035、7043、7045 行）；P/输出寄存器的异步复位过程见 7498、7538 行。MULTALU27X18 同样提供该模式。官方 [UG305：Arora V DSP 指南](https://cdn.gowinsemi.com.cn/UG305E.pdf) 的 MULT27X36 原语章节也给出这些选项。

因此已证明的是“当前若干终点在 fabric FF，且 DSP 输出后有很长连线”，未证明的是“复位导致该映射”。还需检查位宽拆分、乘积重组加法、状态下的清零/保持与 CE 条件，以及寄存器吸收约束。可做去复位 A/B，但不能承诺消除 203 条路径或减少 10 ns；Voice 内部 145 条还包括 DSP 输入前的平滑和算子调制求和，并非都是乘积输出寄存器。

移除启动复位也不能顺手移除 state 1 的左右乘积清零：后者是运行时静音语义。应逐个证明有效读取前已完成写入，并保留 valid、FSM、清空行为的初始化；无效拍内部数据出现 X 可接受，有效 PCM/完成包出现 X 不可接受。若调整 always 块，应确保单一写入者和无复位寄存器的真实推断语义。

**2. 公共本地缓冲与 Endpoint 注册 credit 不必同时实施。**

现有公共 `reg_completion` 已是一项输出保持。增加一个备用槽形成总计两项、上游 ready 仅由本地占用决定的缓冲，可以切断 Endpoint ready 的同拍向上传播；Endpoint 仍按 `cnt_completion<4` 接收出队数据。

另一种方案是注册 credit 并预留在途容量。`<3` 单阈值不是通常意义的迟滞，必须写清一拍在途量与复位初值。若选此方案，`.i_m_axis_tready(...)` 与 `flag_completion_put` 必须使用同一个实际握手条件，不能只修改前者而继续按旧 `cnt_completion<4` 写入 FIFO。单独给 ready 加寄存器未必安全，但“注册 ready 会破坏 AXI”也不是普遍事实。

额外约 168 个数据 FF 是一个备用槽的概算；是否增加首次完成延迟、满转空是否有气泡，要由具体缓冲结构和仿真确认。它不直接给音频算子增加拍数，但控制命令生效时间与音频优先调度仍需回归。

**3. 源路径计数应为 1023 + 3，不能承诺修完只剩 210 条。**

`cnt_completion` 出发：Voice 564、Reverb 388、Modulation 60、Endpoint 自身 10、FX 参数 1，共 1023。
`reg_command_head[322]` 出发：FX 参数 3。
AxisFxEngine 的 4 个失败端点是两类来源，不能全部列为命令字段。

从旧报告集合扣除上述两类后剩余 214：Voice 内部 145 + Delay 29 + FM 29 + DX 内部 7 + Operator→DX 接口 4。此为旧集合分类，不是新构建预计剩余量；新布局与局部使能网络可能产生新的关键路径。P0 后必须重新统计 WNS/TNS/全部失败端点，不能只检查旧起点名称是否消失。

**4. 平滑器“内联四次”不等于“四份物理电路”；搬写回也并非全分支等价。**

综合器可能共享相同表达式。没有对应综合网表/资源对照，不能承诺减少两份 32 位平滑器。

当前 state 1 对禁用/非活动声部也平滑 `mem_gain/mem_pan`，state 15 则不会执行。可达的反例是：保留活动声部但禁用发声，接受参数目标更新，初值 gain=0、target=2^26。一个禁用采样后，当前实现的 gain=1048576；全部搬到 state 15 的版本仍为 0。重新启用后的下一次 smooth 分别为 2080768 与 1048576，结果不同。因此必须保留跳过 state 15 分支的更新语义，或明确接受并验证行为变更，不能直接宣称零风险等价。

**5. RAM 与 CLS 收益的估算用了不符合当前实现的前提。**

`mem_route_config` 已在 state 3 同步读入 `reg_route_descriptor`；综合日志记录 RAM 提取，完整 PnR 报告含 `gowin_add_SDPB_mem_route_config.../CEA`。VoiceModulation 自身综合资源是 2 个 BSRAM、34 个 SSRAM、4247 个 FF，不能把整个路由表再次当作 4096 个可回收 FF。LFO 配置也存在 RAM 提取及部分 RAMREG 拆分，应按实际映射分析，不能笼统称为纯 FF 数组。

`reg_command[0:3]` 确有 `syn_ramstyle="registers"`，4×424=1696 位，加 424 位队首，值得单独比较 FF、分布式 RAM、BSRAM。但宽浅 RAM 的块数由宽度、端口和最小块形状决定，不能只按总位数估算节省。

程序/状态 RAM 的逻辑地址确有每 8 行用 6 行的空洞，但 64 行压为 48 行，不等于释放 25% 物理块。官方 [UG300：Arora V 存储器指南](https://cdn.gowinsemi.com.cn/UG300E.pdf) 列出的 512×32/36 等固定配置说明了这种粒度差异。要回收块数可能需要跨表打包、改变位宽或访问调度；不能承诺 CLS 从 82% 降到 72%。

**6. 866 与 940 是不同边界；不能用前者替代整链验收。**

`tb_axi_fx.v:364` 和 `tb_synth_system.v:70` 明确检查 tick 到最终输出小于 1024 拍。当前固定 DAC 取样以及轻载转重载没有额外预填充保障。仅 Voice 新增 96 拍，也可能使同一采样的整链延迟从 940 增至约 1036；不是“只有同时修改 FX 才超”。反之，总延迟大于周期也不在所有架构下等于吞吐不足：若重新设计帧间流水/预填充，可以另行验证。零新增音频拍数的改动应与这类流水改动分别标注。

**7. 保持精度的方向正确，但位宽须区分有符号与无符号。**

不在没有范围证明时收窄音频操作数。即使声像系数已限幅到 [0,2^26]，也需要 27 位无符号或 28 位有符号；把 27 位系数直接 `$signed`，会把 2^26 解释为负数。若采用建议文本的 ±6×2^26 保守音频上界，则需要 30 位有符号，而不是 29 位有符号。不能仅依据乘法器端口宽度决定格式。

**8. 量化目标使用负 slack，并区分测量值与预测收益。**

| 当前路径族 | 至少需要补足的最差余量 | 布线/单元数据 | 验证指标 |
|---|---:|---|---|
| 完成反压到 Voice | 6.615 ns | 23.442 / 2.862 ns | 控制链已被寄存边界切断；新路径、WNS/TNS/端点数改善 |
| Voice 左声像 | 7.821 ns | 21.526 / 6.249 ns | DSP 吸收/重组与长网线实际变化，不承诺自动减少 10 ns |
| Delay 混合 | 4.867 ns | 17.579 / 7.213 ns | 系数、乘积和求和分段后的时序、数值与延迟 |
| FM 插值 | 4.854 ns | 17.528 / 7.282 ns | 插值链的实际新 slack 与每采样服务时间 |
| DX level→shift | 1.827 ns | 11.371 / 10.381 ns | 电平/指数计算等价与新路径延迟 |

DX 单元占比是 47.7%，布线是 52.3%；可称“逻辑占比相对较高”，不能称其已被证明是唯一逻辑受限模块。每条路径的 setup 要求还包括目的寄存器时序弧等，不能只用 `data_delay-20` 代替 slack。

### 补充验证合同

- 随机及持续反压、空/满/同时入出队、reset/清空、Voice/FX/Legacy 并发完成、仲裁公平性；保持 VALID 等待期间 payload/tag/opcode 稳定。
- 按实际握手维护记分板：每个仲裁接受的完成包在下游恰好消费一次；复位时显式取消在途项。命令重试、合法序号跳变和不同执行域分别建模，不用简单的全局序号连续性代替守恒。
- 不能直接使用所建议的三项计数器相等关系。当前 `LEGACY_ENABLE=0`，AxisSynthSystem.v:167–170 的 `o_count_executed/replayed` 为 0，`o_count_rejected` 属于 UnsupportedDomain；它们并不是全部 Voice/FX 命令总计，SynthSystemTop 的状态字也未按建议所述接入三者。
- 使用有效拍 X 检查，包含首个有效 PCM、复位中断再启动、非活动声部、持有输出、清尾音。Verilog-2001 TB 可用 case equality / reduction-X 检查；现有 FM、Delay、Voice 数值比对已有 `!==`，仍应补覆盖点，不能说目前完全没有 X 防护。
- 保持音频 overrun、FX/PCM dropped、DAC underrun 为 0，验证实际首次输出与轻重载转换。命令等待周期和音频算子周期分别统计。

以上将候选的“理论覆盖集合”和“已测得优化收益”分开；后者目前尚未产生。

## 文件与复现

- [1240 条失败端点及延迟拆分](reports/timing-audit-20261102/analysis/setup-violations.csv)
- [5000 条 setup 路径](reports/timing-audit-20261102/analysis/setup-paths.csv)
- [模块分组、路径族与代表弧 JSON](reports/timing-audit-20261102/analysis/summary.json)
- [原始扩大报告](reports/timing-audit-20261102/impl/pnr/synth_fm1_tr_content.html)
- [诊断 SDC](reports/timing-audit-20261102/audit.sdc)
- [构建日志](reports/timing-audit-20261102/run.log)
- [源码与原候选保全校验](reports/timing-audit-20261102/provenance.json)
- [分析脚本](model/audit_timing.py)

重新解析报告无需重新构建：

```powershell
python model/audit_timing.py reports/timing-audit-20261102/impl/pnr/synth_fm1_tr_content.html reports/timing-audit-20261102/analysis
```

以上修复步骤是已定位问题对应的实施计划，本轮尚未改入 RTL。诊断构建产物未烧录，也不代表新的已验收固件。
