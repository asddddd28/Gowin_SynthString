# 保持显示、采样效果的资源优化

基线：`reports/synthui-hdmi/build-touch-final`（2026-11-03）。
本轮保持系统 50 MHz、HDMI 1280×720 / 73.333333 MHz 像素时钟，以及现有音频、键盘和双触摸板采样配置。

## 有没有例化却没用上的模块

以实际构建 `SynthHdmiTop` 为准，不能仅凭 `sources.f` 中出现文件名判断硬件资源：

| 模块 / 功能 | 当前硬件状态 | 是否可以直接删除来省资源 |
|---|---|---|
| `AxisFxEngine` / `AxisStereoDelay` / `AxisSchroederReverb` | `SynthSystemTop.C_FX_ENABLE=0`，generate 分支未展开，综合层次中没有 FX | 已经不占资源；删除源文件不会再省 |
| `AxisVoiceRuntime` / `AxisVoiceFabric` 旧调度域 | `AxiSynthEndpoint` 固定 `LEGACY_ENABLE=0`，旧算子池未生成 | 已经不占资源；保留 unsupported 回复逻辑以避免错误命令悬挂 |
| 独立 `AxisPhasePm` / `AxisGainMix` / `AxisNoiseStep` | 只由旧算子池例化，当前层次中没有 | 不占资源；当前合成引擎有自身实现 |
| 旧 `LatencyKeyThresholds` | 源码列在工程中，当前顶层使用 `SynthKeyboardControl` + `KeyboardCrossingTime` | 不占资源；不是又留了一套采样器 |
| `SynthBootSequencer` | 上电装载成功后停在 DONE；基线占 2 个综合 RAM 单元及 381 个寄存器 | 是“阶段性闲置”，但保证离线开机初始化；后续可设计与运行期存储复用，不能直接删 |
| `VoiceModulation` + `AxisLfoStep` | 硬件和 B0/B1 配置接口存在，但当前合并版 App 没有通用 LFO 状态 / 配置适配；普通使用流程基本闲置 | 值得增加编译开关。不能与已经可用的低通内置 Cutoff LFO 混为一谈 |
| `AxisEnvelopeMulti` / `AxisEnvelopeSegment` 和 `AxisDxEnvelope` | 在当前 `AxisFmOperator` 内，分别用于通用包络和 DX 音色包络 | 当前音色可以只选其一，硬件仍须支持两种 |
| `AxisMasterLowpass` | 在真实 PCM 通路内，可配置旁路，并接受触摸 Cutoff | 旁路时仍占资源，删除会丢失低通 / LFO Cutoff / 触摸滤波功能 |
| 两个 `MprScanner` / `TouchPosition` | 分别服务两块触摸板，独立总线、采样和故障隔离 | 不是重复闲置的模块；可以重构共享，但不能直接删一个 |
| `SynthDisplayAudio` 和 `SynthStudioMonitor` | 前者为 HDMI 波形/频谱，后者为 App PCM / 遥测 | 都有消费者；合并需重新设计双时钟读端口和缓冲 |
| `SynthDisplayControl.o_focus/o_confirm` 顶层悬空 | 直连端口没用，但同一内部状态会从串口响应返回 App | 不能据悬空端口推断整个状态逻辑无用 |

当前综合层次没有发现大型模块完全无消费者却被强行保留的证据，但存在“RTL 接入完整、App 没有使用”的大型调制域。这比“未连接的死模块”更容易漏查。本轮先压缩小 ROM 和页面容量，不自动改变 B0..B3 指令能力。

### 通用调制域的实际使用情况

- `demo_test/desktop-tauri/src-tauri/src/voice_hdmi.rs` 明确显示 `CURRENT PATCH API: NO LFO STATE`、`CONFIGURATION ADAPTER PENDING`。
- `voice_native.rs::compile_native` 只生成 A0/A1/A2/A3；六算子之间的 PM/FM/AM/Ring 路由不等同于 B0/B1 的慢速调制矩阵。
- 当前 `boot_dry.hex` 包含 57 条命令：A0×4、A1×24、A2×24、A3×4、A7×1，没有 B0/B1。内嵌 FM 命令库同样没有 B0/B1。
- `VoiceModulation` 加其 `AxisLfoStep` 子模块的基线综合资源为 **4912 个寄存器、4556 个 LUT、312 个 ALU、6 个 BSRAM 单元、37 个 SSRAM 单元、5 个 MULT27X36**。这是包含子模块的合计，不能再加一次 LFO 子模块数据。
- 诊断工具和历史 LFO 仿真可以通过 B0/B1 启用该域，因此不能称为永远不可达的死逻辑。
- `AxisMasterLowpass` 内部的 Cutoff LFO 已由 `voice_filter.rs` 和 `MasterFilter.tsx` 配置，属于当前实际功能，应当保留。

