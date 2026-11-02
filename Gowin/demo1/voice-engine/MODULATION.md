# Modulation 首版：LFO 与稀疏调制路由

最新整机采用ABI0x00010005。路由现已拆成描述符读取→源/深度寄存→乘法→累加四级流水，每拍发一条路由；8条路由从启动到完成13拍，连续同目标写回保持次序，数值及LFO推进语义不变。完整8声部加FX的最重仿真为940/1024拍。下文首版ABI及上板描述属历史；本轮实际烧录和App结果见 [BOARD_TEST.md](../voice-system/BOARD_TEST.md)。

2026-11-02。已将 LFO 接入当前候选 Voice Engine，能够调制持续音，配置通过同一个 AXI-MM 入口装载。ABI 为 **0x00010003**；旧 A0…A9 和 raw/context 命令兼容。板级键床、DAC 和 Rust App 仍使用原固件接口，本轮没有烧录板卡或添加 App 控件。

## 当前结构

```text
AxiVoiceEndpoint → AxisSynthSystem → VoiceSynthEngine
                                      ├─ VoiceModulation ×1
                                      │  ├─ 双银行：每音色2个LFO、8条路由
                                      │  ├─ 8份音色全局状态 + 16份声部局部状态
                                      │  ├─ AxisLfoStep ×1（五级流水、II=1）
                                      │  └─ 路由乘加器 ×1，15个目标累加槽
                                      └─ AxisFmOperator ×1，服务8声部×6算子
```

本目录现在共 **13 个 RTL 模块定义**。LFO 有24个逻辑状态槽，并不需要24个物理振荡器。同一源在一帧只推进一次，所有引用它的路由复用同一结果。一个音色的同一个 LFO 选择全局或逐声部模式，不同时计算两种模式。

Modulation 目前是现有 AXI 外设内的子引擎，**不是另一个已完成独立地址译码的 AXI Slave**。可复用的 `AxisLfoStep` 使用私有 ready/valid 原子任务接口；以后拆出独立 Modulation Slave 可保留算子和状态语义。

## LFO 功能

| 功能 | 当前实现 |
| --- | --- |
| 波形 | 正弦、三角、上升锯齿、下降锯齿、脉冲、Sample & Hold、平滑随机 |
| 输出 | signed32 Q26，双极±1或单极0…1 |
| 速率 | 32位相位增量，驻留命令允许0…约100 Hz；0 Hz保持相位 |
| 相位 | 配置起始相位；逐键起音或显式RESTART时使用 |
| 脉冲 | 32位相位比较阈值；可配置占空比 |
| 随机 | 独立xorshift32状态，seed=0归一为1；仅整周期回绕或重触发时推进随机数 |
| 平滑随机 | 在上一随机端点与下一端点之间按完整32位相位线性插值 |
| Global | 每音色共享一个相位；音色有效且LFO启用时，即使没有声部也继续运行 |
| Voice | 每个声部独立相位与随机状态，新的NoteID分配时重触发；释音期间继续，回收后冻结 |
| 手动重触发 | B3指定逻辑上下文，在下一次符合执行条件的采样使用配置的phase/seed重启 |
| 速度同步 | 编译器将BPM及每周期拍数换算为相位增量；尚未实现MIDI Clock锁相或实时Tempo跟随 |

引擎采样率为50 MHz / 1024 = 48,828.125 Hz；速率分辨率约0.00001137 Hz。正弦使用1024点ROM与22位邻点插值。所有LFO目前**逐采样更新**，没有32/64采样控制块造成的阶梯；后续控制率优化需另加插值，不能直接降低更新率。

新NoteID触发本声部的局部LFO；相同NoteID的重复起音、相同sequence的包重放不触发。Global不因任意一个键起音而复位。参数银行提交保留已有相位/随机状态；改phase/seed后若要立即重新开始，可发B3。禁用LFO保留状态，再启用继续运行；禁用整个引擎冻结所有LFO并输出静音。

## 调制路由与单位

每个音色最多8条路由，源为LFO0或LFO1，可多对一、多对多。路由运算为：

