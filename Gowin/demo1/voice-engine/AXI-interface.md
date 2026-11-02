# Voice Engine：AXI 外设接口与后续集成

2026-11-02。本文件落实用户提供的“五层架构与 AXI 调度”图。当前为独立候选子系统，功能仿真通过，严格静态交付门禁未通过；没有替换板上演奏顶层。新内核的单独综合资源见 [ENGINE.md](ENGINE.md)，没有本轮板级布线时序结论。

最新扩展为持续发声的8声部/6算子内核、独立PCM FIFO与A0..A9控制命令，见 [ENGINE.md](ENGINE.md)。下文 raw/context 的局部通路图保留，完整 hierarchy 以 ENGINE.md 为准。

已加入驻留上下文与重发处理，详见 [CONTEXT-and-retries.md](CONTEXT-and-retries.md)。下文保留基础算子格式，新增命令通过 `AxisVoiceRuntime` 转换后共用原有 Fabric。

新增调制B0…B3与0x048能力寄存器见 [MODULATION.md](MODULATION.md)。当前ABI 0x00010004，C0…C4共享FX、0x04c…0x060遥测和精简顶层见 [FX.md](FX.md)。下图是目标地址空间和旧分支；当前三个命令域共享一个AXI Slave，不是三个独立Slave。

## 外部互联与内部执行

目标系统使用 **AXI4 内存映射互联**。FPGA 主控取指并作为 AXI Master，RAM、Voice Engine、调制矩阵、FX 和 PCM FIFO 提供 Slave 地址窗口。AXI4-Stream 留在执行外设内部，用于算子之间的任务和结果传递。

```text
目标公共设施（尚待实现）
Program / Param / State / Scratch RAM ← AXI4 → FPGA 主控 Master
                                             │
                      ┌──────────────────────┼──────────────────────┐
                      ▼                      ▼                      ▼
               Voice Engine Slave       Modulation Slave        FX Slave
               本轮候选实现              待实现                  待实现

AxiVoiceEndpoint 内旧 raw/context 分支（入口另有 AxisSynthSystem，见 ENGINE.md）
AXI AW/W → 参数暂存 → COMMIT → CMD FIFO(4) → AxisVoiceRuntime → AxisVoiceFabric
                                                    │
                    ┌──────────┬───────────┬─────────┼──────────┐
                    ▼          ▼           ▼         ▼          ▼
                 PhasePM    Segment     GainMix    Noise     MultiEG
                    └──────────┴───────────┴─────────┴──────────┘
                                                    │ 按完成情况仲裁
AXI AR/R ← 队首读快照 ← Completion FIFO(4) ← result / tag / opcode
AXI AW/W → POP ────────────────┘
```

该外设只有 Slave 端口，**不能自行向共享 RAM 发起读写**。raw 模式由调用者传入状态、参数和操作数并回收新状态；新增缓存模式由调用者先 BIND 参数与初始状态，再由 Runtime 管理本地状态。以后若执行器需要自主访问共享 RAM，必须增加明确的 DMA/Master 接口，或者由主控先装载执行器本地缓存；不能因为它挂在 AXI 上就假定它能主动读别的 Slave。

## 旧 raw/context 分支的 hierarchy 与物理实例

```text
AxiVoiceEndpoint                         ×1
└─ AxisVoiceRuntime                      ×1，含32项逻辑上下文
   └─ AxisVoiceFabric                    ×1
      ├─ AxisPhasePm                    ×1
      ├─ AxisEnvelopeSegment            ×1
      ├─ AxisGainMix                    ×1
      ├─ AxisNoiseStep                  ×1
      └─ AxisEnvelopeMulti              ×1
         └─ AxisEnvelopeSegment         ×1
```

因此共有 5 种可调用操作，5 个基础算术核心实例：PM×1、段步进×2、乘加×1、噪声×1。MultiEG 是阶段控制和段步进的组合，不能再把它作为另一个独立算术核心重复计数。CMD 与 Completion 各深 4；算子流水和路由入口/出口还能容纳在途任务，队列计数不等于全部在途数。PM 队列压力测试中有 11 条已提交任务分布在完成队列、流水和命令队列，不能把 11 宣称为所有操作类型的统一容量。

## 外部 AXI4 支持范围

