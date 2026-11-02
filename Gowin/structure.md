# SynthString 当前结构与目标架构

更新：2026-11-02。硬件：Tang Mega 60K / GW5AT-60。主机：Tauri + React + Rust。

本文是当前工程与后续实现的架构入口。**“现有”指已上板的演奏基线；“候选 RTL”包含尚未上板验收的新子系统及整机顶层；“改造”和“新增”是待实现设计。** 提议中的模块名称不代表已经存在对应 RTL 文件。旧演奏工程保留，新整机独立位于 `demo1/voice-system`。

最新整机进展：**[完整 hierarchy 与协议](demo1/voice-system/SYSTEM.md)** 已连接ADC键盘、启动ROM、UART协议5、命令仲裁、AXI Master、Voice/LFO/Delay/Reverb、PCM FIFO与PT8211输出，共24种实际实例化的功能模块。共享乘法器与调制流水优化后，8声部48算子满载仿真940/1024拍。板级Delay每声道8K采样（约167.77ms），模块库默认32K。ABI为0x00010005；新版Tauri/Rust [Voice Studio](demo1/voice-system/app/README.md) 已适配四音色、六算子编辑、演奏、FX和遥测，整页滚动已获用户确认。**本轮最终时序、资源、烧录和硬件测试以 [BOARD_TEST.md](demo1/voice-system/BOARD_TEST.md) 为准**。严格RTL规范门禁仍有未解决项。

最新音色适配：[FM1 / DX7四音色说明](demo1/voice-engine/FM1.md)。新增 `AxisDxEnvelope`、DX PM/反馈换算、键位/力度/速率缩放及安全格式切换。四槽启动载入PIANO 2、ORGAN 1、BASS 3、BRASS 2；保存128条原厂数据，但只开放已验证的4条。16组RTL回归覆盖本轮变化，源码与测试日志哈希见 [board-tested-inputs.json](demo1/voice-system/reports/board-tested-inputs.json)。历史综合估算不能代替最终布线结果。

## 1. 图与实现依据

| 内容 | 可编辑图 | 预览 |
| --- | --- | --- |
| 当前：固定阶段、共享计算核心 | [current-architecture.excalidraw](demo1/docs/modular-pipeline/diagrams/current-architecture.excalidraw) | [PNG](demo1/docs/modular-pipeline/diagrams/current-architecture.png) |
| 目标：程序驻留、按依赖发射任务 | [target-architecture.excalidraw](demo1/docs/modular-pipeline/diagrams/target-architecture.excalidraw) | [PNG](demo1/docs/modular-pipeline/diagrams/target-architecture.png) |

将 `.excalidraw` 文件导入 Excalidraw 可继续编辑。目标图中橙色表示改造，蓝色虚框表示新增；实线是任务/数据，橙色虚线是配置/控制，绿色是最终音频。

- 当前顶层：[LatencyAxisTop.v](demo1/keyboard-latency/src/LatencyAxisTop.v)。
- 当前引擎：[ParallelSynthEngine.v](demo1/keyboard-parallel/src/ParallelSynthEngine.v)、[SynthTaskPrefetch.v](demo1/keyboard-parallel/src/SynthTaskPrefetch.v)、[ParallelVoiceChain.v](demo1/keyboard-parallel/src/ParallelVoiceChain.v)。
- 配置与状态：[StudioVoiceStore.v](demo1/keyboard-studio/src/StudioVoiceStore.v)。
- 上板验证与资源：[keyboard-latency/README.md](demo1/keyboard-latency/README.md)、[gowin_summary.json](demo1/keyboard-latency/reports/gowin_summary.json)。
- 五个功能板块的逐项源码映射：[module-layers.md](demo1/docs/modular-pipeline/module-layers.md)、[module-layers.json](demo1/docs/modular-pipeline/module-layers.json)。
- 主机源码：[desktop-tauri](demo_test/desktop-tauri)。

旧设计中的 512 拍 / 约 96 kHz 模型属于历史方案。本文使用当前上板的 1024 拍 / 48.828125 kHz 基线。

## 2. 当前已经具备的结构

### 2.1 连接与执行