```text
contribution = floor(source_Q26 × signed_depth / 2^26)
target_delta = saturate_signed32(sum(contribution))
effective_parameter = clamp(base_parameter + target_delta)
```

源、相位和包络状态不因同一源被多次读取而推进。各目标用36位累加保护位，所有路由相加后才饱和。有效参数单独计算，**不回写基础参数**，因此不会逐采样漂移。

| target | 含义 | depth单位与应用 |
| --- | --- | --- |
| 0 | 声部音高 | Q26频率比例；最终`base_increment × (1 + delta)`；delta限于±1，频率字限于0…0x7fffffff |
| 1 | 声部音量 | Q26加法；基础LIVE音量先平滑，再叠加调制，结果限0…1 |
| 2 | 声像 | Q26加法；0为左、1为右，结果限0…1 |
| 3…8 | 算子0…5增益 | Q26加法，最终限0…1 |
| 9…14 | 算子0…5调制深度 | PM/FM为signed整圈相位字；AM/Ring为Q26，分别按各自合法范围限幅 |

音高调制是**线性频率比例**，例如depth=0.006表示±0.6%频率；不等于精确的对称半音/cents调制。固定频率算子仍使用自身频率字，不跟随声部基频调制。

颤音可用双极正弦→pitch；颤幅可用单极LFO→gain并设置负深度，例如-0.55让基础音量1在0.45…1间变化；自动声像可用双极LFO→pan；音色运动可路由到算子电平或FM深度。脉冲/S&H本身具有阶跃，音量或深度参数突变仍可能出现点击，并未加入全目标去点击滤波。

## 配置命令

沿用暂存窗口、COMMIT和Completion。高层控制共用epoch/sequence；新命令同样受精确重放、冲突、过旧和跳号检查保护。

| opcode | 命令 | address | payload低字起 |
| --- | --- | --- | --- |
| B0 | LFO_CONFIG | patch×8+lfo，lfo=0/1 | increment、start phase、flags、seed、pulse threshold；其余0 |
| B1 | MOD_ROUTE | patch×8+route，route=0…7 | flags、signed depth；其余0 |
| B2 | LFO_INSPECT | context=0…23 | 全0 |
| B3 | LFO_RESTART | context=0…23 | 全0 |

B0 flags：wave `[2:0]`=0…6，对应上述波形顺序；unipolar `[3]`；voice scope `[4]`，0表示global；enable `[5]`；其余0。increment最大8796093。phase与pulse threshold为32位整圈相位字，pulse判断为phase<threshold。

B1 flags：enable `[0]`，source `[1]`=LFO0/1，target `[5:2]`=0…14；其余0。depth是32位二进制补码。非法波形、速率、目标、地址或保留位返回状态8；未开始草稿返回9。路由指向未启用LFO时贡献为0。

装载顺序：`A0 PATCH_BEGIN → 六份CORE/EG → 可选B0/B1 → A3 PATCH_COMMIT`。BEGIN将**草稿银行**的LFO和路由启用位清空，因此旧音色不写B0/B1也能正常提交，默认没有调制。A3在帧边界原子切换音源、EG和调制配置；装载草稿期间当前音色不变。完整音色重新装载时，需重新声明希望保留的LFO/路由。

B2/B3逻辑上下文编号：

- 0…7：`patch×2+lfo`，音色全局源。
- 8…23：`8+voice_slot×2+lfo`，声部局部源；voice_slot是NOTE_ON返回的硬件槽，不是NoteID。

B2结果W0=value，W1=phase，W2 bit10=initialized，W3=RNG；公共状态仍在W2低8位，重放标志在W2 bit8。未初始化/未执行的状态不代表当前音色有效调制值。B3成功只预约重触发，不立即清零已有输出；下次源符合执行条件时重启。精确重发已执行的B3会回放完成结果，不再次重触发。

新增只读 `0x048=0x0002087f`：每音色2个LFO、8条路由、7种波形。`0x040`继续报告完整渲染周期，`0x03C`报告采样期限错过。

