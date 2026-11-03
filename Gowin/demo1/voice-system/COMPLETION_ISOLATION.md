# 公共完成反压隔离实验（P0-A）

日期：2026-11-02，18:17 完成独立布局布线。目标频率保持 50 MHz。**完成反压隔离有效，但整板仍未通过 50 MHz 时序，未烧录。**

违例终点减少 72.0%、TNS 绝对值减少 64.8%；最差 Voice 声像乘法路径在新布局下变差，Fmax 降至 34.028 MHz。本轮保留为功能已验证的控制路径优化候选，不能据此声称系统已提速或达到 50 MHz。

## 变更范围

唯一修改的构建输入为 `../voice-engine/rtl/AxisSynthSystem.v`：将完成输出单槽扩展为输出槽加备用槽，每槽 168 位。上游接收容量只取本地备用槽有效位，切断 `AxiVoiceEndpoint.cnt_completion → READY → 各执行域控制写使能` 的组合传播。

音频计算状态机、Voice 算术、DSP 复位、存储映射、命令译码和接口均未改动。旧 RTL 和合同保存在 `reports/completion-isolation/AxisSynthSystem.before.*`，42 个原构建输入的哈希与唯一变化记录在同目录 `inputs.json`。

空队列接受首包后下一拍输出有效；非满情况下连续同时出入可每拍一包。两槽全满时，不借用同拍出队腾出的空间，下一拍才恢复接受。该边界有一拍接收气泡，正常连续传输没有新增首包延迟。复位清空两槽，轮询优先级只随实际接收推进。

## 功能证据

| 检查 | 结果 |
|---|---|
| 两槽 Python 队列状态穷举 | 14 周期压缩状态探索，共 3068 次状态转移通过 |
| `tb_completion_isolation` | 4843 接收、4839 交付、4 个复位取消；不丢、不重、不乱序 |
| 隔离与负对照 | 新版 8188 次无时钟 READY 翻转通过；旧版同测试在 52 ns 报组合传播 |
| `tb_axi_voice_endpoint` | 1144 写、1082 读、370 完成包比对；FIFO 饱和及 AXI 反压通过 |
| `tb_axi_fx` | 117 命令、6129 个已消费 PCM；Voice 866 / FX 72 / 整链 940 拍 |
| 完整音频整数模型 | 6133 帧一致，停止时没有遗留在途帧 |
| `tb_axi_synth_engine` | 快照、重放、实时提交、旧协议、溢出处理通过 |
| `tb_axi_lfo` | 3 个编译音色，71 命令；全局/局部、重放、非法输入通过 |
| `tb_synth_system` | 4 音色，66 键事件、134 UART 回复、3436 PCM；最大计算 940 拍 |

上述计数来自不同测试的独立统计边界，不能将“已消费 PCM”和“参考模型总帧数”直接等同。940 拍是在现有测试配置下的整链最大计算周期；1024 拍采样周期不变。未凭此声明所有可能的未来音色配置均能满足期限。

## 严格门禁状态

| 公共门禁 | 修改前 | 修改后 |
|---|---|---|
| compile | passed | passed |
| ast | failed：formatter template mismatch | failed：formatter template mismatch |
| readability | failed | failed |
| comment | failed | failed |
| naming | failed | failed |
| profile | failed | failed |
| testbench | 静态门禁未请求 | 静态门禁未请求；外部仿真另列 |
| toolchain | 静态门禁未请求 | 外部 xsim 已通过；PnR 完成但 50 MHz STA 未通过 |

严格报告错误总数从 540 变为 559，strict warnings 均为 10。新增逻辑仍沿用旧模块格式，因此严格格式/命名/注释规则有新增发现，不能将所有问题称为原有问题或宣称严格交付门禁通过。为保持此次物理对照只有一个功能变量，本轮不同时重排整个历史模块；本结果是有功能验证的时序优化候选。完整报告为 `reports/completion-isolation/{before,after}-gate.{json,md}`。

新增测试 `tb_completion_isolation.v` 自身的严格门禁为 **passed，0 错误、0 strict warnings**，报告为 `testbench-gate.json`。测试最后仅补充语义注释，已核对所有非注释内容未变化。

## 物理验证方法

独立目录 `reports/completion-isolation/build/`，从同一 50 MHz、同一器件/引脚/工具选项重新综合和布局布线。SDC 仍为 20 ns 时钟，只扩大报告到 5000 条 setup 路径、每终点一条，并报告 hold/recovery/removal。基线 `reports/timing-audit-20261102/` 保持不变。