```text
实体 32 键
  → KeyboardSampler（多路复用 ADC 扫描）
  → LatencyKeyThresholds（门限、滞回、两次确认）
  → KeyboardVoiceBridge（物理键 OR 远程 Gate；固定键位对应声部）
  → StudioVoiceStore（参数及独立声部状态）

Tauri / React UI → Rust → UART 115200 / CRC16
  → StudioControl（配置、远程键、波表）
  → KeyboardVoiceBridge / 配置存储

ParallelSynthEngine + SynthTaskPrefetch
  → 按固定阶段发射各声部任务
  → 共享相位、波形、包络、调制计算池
  → ParallelVoiceChain：SVF → VCA
  → KeyboardFrameMixer → KeyboardLoudness
  → PcmRounder / LatencyI2sTx（PT8211 时序）→ 底板 3.5 mm 输出

LatencySupervisor → LatencySynthTelemetry → UART → App
  （只读观察；监测拥塞不能反压音频）
```

当前逻辑阶段为：调制包络 → 调制振荡器相位 → 调制波形 → 载波相位 → 载波波形 → 振幅包络 → Mix/AM/Ring → SVF/VCA。阶段编号依次为 `7 → 0 → 1 → 2 → 3 → 4 → 5 → 6`；同一阶段的声部任务完成后才切到下一阶段。这是固定调度顺序，尚无逐声部可下载程序。

### 2.2 逻辑数量与物理数量

| 项目 | 当前数量 / 含义 |
| --- | --- |
| 逻辑声部 | 32，键位与声部固定对应 |
| 每声部音源 | 2 个逻辑振荡器 |
| 每声部包络 | 振幅 ADSR + 调制 ADSR |
| 每声部滤波状态 | 1 份 SVF 状态 |
| 相位/FM 物理核心 | 1 |
| 波形物理核心 | 2 |
| ADSR 物理核心 | 3 |
| Mix/AM/Ring 物理核心 | 1 |
| SVF / VCA 物理核心 | 各 1，当前直接连接为尾部链路 |
| 配置 / 状态行 | 每声部 512 bit / 384 bit |
| 输出 | 单声道混音复制到左右；还没有独立立体声效果总线 |

当前任务口采用 AXIS 风格的 `TDATA/TUSER/TVALID/TREADY`，载荷按核心定义；不是完整 AXI4 存储映射互联。以相位任务为例：输入 128 bit，由旧相位、频率增量、调制值、深度各 32 bit 组成；21 bit 标签为帧代号 16 bit + 声部编号 5 bit；返回新相位和原标签。

当前音色是 **64 字节固定参数配置**，并非指令程序。现有 FM 将调制作用于相位增量，不能直接等同于未来 DX 风格的 PM 算子。包络到 FM/AM 深度目前也是固定连接，尚无通用调制矩阵。

### 2.3 已有性能边界

| 项目 | 当前记录 |
| --- | --- |
| 核心时钟 / 采样率 | 50 MHz / 48,828.125 Hz |
| 每采样预算 | 1024 拍 = 20.48 µs |
| 固定引擎计算 | 385 拍 = 7.7 µs |
| CLS | 25,325 / 29,952，85% |
| BSRAM | 94 / 118，80% |
| DSP | 74 / 118，63% |
| 布线后最差 setup 余量 | +0.054 ns |

已有单键、和弦发声及延迟记录见上板报告。**7.7 µs 是引擎计算时间，不是按键到 DAC 的端到端延迟**；实体键测量约 6.70 ms，主要包含扫描与确认。增加计算核心不能直接消除扫描等待。

当前资源和时序余量都需要关注。385 拍不能按算子个数简单放大后宣称 FM6 一定能运行；新运行时、存储访问、调制、效果器和监测均需纳入重新综合与布局布线。

## 3. 目标架构的基本决定

