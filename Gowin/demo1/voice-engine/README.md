# Voice Engine 可调度算子库

更新：2026-11-02。整体架构见 [structure.md](../../structure.md)。

## 1. 最新状态：基础 Voice Engine 已形成持续发声闭环

最新新增 **[完整整机 hierarchy](../voice-system/SYSTEM.md)**：键盘、UART、启动ROM、AXI Master、Voice/LFO/FX、PT8211已连通并完成仿真。参数表和算子状态使用同步RAM后，满载完整路径为971/1024拍。板级Delay为16K/声道，库默认仍为32K。最新整机证据见 [验证报告](../voice-system/VERIFICATION.md)。原 [fx-verification.json](reports/fx-verification.json) 中931拍及综合资源为优化前历史基线。

已有 **[LFO / Modulation](MODULATION.md)**：每音色2个LFO、8条路由、全局/逐声部模式、7种波形及音高/音量/声像/算子参数调制。下文658拍及原资源数字为历史基线，不是含LFO/FX的整套资源与时限。

本目录现在有 **17 个 RTL 模块定义**，精简顶层使用12种。8 个动态声部，每声部 6 个逻辑算子，支持 PM/FM/AM/Ring、六种波形、独立四段线性 EG、无环路由、历史反馈、延音与释音、LFO调制及共享立体声FX。

完整说明、当前 hierarchy、指令格式、去重策略、资源和限制见 **[ENGINE.md](ENGINE.md)**。离线音色编译器与五组基础音色位于 [model/compile_voice_patch.py](model/compile_voice_patch.py) 和 [examples](examples)。

8×6 算子的端到端仿真测得整帧 658 拍，采样预算 1024 拍。Gowin 已完成新 Voice Engine 单独综合；尚未接入 `LatencyAxisTop`、进行本轮板级 PnR 或烧写。严格交付门禁仍失败，不能称为最终板级版本或完整 DX7/Surge 兼容。

旧四核、多段 EG、任务 Fabric 和32项上下文 Runtime 由 `LEGACY_ENABLE=1` 保留，接口见 [AXI-interface.md](AXI-interface.md) 与 [CONTEXT-and-retries.md](CONTEXT-and-retries.md)。下文测试数字描述对应历史阶段，当前完整结构和证据以 [FX.md](FX.md) 为准。

## 2. Voice Engine 应有哪些生成与处理算子

| 类别 | 算子 / 模块 | 作用 | 当前情况 |
| --- | --- | --- | --- |
| 基础相位 | PHASE / FM_PHASE | 频率增量积分、回绕、线性 FM | 新 AxisFmOperator 内置 PM/FM 两种积分语义；旧 AxisPhaseFm 保留于板级旧路径 |
| 相位调制 | PM_PHASE | 保持积分状态独立，对查表地址施加相位偏移 | **新增 [AxisPhasePm](rtl/AxisPhasePm.v)** |
| 周期波形 | SINE / TRI / SAW / PULSE | 相位到音频幅值 | 新 AxisFmOperator 已内置正弦/三角/锯齿/脉冲；抗混叠仍待扩展 |
| 波表 | WAVETABLE / MORPH | 邻点插值、帧间插值、资源读取 | 新核心支持两帧1024点邻点/帧间插值；多资源句柄/版本/缓存调度待扩展 |
| 噪声 | NOISE | Drum、打击、气息等非周期激励 | **新增 [AxisNoiseStep](rtl/AxisNoiseStep.v)**；每个逻辑实例保存独立种子 |
| 包络基础 | SEGMENT | 电平向目标步进、到达判断、零速报告 | **新增 [AxisEnvelopeSegment](rtl/AxisEnvelopeSegment.v)**；支持有符号目标，可用于幅度或音高 |
| ADSR | ADSR | 起音、衰减、保持、释音 | 旧板级路径保留 AxisAdsr/EnvelopePrecision；新引擎用独立四段线性EG表达 |
| 多段包络 | MULTI_EG / DX_EG / PITCH_EG | 阶段切换、Gate/重触发、速率/电平语义 | **新增 AxisEnvelopeMulti**：四目标线性包络、NoteOn/Off/Kill、保持与重触发；DX 曲线和音乐单位映射仍待实现 |
| 音频乘加 | GAIN / MAC / MIX | 音量、声源求和、载波求和、交叉混合 | **新增 [AxisGainMix](rtl/AxisGainMix.v)**；同时保留当前 `StudioOscMixer` 作为旧行为对照 |
| 音频调制 | AM / RING | 单极/双极振幅调制 | 新 AxisFmOperator 已包含 AM/Ring，深度与输入范围明确 |
| 反馈历史 | HISTORY_READ / COMMIT | 一拍/两拍历史、算法反馈、递归状态所有权 | 已在新引擎保存每算子的两拍历史，复合算子完成平均与缩放 |
| 算子组合 | FM_OPERATOR | 包络、相位调制、正弦/波形、增益及状态回写 | 已实现 AxisFmOperator；一次任务推进一次相位/包络并返回状态 |
| 可选音源扩展 | SYNC / PWM / SUB / UNISON / SHAPER | 更丰富的 Bass/Pad/Lead 音色 | 后续按音色需求增加；先明确抗混叠、复音与实例数量预算 |