已解析 5000 条 setup 路径，完整覆盖报告中的 347 个失败终点，5000 条路径的 cell/net arc 延迟加和均通过一致性检查。hold 总失败终点为 0；已报告的 100 条 recovery 与 100 条 removal 也没有负裕量。两次构建的器件、50 MHz 约束、CST、place/route 选项一致，42 个构建输入在本次运行期间未变化，旧基线时序报告哈希未变化。

综合中间报告：寄存器 23643 → 23787（+144），LUT 20801 → 21155（+354），ALU 5501 → 5502。物理映射优化了部分常量字段，因此新增寄存器数不等于完整备用槽宽度加有效位。乘法器、BSRAM 和 SSRAM 原语数量未变；LUT 变化分布于多个层级，不能把全部差值解释为备用槽的直接成本。PnR `device.cfg` 与基线逐字节一致。

## 全部 STA 结果对比

| 指标 | 原基线 | P0-A 候选 |
|---|---:|---:|
| 约束频率 | 50 MHz | 50 MHz |
| Setup 失败终点 | 1240 | 347 |
| Setup TNS（工具汇总） | −1776.880 ns | −625.236 ns |
| Setup WNS | −7.821 ns | −9.387 ns |
| 报告 Fmax | 35.944 MHz | 34.028 MHz |
| Hold 失败终点 | 0 | 0 |
| 以 cnt_completion 为起点的失败路径 | 1023 | 0 |
| 以 reg_command_head 为起点的失败路径 | 3 | 171 |

当前报告最差路径不再经过完成计数器。命令头路径由原来的 3 条变为 171 条，可能包括原本被更差完成反压路径掩盖的同终点路径，也受重新布局影响；**不能将其全部解释为新引入的逻辑错误**。每终点只报告最差路径，因此这里的数量不代表所有可达组合路径数。

| 失败终点所属模块 | 原基线 | P0-A | 当前来源 |
|---|---:|---:|---|
| VoiceSynthEngine | 709 | 118 | 116 内部 + 2 命令头 |
| AxisSchroederReverb | 388 | 116 | 命令头控制 |
| VoiceModulation | 60 | 6 | 命令头控制 |
| AxisStereoDelay | 29 | 0 | 本次没有失败终点 |
| AxisFmOperator | 29 | 29 | 正弦 ROM 到插值寄存器 |
| AxisDxEnvelope | 11 | 31 | 速率 ROM 到指数 ROM/电平/移位 |
| AxiVoiceEndpoint 自身 | 10 | 0 | 本次没有失败终点 |
| AxisFxEngine | 4 | 47 | 命令头控制 |
| 合计 | 1240 | 347 | 176 内部 + 171 命令头 |

当前最差路径所在的 `VoiceSynthEngine.reg_mod_pan → reg_left_product` 路径族共有 32 个失败终点。最差路径数据延迟 29.313 ns，其中 net 23.429 ns、cell 5.884 ns，WNS −9.387 ns。第二类严重路径为 `AxisDxEnvelope` 的速率 ROM 到指数 ROM，最差 WNS −6.222 ns。命令头控制路径最差落在 Reverb 的 `reg_comb_sum/CE`，WNS −3.407 ns。

## 最终物理资源

| 资源 | 原基线 | P0-A | 变化 |
|---|---:|---:|---:|
| Logic | 27189/59904 | 27531/59904 | +342 |
| Register | 23643/60780 | 23787/60780 | +144 |
| CLS | 24379/29952 | 24310/29952 | −69 |
| BSRAM | 98/118 | 98/118 | 0 |
| DSP | 98/118 | 98/118 | 0 |

CLS 报告占用仍为 82%，BSRAM/DSP 仍为 84%。综合 LUT 统计与最终 PnR Logic 是不同口径，不应混用。

## 下一轮修改边界

1. 按用户优先级，先单独处理 **VoiceSynthEngine 声像乘法**：预先寄存左右声像系数，分析乘法器拆分与结果拼接的实际网表路径，必要时在乘法前后增加寄存边界；保留有效位、非活动声部清零和原有定点数语义。27 位无符号 Q26 系数包含 2^26，转换为有符号至少需要 28 位。
2. 再处理 Voice 的 gain/pan 平滑与算子参数选择长链，保持禁用/非活动声部每帧平滑行为。新增周期须以整链 940/1024 拍预算重新验证，不能只看 Voice 子模块的 866 拍。
3. P0-B 独立隔离命令头译码/控制，再处理 DX 包络 ROM 串接和 FM 插值；每次只改变一个可审查的计算或控制边界，分别做仿真、独立构建和完整端点统计。

原始结果：`reports/completion-isolation/analysis/summary.json`、`setup-violations.csv`、`paths.json`；机器可读对比与来源核验：`comparison.json`；源码差异：`AxisSynthSystem.diff`。当前未将该候选替换到板上，也未发布 GitHub。