1. **音色是一段驻留程序。** 电脑编译完成后可分包上传，但起音前必须完整装载、校验和提交；音频计算不等待电脑或 SD 继续供应指令。
2. **程序、参数、状态分开。** 相同音色的声部共享程序，参数以版本或快照引用；相位、包络、反馈和中间结果按声部及逻辑节点隔离。
3. **按下琴键创建执行实例。** NoteOn 绑定音符、力度、程序和状态；采样节拍反复执行程序；NoteOff 进入释音，直到该实例可回收。
4. **任务有明确执行边界。** 包内携带操作类型、必要输入或缓存引用和事务标签；内部微任务可执行一个基础算子，外部 AXI 命令可调用一个复合算子或声部帧，避免每次乘加重新搬运整套参数。不把完整音色程序在所有模块之间反复转发。
5. **功能模块组成依赖图。** 允许分叉、混合和不同路径；各声部按依赖就绪情况交错执行，减少全局阶段等待。最终 PCM 仍必须满足统一的采样截止时间。
6. **六算子是逻辑配置。** 六份独立状态不要求六个物理计算核心。先完成单声部 FM6，再评估 12 复音目标；最终容量由准入预算和实际实现决定。
7. **保留统一时间基准。** 演奏事件、控制更新、程序版本切换和音频帧使用明确的时间戳/边界，监测不影响实时通路。
8. **外部主干采用 AXI4 内存映射。** 按用户五层架构图，FPGA 主控为 Master，RAM/Voice Engine/Modulation/FX/PCM FIFO 为 Slave。执行外设提供 CMD/Completion FIFO，内部可保留私有 AXI-Stream。AXI 写响应仅确认事务/入队，运算完成通过带 tag 的 Completion 单独回收。

## 4. 所需模块与职责

状态：**现有**＝当前顶层已接入；**改造**＝有可复用实现但接口或行为需变；**新增**＝当前实时系统尚未具备。

### 4.1 硬件抽象与控制交互层 UI & Control

| 模块 | 状态 | 需要完成的内容 |
| --- | --- | --- |
| KeyScan / KeyThreshold | 改造 | 复用 ADC 扫描、门限、滞回和确认；输出带来源、键号、时间戳的事件 |
| Velocity / Aftertouch | 新增 | 先确认传感器可测量的物理量，再实现标定、曲线和事件；现有按下位图不能直接提供真实力度 |
| Knob / Encoder Engine | 新增 | 模拟旋钮多采样、死区/滞回、校准；编码器另用正交译码和去抖 |
| Tauri Patch Editor | 改造 | 增加程序/算法图、六算子、包络、调制路由、键位映射和资源预算显示 |
| Hardware Display / Scope | 新增、可选 | TFT 驱动、菜单和算法图；首版示波/频谱优先放电脑，监测数据可抽取或丢帧 |
| Audio Hardware Output | 改造 | 复用 PT8211 串行输出、舍入；接入独立 L/R 数据并保持采样节拍 |
| Latency / Fault Monitor | 改造 | 复用延迟监督器，追加任务超期、状态冲突、队列高水位、装载错误；限制监测资源开销 |

### 4.2 通信与编排层 MIDI & Control

| 模块 | 状态 | 需要完成的内容 |
| --- | --- | --- |
| UART / Control Transport | 改造 | 保留 CRC16、ACK；增加协议版本、能力查询、分包重试和程序事务 |
| MIDI Parser / Adapter | 改造 | 正确处理不同消息长度、Clock、SysEx 和多设备来源；当前主机回调只保留三字节，不具备完整解析能力 |
| ControlEvent Queue | 新增 | 统一硬件/主机输入，按目标采样帧派发 Note、CC、Bend、Sustain 等事件 |
| KeyMap / PatchMap | 改造 | 将实体键、MIDI 音符映射到音色程序；与物理声部编号解耦 |
| DX7 SysEx Import / Export | 新增，Rust 优先 | 单音色/32 音色库的长度、校验和字段验证；映射到内部算子/包络/算法；保留原始字段用于往返导出 |
| Arpeggiator / Sequencer | 新增 | 基于本地时间基准生成事件，逐步加入 Swing、Ratchets、Parameter Locks |
| USB-MIDI / BLE-MIDI | 新增、按外设选型 | 初期沿用电脑 MIDI 适配；板端独立实现需要对应控制器/模块及协议栈 |

### 4.3 核心 DSP 合成引擎 Voice Engine

实现入口：[完整基础 Voice Engine](demo1/voice-engine/ENGINE.md)、[模块清单](demo1/voice-engine/README.md) 与 [AXI 接口](demo1/voice-engine/AXI-interface.md)。加入LFO后当前候选子系统共13个RTL定义，已形成 AXI装载驻留程序 → 动态声部 → 六算子调度 → 立体声PCM 的功能闭环。8声部×6逻辑算子复用一个物理复合算子，整帧仿真658拍/1024拍预算。支持两种不同音色并行、逐算子线性EG、PM/FM/AM/Ring、六种波形及双帧波表、延音/释音/抢音、反馈历史和重复请求保护。