后续可增加通用调制域编译开关，关闭时同时收紧能力寄存器并明确拒绝 B0..B3，再验证无通用调制的音色逐样本等价；或者补齐 App 配置以充分利用已存在的资源。本轮未关闭该域。

资源口径：基线综合阶段是 **85 个 BSRAM 单元**，最终布局布线经过 SDP 拆分后是 **113/118 块物理 BSRAM**。模块级综合块数不能直接加总成最终 113 块。

## 本轮实现

1. 页面 ROM 有 84 个实际行，每行仍占 128 个 18 位单元。原数组分配 16384 个单元。仅改为 11264 个单元，Gowin 仍映射为 16 块；因此最终明确分成 8192、2048、1024 三个数组，共 11 块。
2. 三个数组同时寄存读取，选区标志在同一拍寄存。输出选择替代原 ROM 的银行选择；后面的文本、字形、颜色流水级不变。没有增加可见延迟，也没有降低分辨率、字符数、颜色或刷新率。
3. 两个触摸扫描器的小配置表使用 `syn_romstyle="distributed_rom"`。46 项初始化及默认值、采样寄存器、I2C 时钟和超时完全不变。

不改 DFT 的 256 点输入、64 个频谱柱、波形触发与自动增益、64×64 历史图、音频数据位宽、滤波系数、音色 ROM、键盘校准或触摸位置计算。

## 证据与限制

- 修改前源码、全部显示素材与七幅 RTL 渲染图冻结于 `reports/resource-preserving/baseline`。
- `hdmi/model/check_storage_compaction.py` 枚举 65536 个页/行/列地址，验证三存储区映射与基线逐字一致；被移除区域不可达且全为零。
- 同一脚本证明 MPR 去除注释和综合属性之后的可执行 token 完全相同。
- `hdmi/model/validate_storage_compaction.py` 在独立目录执行真实 RTL 显示回归；`--mpr` 执行 SCL/SDA 行为从机，包括正常配置采样、NACK 隔离、卡钟超时、重新配置。
- 七幅完整 RGB 图的逐字节比较覆盖 6,451,200 个像素，包括校准中文提示。
- 既有紧凑 RTL 不满足 readable-verilog 的严格格式门禁，formatter-AST 在基线和修改版都报告解析 / 风格问题。本轮没有把大规模代码格式重构混入资源优化；格式门禁失败不能写成通过。实际编译仿真、Gowin 综合和布局布线结果另行记录。
- 资源收益和时序以最终候选的布局布线报告为准；仅源码数组缩小不构成节省资源的证据。

## 最终结果

候选：`reports/synthui-hdmi/build-storage-banked`，2026-11-03 09:33 完成。

| 最终布局布线指标 | 基线 | 优化后 |
|---|---:|---:|
| 物理 BSRAM | 113 / 118 | **105 / 118** |
| 空闲 BSRAM | 5 | **13** |
| CLS | 26523 / 29952 | **26294 / 29952** |
| Logic | 33475 | 33519 |
| Register | 28143 | 28152 |
| DSP | 68.5 / 118 | 68.5 / 118 |
| 系统时钟约束 | 50 MHz | 50 MHz |
| 系统报告 Fmax | 50.177 MHz | **50.181 MHz** |
| 像素报告 Fmax | 75.995 MHz | **84.584 MHz** |
| Setup / Hold 违例 | 0 / 0 | **0 / 0** |

显式拆分页面存储后，HDMI 综合 RAM 实际减少 6 块，触摸初始化表减少 2 块，最终物理总量也减少 8 块。Logic 增加 44，寄存器增加 9；没有用画质或音频精度交换资源。

系统最差 setup 为 **+0.072 ns**，hold 为 **+0.043 ns**。时序通过，但系统余量仍很薄；当前最慢 setup 路径从 `Thresholds_Inst/cnt_divider` 到 Voice Engine 的声部状态写使能，应单独处理，不能把这次 RAM 优化等同于已解决全部时序压力。

最终四组仿真均通过，七幅图 6,451,200 个像素逐字节一致。源文件清单核对确认只改两个 RTL 模块以及页面素材，音频计算、键盘采样、触摸位置算法和频谱分析源码均未改。详见 `reports/resource-preserving/{simulation-summary,pixel-equivalence,source-diff,timing-final}.json`。

固件已生成于 `reports/synthui-hdmi/build-storage-banked/impl/pnr/synth_hdmi.fs`。**本轮未烧录、未做新固件上板验收**；板上仍为先前触摸版，App 与用户设置没有更改。