### 不放进基础算子池的职责

- VoiceAllocator、KeyMap、Gate/延音、抢音、声部结束判断：属于声部控制与生命周期。
- 程序取指、依赖、事务表、状态 RAM 和回写：属于运行时。
- LFO/宏/CC 的多对多连接：属于调制矩阵，使用算子但不是一个振荡器的固定附属部分。
- SVF/Biquad、立体声混音、Chorus/Delay/Reverb：按整体分类属于滤波/效果域；可以在音色程序中被调用。

六算子 FM 的“六个算子”是六份逻辑音源/包络/历史状态，不等于六种硬件模块，也不要求六份完整物理核心。

## 3. 第一批 RTL 的接口与数值

四个模块统一采用单拍任务：

- 输入：128 bit `TDATA`、32 bit 透明 `TUSER`、`TVALID/TREADY`。
- 输出：64 bit `TDATA`、原 `TUSER`、`TVALID/TREADY`。
- 单时钟；低有效异步复位，释放由外部同步。
- 输出阻塞时，该算子内部整体暂停，结果与标签保持稳定。
- 无阻塞时 II=1；不同声部的任务可以逐拍交错。
- 每个核心仅保存流水快照，持久状态由调用者保存并在依赖完成后回写。
- 不使用 TLAST/TKEEP；不是完整 AXI4 存储映射总线。

这是本算子库的接口，不是已经完成的全系统任务 ABI。现有顶层采用 21 bit 标签和不同宽度载荷；集成时需要显式适配和事务表，不允许直接截掉新标签高位。

### 3.1 PM 相位

输入四个低字到高字：

`phase / increment / modulation_Q26 / depth_phase_word`

输出低字为 `next_phase`，高字为 `lookup_phase`：

```text
next_phase   = (phase + increment) mod 2^32
offset       = floor(modulation * depth / 2^26)
lookup_phase = (next_phase + offset) mod 2^32
```

下一采样回写 `next_phase`，波形读取使用 `lookup_phase`。本核心不负责正弦查表、包络或反馈历史存储。深度是有符号相位字，不能把半音或 Hz 直接当作这个字段发送。

### 3.2 包络目标步进

输入：`current_signed32 / target_signed32 / step_unsigned32 / reserved`。

向目标移动最多一个 step，跨越时精确停在目标。输出低 32 bit 是新电平，bit32 表示已到达，bit33 表示“尚未到达且步长为零”，其余为零。

目标和当前值可以使用相同的幅度或音高数值单位。包络曲线、阶段表、DX 速率换算不在该基础核中；后续控制层负责生成目标/步长。默认线性逼近不能直接宣称 DX7 声音兼容。