Gowin 单独综合新 VoiceSynthEngine：Logic约39%、寄存器约28%、BSRAM20、MULT27X36原语29、Latch0；不是整板资源。严格门禁仍未通过，尚未接入当前上板顶层，也没有本轮PnR，不能声称完整Surge或DX7兼容。逐项证据与限制见上述ENGINE.md。

| 模块 | 状态 | 后续内容 |
| --- | --- | --- |
| VoiceAllocator / Lifecycle | 候选已实现 | 8声部、NoteID幂等、延音、载波结束检测、最老抢占；继续抢音淡化与更丰富策略 |
| Phase / Wave / Wavetable | 候选已实现 | 六种波形、32位相位、邻点及双帧插值；继续抗混叠和多波表资源缓存 |
| PM/FM Operator | 候选已实现 | 比率/固定频率、PM/FM/AM/Ring、增益及独立状态；继续精度/时序优化 |
| ADSR / MultiEG | 候选已实现线性四段 | 独立EG和一次采样一次推进；继续音乐单位/曲线映射 |
| DX 4-Rate/4-Level EG | 待扩展 | 准确速率/电平曲线、键盘/力度缩放，另加Pitch EG |
| Algorithm / Feedback Routing | 候选已实现六行无环图和历史反馈 | 继续DX7 32算法映射、更多反馈拓扑及SysEx导入 |
| Mix / AM / Ring / VCA | 候选已实现 | 载波平均、声部Gain/Pan、固定复音余量；继续听感响度校准 |
| Voice End Detection | 候选已实现 | 基于载波EG结束回收，迟到NoteOff不会杀死替代声部 |

选择分立 `EG + PM_OP` 或复合 `FMOP` 时，必须定义包络由谁推进。同一采样内同一份包络/相位状态只推进一次；共享源多次被读取不应多次推进状态。

### 4.4 调制矩阵 Modulation Matrix

首版LFO与路由已形成候选实现，入口见 [MODULATION.md](demo1/voice-engine/MODULATION.md)。每音色2个LFO、8条稀疏路由；全局8份、逐声部16份逻辑状态由一个AxisLfoStep物理流水处理。支持7种波形、单/双极、NoteID起音重触发与显式B3重触发，路由到音高、音量、声像、6个算子增益和6个算子调制深度。AXI-MM仍共用AxiVoiceEndpoint入口，尚未拆成独立Slave地址窗口。

| 模块 | 状态 | 后续内容 |
| --- | --- | --- |
| LFO Source Pool | 候选已实现 | 全局自由运行/逐声部模式、状态隔离、随机与插值；继续Delay/Fade和更多源 |
| Sparse Route / Mod MAC | 候选已实现 | 8路、15个目标、36位累加保护位、源值一帧算一次；继续宏/轮/触后等输入 |
| Control-rate Interpolator | 暂未需要，LFO按音频率计算 | 若改32/64采样更新，需增加目标插值和状态连续性检查 |
| Live Parameter Commit | 候选已实现 | 与音色参数共同双银行切换；保留相位，可显式重触发；继续全目标去点击 |
| Musical Mapping / Tempo | 部分实现 | 编译器支持Hz/BPM换算；实时MIDI Clock锁相和准确半音调制待做 |

8声部×6算子与LFO/路由同时工作的测试最高858拍/1024拍预算；1600帧PCM与38400份源状态对照通过。新内核单独Gowin综合约50% Logic、35%寄存器、24 BSRAM、36 MULT27X36，尚无板级PnR结论。当前总RTL定义13个，严格门禁未通过，详见最新验证清单。

LFO不串在音频样本通路中：它产生参数偏移，先与基础值合成，再交给声部DSP计算；同一源被多路引用不会重复推进相位。

### 4.5 后级处理与效果链 FX Suite

