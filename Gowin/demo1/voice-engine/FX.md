# 共享立体声 FX：Delay + Reverb

更新：2026-11-02。当前控制流水候选未烧录，见 [FX控制寄存实验](../voice-system/FX_CONTROL_PIPELINE.md)。早期子系统证据见 [fx-verification.json](reports/fx-verification.json)。

整机扩展：板级包含 Master、键盘、UART 和 PT8211。当前回归满载为 Voice874 / 含FX整链948拍，50MHz物理收敛状态以 [资源与时序](../voice-system/RESOURCE_TIMING.md) 为准。下文931拍和早期综合资源保留为历史记录。Delay地址位数库默认15，当前整板为13，能力字和参数上限随配置变化，整板最大约167.772 ms。外部仍共享一个AXI Slave入口。

## 接口与层次

外部使用现有 **32 bit AXI4 内存映射 Slave**，通过参数暂存、COMMIT 和 Completion 队列控制。新增 FX 是独立 C0…C4 命令域，音频在 FPGA 内持续处理，上位机不用逐样本发任务。当前 Voice、LFO、FX **共享一个 AXI Slave 入口**；尚未实现三个独立 Slave 地址窗口、全局 AXI Master 或共享 RAM DMA。

```text
AxiSynthEndpoint                              精简综合顶层 ×1
└─ AxiVoiceEndpoint (LEGACY_ENABLE=0)           AXI-MM / CMD4 / Completion4
   └─ AxisSynthSystem                          1024拍采样节拍、完成仲裁
      ├─ VoiceSynthEngine                     8声部 × 6逻辑音频算子
      │  ├─ VoiceModulation                   每音色2 LFO、8路调制
      │  │  └─ AxisLfoStep                     物理LFO流水线 ×1
      │  └─ AxisFmOperator                    物理音频复合算子 ×1
      │     └─ AxisEnvelopeMulti
      │        └─ AxisEnvelopeSegment
      ├─ PCM输入FIFO                          深2
      ├─ AxisFxEngine                         独立参数、序号缓存、尾音状态
      │  ├─ AxisStereoDelay                   立体声Delay ×1，两条环形线
      │  └─ AxisSchroederReverb                Reverb ×1，8条逻辑延迟线
      └─ PCM输出FIFO                          深4 → 后续板级DAC适配
```

目录共有17个RTL定义，精简顶层使用其中12种。`AxiVoiceEndpoint.LEGACY_ENABLE` 默认1，保留旧raw/context及回归入口；精简顶层设为0。此时 `0x00c/0x01c/0x030` 返回0，旧命令返回status=1。全兼容配置加FX超出本器件逻辑容量。

音频顺序：**声部混音 → Delay → Reverb → PCM FIFO**。两个效果各有干湿比，是共享串联insert链；尚无每声部send、并行return或任意效果图。Reverb以左右均值激励，通过不同全通延迟产生立体声尾音，干声保留原立体声。

## 功能与数值

| 项目 | Delay | Reverb |
| --- | --- | --- |
| 结构 | 左右独立延迟、线性分数插值、ping-pong | 4路低通反馈comb，左右各2级真正allpass |
| 时间 | 每声道1…32767.999985采样，约0.02048…671.08864 ms | comb：1493/1601/1747/1999；左AP：211/431；右AP：263/487采样 |
| 参数 | 左右时间、正/负反馈、wet、启用、交叉反馈 | 反馈、阻尼、wet、启用 |
| 反馈边界 | ±63753420 / 2²⁶，略小于0.95 | 0…60397977 / 2²⁶，略小于0.9 |
| 阻尼边界 | 无独立阻尼 | 0…63753420 / 2²⁶ |
| RAM | 32768×18 bit×2声道 | 10240×18 bit，单端口分时读写 |

32位signed Q26音频/参数，64位乘积，65位累加。反馈RAM为 **18位signed Q16**，范围 `[-2, 2−2⁻¹⁶]`，量化步长约−96.3 dBFS，不能称为24位效果精度。反馈写回朝零截断，避免微小负值向下取整产生静态极限环；反馈存储饱和到可表示范围，最终输出饱和到±1。`clipped_frames` 标记至少一处饱和；没有自动响度压缩器或软限幅器。

Delay插值 `a + floor((b−a)×fraction/65536)`，写回 `injection+feedback×echo`，交叉模式使用对侧echo。干湿混合 `dry×(1−wet)+effect×wet`。