| 项目 | 当前约定 |
| --- | --- |
| 时钟 | 单一计算时钟，仿真 50 MHz；没有 CDC |
| 地址 | 16 bit 字节偏移；系统地址基址由未来互联译码 |
| 数据 / ID | 32 bit / 4 bit，AXI ID 与任务 tag 是不同概念 |
| 在途事务 | 一条读突发、一条写突发，可同时执行 |
| 支持传输 | 32 bit 对齐，SIZE=2；INCR 最长 256 拍，FIXED 最长 16 拍 |
| 不支持项 | 窄传输、非对齐、WRAP、exclusive、跨 4 KiB 突发；返回 SLVERR |
| 写通道 | AW 与 W 独立；允许 WVALID 先到，但接受 AW 后才拉高 WREADY |
| 写响应 | 接受实际 WLAST 后产生 B；AWLEN/WLAST 不一致返回 SLVERR |
| 返回稳定性 | B 或 R 被反压时，VALID 与全部有效载荷保持 |
| 副作用 | COMMIT / POP 仅允许单拍；非法或满/空操作无入队/弹出效果 |
| 读一致性 | AR 握手时冻结完整完成队首；同一读突发不因并发 POP 而撕裂 |
| 复位 | 清除 AXI 在途事务、队列资格和内部流水；RAM 内容靠有效计数隔离 |

这里实现的是有明确限制的 AXI4 Slave，不是完整功能互联 IP，也不是 AXI4-Lite。CACHE/PROT/QOS 等可选属性没有在该端口暴露；接系统时由适配层按“不提供这些附加功能”的约定处理。非法突发整体不具备事务回滚：后续写拍出错时，之前合法的暂存字写入可能已生效，因此实际提交必须另发独立 COMMIT。

AXI 通道语义参考 [Arm AMBA AXI 协议](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf?hash=6325311012DDADF238C35A6C0FD734E520754F82&la=en&revision=71bd7c57-2ed7-487b-bc3e-68c4ab56fa5f)；本文的寄存器、错误处理和算子格式是本项目约定。

## 寄存器窗口

| 字节偏移 | 访问 | 含义 |
| --- | --- | --- |
| `0x000` | R | 标识 `0x56534531`，即 VSE1 |
| `0x004` | R | 接口 ABI `0x00010003`，兼容原 raw/context 操作并新增驻留声部命令 |
| `0x008` | R | CMD 数量[2:0]、Completion 数量[6:4]、CMD 满[8]、Completion 空[9] |
| `0x00C` | R | 支持的操作位图 `0x1F` |
| `0x010 / 0x014 / 0x018` | R | 成功提交 / 完成入队 / POP 计数，32 bit 自然回绕 |
| `0x01C` | R | 上下文/重放/观察功能位图 7 |
| `0x020…0x02C` | R | 实际运算 / 重放 / 拒绝 / 新绑定计数 |
| `0x030` | R | 逻辑上下文容量 32 |
| `0x034…0x044` | R | 新 Voice Engine 能力、活动声部、overrun、渲染周期、PCM丢帧，详见 ENGINE.md |
| `0x300…0x30C` | R | PCM队首左/右/帧号/有效，AR时原子快照，读取不弹出 |
| `0x100…0x124` | R/W | 十个 32 bit 参数/输入/状态字，低地址对应低位字 |
| `0x128` | R/W | opcode，只有低字节有效 |
| `0x12C` | R/W | 完整 32 bit task tag |
| `0x130` | W | COMMIT：WSTRB[0] 和 WDATA[0] 均为 1 时原子入队 |
| `0x134 / 0x138` | R/W | generation/context_id 元数据 / 缓存执行 sequence，原 raw 操作忽略 |
| `0x200…0x20C` | R | 四个结果字，共 128 bit |
| `0x210` | R | 完成任务 tag |
| `0x214` | R | 完成任务 opcode |
| `0x218` | W | POP：WSTRB[0] 和 WDATA[0] 均为 1 时释放队首 |

未知/只读地址写入、空结果读取、空 POP、满 COMMIT 返回 SLVERR。参数和 tag 支持 WSTRB 部分写，零写掩码不更改它们。

推荐调用顺序：

1. 用从 `0x100` 开始的 12 拍 INCR 写入 payload、opcode、tag，等待 OKAY。
2. 单拍写 `0x130 = 1`，等待 OKAY。SLVERR 表示本次未提交，可在检查容量后重试。
3. 主控可继续调度其他独立任务。**B/OKAY 只证明命令已入队，不证明运算完成。**
4. Completion 非空时，从 `0x200` 发起 6 拍读，获得同一份结果、tag 和 opcode。
5. 处理完成结果，再单拍写 `0x218 = 1`。读取本身不弹出队首。

暂存窗口当前仅支持一个逻辑提交者。多个 Master 必须在外部串行化“写参数→COMMIT”的整个过程；AXI ID 不会隔离各主机的暂存区。结果消费也需要单一所有者。

## 私有算子任务格式

Fabric 输入 `TDATA=320`、`TUSER=32`（task tag）、`TDEST=8`（opcode）、`TLAST=1`。前四种算子使用低 128 bit，MultiEG 使用全部 320 bit。每拍都是一个完整任务，所有字节均有效。外层 Runtime 输入为 384 bit，额外高 64 bit 携带上下文元数据和执行序号；它支持 BIND/RUN/INSPECT，并组装下面的原始计算任务。

