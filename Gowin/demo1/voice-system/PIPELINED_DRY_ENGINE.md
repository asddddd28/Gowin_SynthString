# 关键路径分拍与关闭FX的整板结果

2026-11-02 23:12完成完整Gowin布局布线；同一50MHz/20ns约束，SDP拆分仍开启。**setup/hold失败均为0，Fmax50.425MHz，最差setup +0.169ns。固件已生成，未烧录。**

当前生产RTL默认关闭FX。源码及可选编译分支保留，Delay/Reverb不会实例化到当前整板，不是仅将wet音量置零。

## 四处分拍

| 路径 | 实现 | 调度影响 |
|---|---|---|
| Voice增益/声像 | state13保存当前值与target；state14平滑并复用reg_mod_gain/pan；state15叠加调制并限幅 | 利用现有声部准备周期，不加拍 |
| FM源求和 | state1分别保存两组三路signed34部分和；state4以signed35相加、饱和后补齐请求；state2才能发放 | 每个启用算子增加1拍 |
| DX力度缩放 | state1曲线/偏移寄存，state2乘灵敏度并按原公式舍入 | 不加拍 |
| DX电平更新和指数表 | state2保存起音base/距离；state3寄存增量乘积；state4电平/状态；state5用已寄存电平读ROM；state6结果、state7有效 | DX EG6→7拍，DX复合算子10→11拍 |

保留原定点位宽、符号、截位与饱和规则；无额外DSP计算单元。当前carrier、context写地址和反馈历史仍属于当前请求，下一行RAM预取包括新增state4。

## 资源和时序

比较对象为分拍前、含FX的`reports/voice-prefetch`。下面是**分拍与移除FX的合并净变化**，不是对FX单独删除实验的归因。

| 资源 | 分拍前含FX | 当前干声版 | 差值 |
|---|---:|---:|---:|
| Logic / 59904 | 27243 | 23087 | −4156 |
| Register / 60780 | 24091 | 20833 | −3258 |
| CLS / 29952 | 24493 | 21597（72.1%） | −2896 |
| BSRAM / 118 | 98 | 62（52.5%） | −36 |
| DSP / 118 | 94 | 58（49.2%） | −36 |
| Fmax | 47.551MHz | 50.425MHz | +2.874MHz |
| setup失败终点 | 62 | 0 | −62 |
| hold失败终点 | 0 | 0 | 0 |
| 最差setup slack | −1.030ns | +0.169ns | +1.199ns |

原来4类失败路径在本次整板STA中均不再违例。当前最紧路径已经转到`reg_operator_request`的反馈历史求和/乘法至`AxisFmOperator.reg_feedback_product`，+0.169ns；命令预检查+0.182ns、声部/音色选择+0.235ns也较紧。裕量仍不宽，不据此承诺以后随意加模块仍能通过。外部I/O预算仍非完整板级电气验收；PR1014时钟路由提示保留，不隐藏警告或放宽约束。

## 当前音频与控制通路

`键床ADC/去抖 或 UART → 命令仲裁 → AXI主控 → AXI从端/命令队列 → VoiceSynthEngine（LFO/调制 + 六逻辑算子）→ 四项PCM FIFO → SynthPcmOutput → PT8211`

每个物理VoiceSynthEngine、VoiceModulation、AxisLfoStep、AxisFmOperator、AxisDxEnvelope、AxisEnvelopeMulti/Segment均为一个；8声部×6个逻辑算子状态独立。FX引擎、Delay、Reverb均为0个物理实例，综合层级XML已检查不存在这些实例。

- `SynthSystemTop.C_FX_ENABLE=0`为默认整板配置，下传到Boot和Endpoint/Runtime。
- Boot选择`rom/boot_dry.hex`，4个预设和安全主音量共57条命令；不发送原先3条FX装载/提交命令。完整60命令ROM仍保留供可选FX构建。
- `0x04c`能力、`0x050`延时容量和`0x054..0x060`FX遥测为0。
- C0..C4仍返回带原tag/opcode的完成包，状态1（unsupported），不会默默成功；UART重复请求仍返回缓存回复。
- 采样周期1024拍，50MHz/1024≈48.828125kHz；既有PT8211 16bit双声道、键床扫描、UART频率不变。

内核`C_FX_ENABLE`默认1是为保留已有兼容回归；实际整板顶层明确传0。恢复FX需要重新构建并重新做整板时序，不能将可选分支的功能仿真通过当作其当前物理实现已验收。

## 功能回归

| 检查 | 实测结果 |
|---|---|
| 分拍算术模型 | 20万组运算、1024力度组合通过；各路由掩码/算子位置、符号、饱和 |
| DX包络 | 10096参考向量，7拍；7阶段复位取消与重发通过 |
| DX复合算子 | 1600参考向量，11拍；11阶段复位取消与重发通过 |
| Voice | 400帧逐样本参考、48算子、重试/延音/抢占/panic/复位/反压通过；本负载最大829拍 |
| FM1/DX混合 | 10240帧、147命令、4音色及格式切换屏障通过；本负载最大877拍 |
| 调度归属 | 147930请求/完成全部匹配，pending0；反馈历史/当前carrier/context/参数行通过 |
| 可选FX兼容配置 | native满载Voice834、含FX总链908、FX72拍；6132个完整音频帧整数参考通过，结束时另1帧在途 |
| 完成队列 | 4843接收、4839交付、4次被复位取消，8188次READY隔离检查通过 |
| 默认干声整板 | 57启动命令、66键事件、134串口回复、CRC重放、ADC/PT8211通过；PCM3436，PT8211帧3437（含初始化输出） |
| 干声计算期限 | 观测PCM脉冲最大878拍，native压力835拍；零drop/overrun/underrun |

Voice遥测与整板PCM脉冲观测相差一拍；835对应834，878对应877。878拍在50MHz下为17.56µs，这是计算路径观测，不包含采集/去抖、命令排队和DAC模拟响应，不能当作实际按键到声音延迟。全DX再启用全部LFO的理论预算为Voice882/PCM883拍，尚未将它冒称为本整板测试的实测值。

原1024拍deadline断言保留；测试预期仅按新的流水周期和实际观察点调整，没有放宽采样期限。新增调度夹具严格门禁0错误0警告，历史主RTL仍有严格风格/结构规范项失败，不能声称全工程满足该规范。旧函数/task使部分spec端口自动交叉检查误识别，相关规范通过人工核对接口后用已确认contract渲染。

## 固件与可复查证据

- 固件：`reports/critical-pipeline/build/impl/pnr/synth_fm1.fs`，未烧录。
- `reports/critical-pipeline/inputs.json`冻结43个构建输入；SDC与前版逐字节相同，完整结果记录于`result.json`。
- `analysis/summary.json`与`paths.json`：5000 setup、100 hold、100 recovery、100 removal展开路径；全局STA setup/hold失败0。
- `build/impl/gwsynthesis/synth_fm1_syn_rsc.xml`：物理生成前的模块资源归属；最终BSRAM/DSP用量以PnR报告为准。
- 同目录保存修改前源码、diff、分拍模型、测试日志及静态门禁报告。