Reverb的comb阻尼状态 `lp=(1−d)×delayed+d×old_lp`，写回 `(1−g)×mono+g×lp`，四路均值送入allpass。allpass系数0.5，`y=delayed−0.5×x`、`state=x+0.5×y`。精确舍入位置见 [fx_model.py](model/fx_model.py)。结构参考 Julius O. Smith 的 [Schroeder Reverberators](https://www.dsprelated.com/freebooks/pasp/Schroeder_Reverberators.html) 与 [Freeverb低通反馈结构](https://www.dsprelated.com/freebooks/pasp/Freeverb.html)；本实现不是完整Freeverb、Surge Reverb或真实房间模型。

## 状态与实时行为

- NoteOff、换音色和Voice Panic不清共享尾音；无声部时继续用零输入推进效果。
- disabled返回精确干声，内部零注入但继续衰减；再次启用可能听到剩余尾音。
- C3帧间清空指针、有效年龄、滤波状态，不复位整块RAM；无效历史读零。
- C2在FX帧间原子切换全部参数，一帧不会混用两个版本。
- 控制先预译码，再寄存校验结果与五位执行动作，最后在真实握手沿执行；空闲命令比原实现增加一拍校验。音频到达取消未接受快照并优先处理，结束后重新校验，音频计算周期不增加。
- 延迟时间、开关和wet瞬变可能有跳变；尚无参数斜坡、新旧读头交叉淡化，实时旋钮控制还需补这一层。
- C3不撤回已排队PCM，最多仍有4个旧输出帧；立即静音还需要板级输出策略。
- 核心背压时不重复写状态；系统PCM满时丢新帧并计数，FX仍持续计算。输入队列异常满也丢新帧并单独计数。

## AXI命令与寄存器

ABI `0x00010004`。`0x100..0x124`暂存十个payload字，`0x128` opcode、`0x12c` tag、`0x134={epoch24,address8}`、`0x138` sequence，写 `0x130` bit0原子入队；读完成后写 `0x218` POP。

FX的epoch/sequence**独立于Voice A/B域及旧上下文域**。初始seq=0，之后连续。最新相同请求可换tag重发，返回缓存并置bit72，不重复提交/清空；冲突=5、旧序号=6、跳号=7、epoch不符=4，不消耗序号。合法下一序号中的参数错误=8会消耗并缓存。只缓存最近一条，复位失效，序号耗尽需重建会话。

未定义payload位必须为0。W0是最低32位；完成status在 `[71:64]`，与AXI BRESP分开，入队成功仍须检查业务完成。

| opcode | address | payload或完成内容 |
| --- | --- | --- |
| C0 | 0 | Delay草稿：W0左时间Q16.16、W1右时间、W2 signed反馈Q26、W3 wetQ26、W4 bit0 enable/bit1 pingpong |
| C1 | 0 | Reverb草稿：W0反馈Q26、W1阻尼Q26、W2 wetQ26、W3 bit0 enable |
| C2 | 0 | payload全零，提交两个草稿；完成W0返回revision |
| C3 | 0 | W0 bit0清Delay/bit1清Reverb，至少一位置1 |
| C4 | 0 | payload全零；完成W0帧数、W1削波帧数、W3最近FX周期 |
| C4 | 1 | payload全零；完成W0/W1活动Delay时间、W3 Delay标志 |
| C4 | 2 | payload全零；完成W0 Delay wet、W1 Delay反馈、W3 Reverb wet |
| C4 | 3 | payload全零；完成W0 Reverb反馈、W1阻尼、W3 revision |

| 只读地址 | 意义 |
| --- | --- |
| 0x04c | `0x040f1203`：高到低字节=4 comb、15位Delay地址、18位存储、bit0 Delay/bit1 Reverb |
| 0x050 | 最大整数延迟32767采样 |
| 0x054 | FX完成帧数 |
| 0x058 | FX削波帧数 |
| 0x05c | FX输入丢帧数 |
| 0x060 | 最近FX周期，不含输出背压等待 |

计数器32位自然回绕。跨地址读取不是原子快照，一致快照用C4。原 `0x040` 仍仅表示Voice周期，`0x044` 为最终PCM丢帧。

## 主机配置

[compile_fx.py](model/compile_fx.py) 将毫秒和归一化参数编译成C0/C1/C2及AXI写序列；示例有 [短延时房间](examples/fx_room.json) 和 [Pad空间](examples/fx_pad_space.json)。

```powershell
python model/compile_fx.py examples/fx_pad_space.json --output examples/fx_pad_space.commands.json --epoch 1 --sequence 0
```

这是离线编译器，不连接串口；调用方逐条检查完成，维护FX独立序号。新AXI入口的UART桥、Rust调用和App旋钮尚待集成，不能把JSON直接发给旧板级UART协议。

## 验证、资源与边界

- Delay 80000帧、Reverb 100000帧与独立整数模型逐样本一致；包含分数/最大延迟、正负交叉反馈、旁路、满幅、参数边界、清空、复位取消、背压及尾音衰减。
- 真实AXI装载4音色、8声部48算子及LFO/FX；验证草稿隔离、重试、非法参数、完成FIFO堵塞、尾音独立、PCM溢出。FX输入/输出再由Python逐帧重算。
- 50MHz：最重Voice帧858拍，FX接受到结果71拍，tick到全链结果931拍=18.62µs，1024拍预算余93拍。这是**计算路径时限**，不是实体键到DAC总延迟，也不是回声时间。
- 精简完整 `AxiSynthEndpoint` Gowin综合：Logic45777/59904（77%）、Register25354/60780（42%）、BSRAM114/118（97%）、MULT27X36共59个、Latch0。仅余4块BSRAM，后续键盘/串口/滤波和长延迟需重新预算。综合不证明布局布线50MHz达标。
- 全兼容 `LEGACY_ENABLE=1` 的一次综合Logic65160/59904，超量；保留仿真兼容，不作为本板部署配置。
- 严格格式/AST/注释/命名/组合预算门禁仍失败，分别记录功能、综合和格式证据。没有本轮板级PnR、烧录或听音结论。

下一步：参数平滑、send/return、反馈存储布局优化/外部RAM、板级与App连接。Chorus/Flanger、更多Reverb算法、实时tempo锁定和FX调制路由尚未实现。