| opcode | 操作 | 低位起参数 |
| --- | --- | --- |
| 0 | PHASE_PM | phase / increment / modulation Q26 / signed phase depth |
| 1 | SEGMENT | current signed32 / target signed32 / step unsigned32 / reserved |
| 2 | GAIN_MIX | a / gain_a / b / gain_b，均为 signed32 Q26 |
| 3 | NOISE | 低字为 xorshift 状态，其余保留 |
| 4 | MULTI_EG | current / control / L1…L4 / R1…R4 |

返回为 128 bit：低 64 bit 是各算子的结果，bits[71:64] 为任务状态（0 成功、1 未知操作、2 非单拍任务），高位保留为零；tag 和 opcode 原样返回。异常多拍任务只对第一拍返回一次错误，后续拍被排空至 TLAST，不执行运算。

每个核心内部保序，**不同核心之间允许乱序完成**；主控必须用 tag 查事务表。原 raw 操作没有同状态冲突检测或去重，调用者负责它们的状态所有权；新增缓存 RUN 则由 Runtime 检查 generation/sequence 并管理写回。tag 在两种模式中都仅用于传输匹配。路由入口只有一个待派发槽，会存在队头阻塞；后续可按资源预算增加分类队列。

## MultiEG 数值合同

四个目标 L1…L4 是 signed32，四个速率 R1…R4 是每次调用的 unsigned32 线性步长。control：stage[2:0]、event[4:3]、restart[5]；其余位忽略。

- stage：0 idle，1/2/3 分段，4 hold，5 release；6/7 非法。
- event：0 Tick，1 NoteOn，2 NoteOff，3 Kill。
- NoteOn 进入第一段；restart=1 从 L4 开始，否则从当前电平接续，并执行该次步进。
- NoteOff 让活动包络从当前电平进入第四段；idle 不被重新激活。Kill 直接变为 idle，电平设为 L4。
- 段到达后 1→2→3→hold；release 到达后 idle。一次任务最多推进一个阶段，零距离段也不在同次任务中连跳。
- 返回 level[31:0]、stage[34:32]、active[35]、reached[36]、stalled[37]、bad_stage[38]；其他位为零。
- idle/hold 保持电平，不报告 reached/stalled。非法旧阶段在 Tick/NoteOff 下停止并报 bad_stage；NoteOn/Kill 可恢复。

包络调用频率由调度器决定。本核心无阻塞时最早在接受后第 6 拍消费结果，II=1；这不等于外部 AXI 调用耗时。L4 可以非零，idle 不是“自动静音”，VCA/生命周期需按音色语义处理。它是通用四段线性包络，尚不包含 DX7 速率曲线、键盘缩放、力度映射或 Pitch EG 的音乐单位换算。

## 吞吐预算与下一步

原始内联快照接口首先用于可观察的外设调用验证。以 12 声部×6 逻辑算子为例，仅每个算子分别调用 MultiEG、PhasePM、GainMix 就有 216 条任务/采样；每条新任务写 12 个参数/标识字加 1 个 COMMIT，共 13 拍，**仅 W 数据就需 2808 拍**，超过当前 1024 拍/采样预算。此估算尚未计算波形、地址握手、读返回、滤波和效果。独立 R 通道可以重叠读写，也无法消除 W 通道的下限。新增缓存 RUN 已减少重复参数写入，但其串行检查、逐基础操作回读和握手开销仍需纳入预算，不能因此宣称 FM6 已达标。

后续实现顺序：

1. 已实现 32 项算子参数/状态快照与最近结果缓存；继续做跨声部参数共享和保持状态的实时参数版本提交，避免逐运算重传十个字。
2. 在相同 AXI Slave 框架内加入较粗粒度命令，例如 `RUN_OPERATOR` / `RUN_VOICE_FRAME`；这些是规划名称，尚无对应 opcode。
3. 子系统内部用私有任务流执行 EG→Phase→Sine/Wavetable→Gain，复用核心；反馈历史和依赖由本地运行时管理。
4. 外部主控下发短描述符并回收必要结果；根据实测再决定更宽数据总线、批量命令和 Completion 聚合。不能只靠增加 FIFO 深度解决平均带宽不足。
5. 完成静态门禁和 Gowin 综合/PnR 后，再将候选子系统接入板级主控、Mod/FX 和 PCM 输出并测整体截止时间。

测试入口包括 [tb_voice_fabric.v](sim/tb_voice_fabric.v)、[tb_voice_context.v](sim/tb_voice_context.v) 和 [tb_axi_voice_endpoint.v](sim/tb_axi_voice_endpoint.v)。最新证据、哈希和未通过的门禁见 [context-verification.json](reports/context-verification.json) 与 [context_gate.md](reports/context_gate.md)；`fabric-verification.json` 保留缓存扩展之前的基线。