| 模块 | 状态 | 需要完成的内容 |
| --- | --- | --- |
| SVF / Filter Adapter | 改造 | 复用当前逐声部 SVF；按需求新增 Biquad/级联类型，不能将现有 SVF 标为已实现双 Biquad |
| Stereo Bus / Pan / Mixer | 改造 | 独立 L/R、声像、总线分配、累加余量与饱和处理 |
| Loudness / Limiter | 改造 | 保留复音响度控制；加入平滑、跨音色电平校准和峰值统计 |
| Delay / DelayMemory | 新增 | 环形 RAM、受限反馈、时间变化平滑；按需求加入分数延迟插值 |
| Chorus / Flanger | 新增 | LFO 驱动延迟线、插值与反馈；优先共享立体声总线部署 |
| Reverb | 新增 | 根据 RAM、带宽与计算预算选择结构，验证衰减、稳定性、尾音与音质 |
| Saturation / Shaper | 新增 | 非线性运算、余量和混叠控制；需要过采样时独立核算资源 |

共享效果器拥有独立生命周期。回收一个声部不能清空全局 Delay/Reverb 尾音。首版先实现共享 Chorus/Delay，再考虑 Reverb。

### 4.6 公共程序运行与存储设施

这部分支撑五个功能板块，不是第六段音频处理链，也是本次架构重构的首要工作。

| 提议模块 | 状态 | 职责 |
| --- | --- | --- |
| PatchCompiler（Rust） | Python离线六行编译器已实现，Rust接入待做 | 图检查、单位/类型检查、调度约束、指令及参数生成、状态布局、资源预算 |
| ProgramLoader / Validator | 新增 | 分包暂存、完整性校验、边界/操作码检查、提交；拒绝超限程序 |
| ProgramStore / ParamVersionStore | 新增 | 驻留指令和参数版本；被活动声部引用的旧版本不能覆盖 |
| VoiceContextStore | 改造 | 从固定状态行转为程序句柄、PC、实例代号、节点状态索引及生命周期 |
| ProgramSequencer / Prefetch | 改造 | 从固定阶段号改为取指、依赖就绪、每实例进度与下一指令预取 |
| TaskDispatcher / CorePool | 改造 | 复用共享核心封装；按核心可用、状态占用、队列与返回容量派发 |
| ResultScratch / Scoreboard | 新增 | 中间结果、分叉/汇合、源就绪和状态忙标记；防止读旧帧数据 |
| Completion / StateCommit | 新增 | 检查事务身份、结果归属，写回状态与结果，释放依赖；过期返回不能写新声部 |
| Frame / Deadline Controller | 改造 | 每采样启动、最终结果收齐、截止期/欠载检测和受控故障输出 |
| AssetStore / SD Loader | 改造或新增适配 | SD/exFAT 保存程序、参数、波表；起音前装入 RAM/缓存。本顶层没有指令程序从 SD 驻留加载的通路 |

建议首先保留现有计算核心，通过适配层接入运行时；不要同时重写调度器、全部 DSP 数学实现和板级外设。

## 5. 数据、参数与任务如何传递

### 5.1 四条通路

| 通路 | 内容 | 时机 |
| --- | --- | --- |
| 装载通路 | Program、ParamImage、KeyMap、素材 | 编辑/切换音色时；分包传输，完整提交后才可引用 |
| 事件通路 | NoteOn/Off、CC、Bend、Sustain、实时参数 | 事件到达后按时间戳调度；与指令加载分开排队 |
| 执行通路 | 操作/短描述符、输入快照或缓存引用、状态索引、tag | 主控经 AXI4 MM 提交到外设 CMD FIFO；外设内部用 ready/valid 流控 |
| 回写/输出通路 | 新状态、中间结果、完成标签、最终 PCM | 核心返回后提交；完成音频帧送输出 |

分包装载提案：`BEGIN → WRITE → VALIDATE → COMMIT`。这些名字尚不是现有固件命令。验证包括长度、校验、地址范围、操作类型、状态规模、依赖合法性和资源限额。COMMIT 只发布可引用版本，失败时当前版本继续可用。

音色程序作为整体驻留，但执行时可只预取一条或少量指令；两者并不冲突。程序 RAM 至核心之间不需要每次传完整程序。

### 5.2 需要冻结的数据结构

| 数据结构 | 最低语义 |
| --- | --- |
| PatchProgram | 格式版本、程序身份、入口、指令数、状态/结果槽需求、功能需求和预算 |
| ParamImage | 类型化参数、单位/范围、版本；与程序兼容性 |
| KeyMap | 输入来源、键/音符范围、音色句柄、移调和演奏策略 |
| VoiceContext | 音符实例代号、程序/参数句柄、音高、力度、Gate、PC、状态基址 |
| Task | opcode、节点/输入/输出定位、输入及参数快照、状态定位、事务标签 |
| Completion | 原事务标签、状态/结果、完成或异常标记 |