## 时序和资源

一帧先扫描24个源状态槽，仅对符合scope/enable/voice条件的源发送任务；`AxisLfoStep`以II=1执行，最早完成握手延迟5拍。等待全部源回写后，对每个活动声部依次累加8条路由，再运行它的六算子音频程序。不同音符共享global值，局部值相互隔离。

验证配置同时启用8个声部、48个音频算子、每音色2个LFO和8条路由，最重一帧 **858拍**；相对于1024拍采样预算剩166拍。按50 MHz换算为17.16 µs计算时间、3.32 µs余量；这只是已验证的周期预算，尚不是布局布线后的50 MHz保证或按键到DAC延迟。

Gowin综合以 `VoiceSynthEngine` 为顶层，包含Modulation而不含旧raw/context分支和外部AXI适配。最新数字及原始报告见 [lfo-verification.json](reports/lfo-verification.json) 与 [Gowin报告](reports/gowin-lfo/impl/gwsynthesis/voice_lfo_syn.rpt.html)。约50% Logic、35%寄存器、24 BSRAM、36个MULT27X36原语、0锁存器。顶层768个探针信号应留在芯片内部，不能直接作为板级管脚设计；没有PnR或新固件烧录结论。

## 验证和使用

- LFO算子：3560次独立整数模型对照，覆盖7波形、双/单极、回绕、零种子、重触发、长反压、II=1和在途复位。
- 完整引擎：1600帧立体声、38400份源状态逐位比较；覆盖四音色、多键错峰起音、GLOBAL/VOICE、所有目标、路由叠加饱和、LIVE、延音/释放、活动银行更新、显式重触发及重放。
- AXI：三组真实编译器输出装载后持续出声，验证配置、源观察、重复NoteOn、重放、非法请求、无声部时global继续运行和B3重启。
- 原有八套功能回归通过。最新结果与文件SHA256见上述验证清单。

```powershell
python model/lfo_model.py
python model/lfo_engine_vectors.py
python model/compile_voice_patch.py examples/LFO_Vibrato_Keys.json --slot 0 --epoch 1 --sequence 0 --output examples/LFO_Vibrato_Keys.commands.json
```

JSON音色可加入如下字段：

```json
{
  "lfos": [
    {"wave":"sine", "scope":"voice", "rate_hz":5.5, "phase":0, "seed":1},
    {"wave":"triangle", "scope":"global", "beats_per_cycle":4, "seed":2}
  ],
  "tempo_bpm":120,
  "routes": [
    {"source":0, "target":"pitch", "depth":0.006},
    {"source":1, "target":"pan", "depth":0.3}
  ]
}
```

以上字段合并到已有六算子音色，不是省略operators也能编译的完整文件。target名称支持pitch/gain/pan、op0_gain…op5_gain、op0_depth…op5_depth。PM/FM算子depth路由使用整圈相位比例，其余目标使用归一化量。

完整示例：[LFO_Vibrato_Keys](examples/LFO_Vibrato_Keys.json)、[LFO_Tremolo_Pad](examples/LFO_Tremolo_Pad.json)、[LFO_Random_FM](examples/LFO_Random_FM.json)。编译器只生成命令与AXI写列表，不连接板卡。`rate_hz`与`beats_per_cycle`二选一，频率/波形/路由等参数均做合法性检查。

## 尚未完成

LFO Delay/Fade包络、更多LFO数量、任意外部源（宏、调制轮、触后等）、准确半音映射、实时MIDI Clock锁相、滤波目标以及独立Modulation AXI地址窗口，仍是后续扩展。当前音频率计算已足够平滑；降低控制率需要插值设计和重新验证。

严格RTL门禁 [lfo_gate.md](reports/lfo_gate.md) 尚未通过，静态解析通过，格式AST/注释/命名/组合操作预算等仍有失败；功能仿真和综合不能代替这一结论。`readable-verilog-generator` 要求“zero errors and zero strict warnings”，因此当前保持候选模块状态。板级集成与App旋钮界面另行推进。