### 3.3 双路乘加

输入：`a / gain_a / b / gain_b`，均为 signed32、26 个小数位。

```text
wide = a * gain_a + b * gain_b       // 64-bit products, 65-bit accumulation
out  = sat32(floor(wide / 2^26))
```

输出 bit32 是削波标志，低字是饱和结果。单位增益为 `0x04000000`。先完整求和再去小数，保留抵消精度；接近正饱和边界时，要按量化后的值判断是否真的削波。

组合示例：

- VCA：`a=audio, gain_a=envelope, b=0`。
- 求和：两个 gain 取单位增益。
- Ring：把调制音频作为 gain_a，b 取零。
- AM：先计算 `(1-depth) + depth*unipolar_mod`，再乘载波；必须明确调制源范围，避免与 Ring 混淆。
- 反馈平均：两个历史输入各乘 0.5；后续深度可由 PM 核施加。
- 载波超过两路时构建加法树，并明确累加余量；不要无意在每个中间节点削波。

### 3.4 噪声

输入低字为随机状态，其余保留。输出低字为新状态，高字为 signed32 Q26 音频。采用 xorshift 的 13/17/5 移位异或，零状态自动修复为一。

不同逻辑噪声源必须分配不同种子；所有声部使用同一种子会相关。此模块产生确定性伪随机白噪声激励，不是密码学随机源；粉红/有色噪声可通过后续滤波构造。

## 4. 如何组合生成声音

### 基础减法/波表音色

```text
PHASE/FM → WAVE/WAVETABLE → GAIN/MIX → 声部输出
                                  ↑
                          ADSR / MULTI_EG
```

滤波器在音色需要时连接到声部输出前。Drum 可用 NOISE 与周期激励混合，配合快速幅度/音高包络；Pad 和 Chord 复用多个独立音符实例与较长包络，不等于专门新增一个“Pad 电路”。

### 一个逻辑 FM 算子

```text
EG 状态 → EG 控制/步进 → level ───────────────────┐
频率字 + 积分状态 → PM_PHASE → lookup_phase → SINE → GAIN → operator_sample
                    ↑          └ next_phase 回写
          前馈调制值 + 历史反馈
```

每个样本中先计算依赖已就绪的调制算子，再计算其载波；并联分支分别执行，载波按算法求和。反馈只读约定的历史状态，禁止构成零延迟环。状态更新在任务完成后提交，不由波形核心私自推进六份声部状态。

## 5. 仿真证据与限制

[参考模型](model/voice_operator_model.py)、[测试平台](sim/tb_voice_operators.v)、[xsim 日志](reports/xsim.log)。

| 算子 | 最终轮逐位比较事务 | 最早消费延迟 | 无阻塞接纳间隔 |
| --- | ---: | ---: | ---: |
| AxisPhasePm | 2076 | 3 拍 | 1 拍 |
| AxisEnvelopeSegment | 2140 | 4 拍 | 1 拍 |
| AxisGainMix | 1569 | 4 拍 | 1 拍 |
| AxisNoiseStep | 2076 | 4 拍 | 1 拍 |

共 7861 个事务，另在复位前取消 15 个在途事务。覆盖极值、负数、相位回绕、零步长、零种子、量化/削波边界、参数与标签逐拍变化、随机气泡、长时间反压和复位后无旧标签返回。3～4 拍是在本核心无反压时的消费延迟，不是按键到声音的延迟，也不是整帧合成预算。

[严格门禁报告](reports/gate.md) 尚未通过。其结果与功能仿真分开保留：解析/AST/注释/profile 检查通过，readability/naming 仍有失败；包括区域/注释约束、常量表达、复位到 ready 的检查，以及把反压使能展开后超出三操作预算的报告。不能把这些检查描述为全部通过，也不能据仿真直接宣布 50 MHz 布线已满足。