事务标签可通过片上事务表关联 `program / voice_id / owner_epoch / frame_id / node_id / param_revision`，不要求把所有字段直接塞入现有 21 bit TUSER。需要定义标签回绕、重用和过期返回规则。

### 5.3 握手与状态规则

- `valid && ready` 才算接收；被反压时 `valid`、数据和标签保持稳定。
- 发射前确认输入就绪、状态未被同一实例的其他任务占用，并预留返回/写回容量。
- 任务只读取该次快照；参数在执行中途被 UI 修改不能改变已发出的运算。
- 状态回写成功后才解除依赖。共享计算核心可以复用，递归状态不能跨实例串用。
- 前馈图不能有零延迟循环。反馈必须显式使用历史样本/状态，并定义具体算法所需的历史长度与缩放。
- 监测可丢弃低优先级显示帧，音频任务不能无声地丢失。发生超期时记录故障并进入约定的保持/渐静策略，不能无限期阻塞 DAC。
- 外部统一使用 AXI4 内存映射接口；轻量 ready/valid 任务流用于执行器内部。RAM 与多个执行外设之间的主动搬运由 Master 承担，只有 Slave 端口的算子不能自行读共享 RAM。

### 5.4 已实现的 Voice Engine 外设与带宽边界

`AxiVoiceEndpoint` 提供 32 bit 数据、16 bit 字节偏移、4 bit AXI ID；支持对齐 32 bit INCR/FIXED 突发，读写各一条在途。命令和完成队列各深 4。十个暂存参数字加 opcode/tag 在 COMMIT 时原子复制，结果在 AR 时冻结并由独立 POP 释放。内部五种操作通过 320 bit 私有任务口接入，共享返回仲裁保留完整 32 bit tag；不同操作可乱序完成。

该版本是可观测的内联参数调用入口。12 声部×6 逻辑算子×每算子三条基础任务，以每任务 13 个写数据拍计，单 W 通道就需 2808 拍/采样，超过当前 1024 拍预算，尚未包含波形/滤波/FX。因此下一步必须做参数/状态缓存、较粗粒度复合执行命令和短描述符，之后再按综合结果决定总线宽度与并行度。增加队列深度只能缓冲突发，不能解决平均带宽不足。

全局主控 Master、程序取指/依赖表、共享 RAM 地址互联、调制/FX/PCM 的 AXI 封装仍待实现。包络已具备四段线性事件控制；完整 DX 曲线、Sine/波表适配、PM/FM 复合算子和反馈历史也尚未闭环。候选模块没有计入当前板上资源数字。

### 5.5 持续发音与重复包

实体键扫描保持按下状态时只产生一次 NoteOn；App 已过滤电脑键盘自动重复，板级实际桥接模块也已通过按住/松开/重按/和弦回归。持续音由本地采样任务推进，后续样本即使输入参数相同也必须继续更新相位、包络等递归状态。

新 `AxisVoiceRuntime` 将通信重发身份定义为 context_id + generation + execution sequence，并精确比较实时输入。最近同一请求返回缓存结果，冲突、旧代号、旧序号和跳号请求拒绝，不再次推进状态。重复 BIND 也不会重置已经运行的实例。原 raw 操作保持原语义，只有显式缓存命令使用此保证；重放历史在复位时失效。完整语义、寄存器、资源逻辑量和后续并行化见 [CONTEXT-and-retries.md](demo1/voice-engine/CONTEXT-and-retries.md)。

参数缓存当前独立存于各逻辑算子，状态所有者已明确；后续仍需共享 ParamStore、FM 音频反馈历史、VoiceAllocator、采样 Tick 和程序依赖表。BIND 用于实例初始化，持续音的旋钮变化需另做保持状态的参数版本提交，不能靠反复重绑实现。

## 6. 音色程序与逐采样流程

以下为语义示意，尚无最终二进制指令编码：

```text
DX_EG   e0, state.eg0, params.eg0
PM_OP   a0, state.op0, e0, mod_input
FILTER  a1, a0, cutoff, resonance
VCA     a2, a1, amp
OUT     bus0, a2, pan
```

六算子音色展开为多条算子与包络指令，载波按算法求和；复杂音色可增加分支、混合、滤波和调制节点。不同路径通过中间结果槽连接，按需要重复调用同类核心。

每个采样帧：

1. 接收该帧应生效的演奏事件与控制更新，处理起音、释音及版本引用。
2. 更新本帧需要的共享调制源，为每个活动实例建立本帧执行进度。
3. 预取指令，检查数据依赖和状态所有权，将可执行任务送入对应核心池。
4. 核心返回后核对 tag，回写状态/结果并唤醒后继；不同声部可交错并行。
5. 各声部 OUT 写入目标混音总线；总线齐备后执行共享 FX 程序。
6. 完成 L/R 响度与限幅，按固定节拍提交 PCM；更新监测和释放已结束实例。

保持帧边界不意味着所有节点都需要全局同步屏障。帧内由依赖驱动，只有明确的混音汇合、共享效果入口和输出截止点需要等待其必要输入。

## 7. 存储、精度与容量

- **程序/基础参数**：按音色版本共享；活动引用计数与释放规则必须明确。
- **算子/声部状态**：相位、EG、反馈、滤波延迟状态独立；优先评估分组 RAM 与端口调度，避免直接扩成大规模寄存器阵列。
- **中间结果**：按存活区间复用槽位；带就绪/帧身份，避免分支汇合误用旧结果。
- **波表/长延迟线**：有明确带宽预算的 RAM/缓存。SD 用于持久存储，不能承担逐采样随机访问的实时保证。
- **数值格式**：复用当前 32 bit 相位和现有音频定点实现作为对照基线；各操作明确输入范围、乘法中间位宽、舍入、饱和与混音保护位。不能仅凭“32 位”就判定音质足够。
- **FM 音质**：验证调制指数、反馈增益、频率比、失谐、包络映射、噪声和混叠；SysEx 字段可读不等于声音已经等价。
- **预算**：统计核心吞吐/延迟、RAM 冲突、取指、参数转换、插值、返回和共享 FX。以允许的最坏音色组合准入；不能只用平均负载。
- **目标容量**：先单声部 FM6，之后评估 12 复音。72 个逻辑算子只是状态数量目标，不是已经证明的资源或吞吐能力。

## 8. 实施顺序与验收

| 阶段 | 交付内容 | 验收条件 |
| --- | --- | --- |
| P0-A 程序定义 | PatchProgram/ParamImage/Task ABI、Rust 编译与参考执行器 | 用指令重现现有双振荡器链路；非法拓扑、越界状态、超预算可被拒绝 |
| P0-B 最小运行时 | 驻留装载、取指、状态池、分发与回写 | 单声部固定点等价；再验证异构多声部、背压、标签、重复起音和旧返回隔离 |
| P0-C 动态演奏 | Event Queue、KeyMap、VoiceAllocator、实时参数 | 延音/释音/抢音正确；旧音色尾巴不受新版本覆盖，持续音更新平滑 |
| P1-A FM6 | PM 算子、DX EG、Pitch EG、反馈、算法图 | 单声部与参考模型数值/频谱/听音对照；覆盖极端参数，再测可接受复音数 |
| P1-B 音色库与调制 | SysEx、LFO、稀疏路由、单位映射与插值 | 导入结果可解释；共享源不重复推进，控制率和音频率路线正确 |
| P2 立体声 FX | 双声道总线、Chorus/Delay，再加 Reverb | 无过载爆音、反馈稳定、尾音连续；多音色和弦电平与实时预算通过 |
| P3 外设与编排 | 实体旋钮、TFT、独立 MIDI、Arp/Seq | 在不破坏音频截止期的前提下逐项集成 |

每个硬件阶段均需完成相应 RTL 仿真、综合、布局布线和上板回归。程序并发、声部数、核心实例数变化后必须重新确认 1024 拍预算、资源占用和时序；旧固定链路的验证结果不能直接转移给新运行时。

建议第一个实现里程碑是：**一段已驻留的程序，调用现有计算核心，复现一声部双振荡器音色，并从实体按键到 DAC 跑通。** 以此验证程序机制，再扩展 FM6 和效果器，降低同时改变调度与 DSP 算法造成的定位难度。