每个 RTL 都有 [接口合同](spec/operators.json)、同名规范和 WaveDrom 时序图，规格以最终 RTL 端口交叉检查。当前不修改板级源列表，不计入已有板上资源数字。

## 6. 后续工作

基础完整算子、驻留音色银行、48份逻辑状态、动态声部和持续采样调度已实现，详情见 ENGINE.md。接下来收敛静态交付检查与板级时序，连接键床/串口/AXI主控/音频输出和 Rust App；再扩展 DX EG、调制矩阵、滤波/FX、抗混叠及抢音淡化。当前没有完成板级集成的结论。

## 7. 复现

在本目录运行参考模型以重建向量，然后使用现有 Vivado 2025.1 的 xvlog/xelab/xsim：

```text
python model/voice_operator_model.py
xvlog rtl/AxisPhasePm.v rtl/AxisEnvelopeSegment.v rtl/AxisGainMix.v rtl/AxisNoiseStep.v sim/tb_voice_operators.v
xelab work.tb_voice_operators -s voice_operators
xsim voice_operators -runall
```

严格门禁命令保留 `--spec spec/operators.json` 与 `--formatter-profile formatter-profile.json`；该 profile 只设定标准格式及正确的项目元数据，没有放宽质量规则。最终文件哈希和验证结果见 [verification.json](reports/verification.json)。

## 8. AXI 子系统新增验证

新增参考生成：`python model/voice_fabric_model.py`。三套测试平台共用 `sources.f`，在本目录依次执行：

```text
xvlog -f sources.f sim/tb_voice_operators.v sim/tb_voice_fabric.v sim/tb_axi_voice_endpoint.v
xelab work.tb_voice_operators -s voice_operators
xsim voice_operators -runall
xelab work.tb_voice_fabric -s voice_fabric
xsim voice_fabric -runall
xelab work.tb_axi_voice_endpoint -s axi_voice_endpoint
xsim axi_voice_endpoint -runall
```

本轮三套回归均通过：原 7861 次算子结果、多段包络 7392 次、混合路由 1800 次完成结果（1828 个输入拍），以及通过 AXI 的 352 次算子调用。AXI 测试完成 1081 条写事务、957 条读事务；包括字节写掩码、W 先于 AW、FIXED/INCR、最大长度读写、非法请求、队列压力、读快照与 POP 并发、在途复位，以及 192 步包络硬件结果反馈。

最终记录见 [fabric-verification.json](reports/fabric-verification.json)。当前全闭包严格报告为 [fabric_gate.md](reports/fabric_gate.md)，与旧四核 `gate.md` 区分。静态解析通过，格式 AST/readability/comment/naming/profile 仍未通过，包括 RAM 不逐项复位与格式器规则冲突、注释/命名、组合依赖和操作预算等；不能把功能仿真通过当作所有静态问题均已排除。报告中 testbench/toolchain 的 `not_requested` 仅指该静态门禁没有调用外部工具，实际 xsim 运行另有原始日志。

## 9. 上下文与重试回归

前一节保留上下文扩展之前的基线数字。最新的 AXI 回归为 1138 写、1007 读、368 个校验完成，新增 `tb_voice_context` 为 3587 输入拍、3563 完成、384 次重放，另以 `tb_keyboard_hold` 验证板级实际桥接模块只在按键变化时发事件。完整运行记录见 [context-verification.json](reports/context-verification.json)，最新严格门禁见 [context_gate.md](reports/context_gate.md)。

```text
python model/voice_context_model.py
xvlog -f sources.f sim/tb_voice_context.v
xelab work.tb_voice_context -s voice_context
xsim voice_context -runall
```

AXI 回归继续使用第 8 节命令。按键桥接回归需在独立仿真目录放置 32 行、每行 128 个十六进制零的 `note_profiles.hex`，然后编译实际 `keyboard-studio/src/KeyboardVoiceBridge.v` 和 `sim/tb_keyboard_hold.v`；本轮目录为 `reports/key-hold-run`。测试夹具不修改板级音色文件。

