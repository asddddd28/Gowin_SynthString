# 当前上板验证入口（2026-11-02）

本轮最新结果见 [BOARD_TEST.md](BOARD_TEST.md)：共享乘法器、命令队首寄存、调制流水，满载940/1024拍；
Tauri/Rust App已构建。具体烧录、硬件遥测及听音状态以该文件为准。
以下内容保留为之前候选的历史记录，不能用其资源、时序或“未烧录”描述替代最新记录。

# FM1增量验证历史（2026-11-02）

以下原有报告是上一候选的历史记录。当前DX扩展的源码哈希、16组RTL回归、主机检查、
综合资源与严格门禁集中在 [fm1-verification.json](reports/fm1-verification.json)，
使用范围见 [FM1.md](../voice-engine/FM1.md)。当前构建只重新运行综合，没有完成新的布局布线，
也没有烧录或板上听音。四个音色的参考WAV来自Python模型。

本轮综合：Logic40,699/59,904（68%），Register21,077/60,780（35%），BSRAM93/118（79%），
Latch0。综合估算Fmax13.564MHz，年龄比较至事件更新的控制路径仍过长；低于50MHz目标。
此数值是综合估计，并非最终布线时序。需要继续拆分控制关键路径后实施。

严格门禁失败项见 [fm1-gate-summary.json](reports/fm1-gate-summary.json)。
采用的 [readable-verilog-generator技能](C:/Users/asddddd28/.agents/skills/readable-verilog-generator/SKILL.md)
要求 “Generated deliverables must pass the formatter-backed gate with zero errors and zero strict warnings.”
本轮未达到该交付条件，保留为候选实现；数值仿真通过不豁免格式、组合深度和完整源码闭包检查。

---

# 整机验证记录

2026-11-02。对应 `SynthSystemTop`、Delay地址宽度14、同步音色参数/算子上下文RAM。完整连接与协议见 [SYSTEM.md](SYSTEM.md)。

## 功能验证

使用 Vivado 2025.1 xvlog/xelab/xsim，本机实际执行，未将静态分析当作仿真结果。

| 对象 | 结果与覆盖 |
|---|---|
| 整机顶层 | PASS；64条启动命令，66个实体键边沿，134条UART响应 |
| ADC到音频 | PASS；15,642次SPI转换，单键/和弦/32键抢音/长按/松键/再按 |
| UART | PASS；CRC、半包超时、重复包缓存、相同序列冲突、乱序、非法命令、保留NoteID |
| 命令仲裁与Master | PASS；96条随机参数命令、24次只读查询，随机AW/W/AR及R/B暂停、结果反压 |
| Master故障 | PASS；watchdog、BRESP/RRESP错误、错误完成tag、复位取消；保持AXI VALID，不误POP |
| AXI Slave | PASS；1,141次写、1,009次读、369个完成比对，队列满/非法访问/独立通道反压 |
| Voice | PASS；8声部48算子、独立状态、抢音/旧释音/延音/重试/提交/清音/复位；400帧整数模型比对 |
| 基础音色 | PASS；5个编译音色、10,240帧参考PCM、三声部和弦 |
| LFO | PASS；1,600帧PCM与38,400个状态快照，8声部48算子、全局/逐声部调制 |
| Delay | PASS；默认32K配置80,000帧模型比对；板级16K配置额外50,000帧，含最大分数延迟、回卷、清空与反压 |
| Reverb | PASS；100,000帧整数模型比对，反馈/阻尼/旁路/尾音/清空 |
| Voice→FX整链 | PASS；6,133帧逐样本整数参考比对；FX独立提交/清尾音/完成重放 |
| 板级容量 | PASS；0x4C=`0x040e1203`，0x50=16383；16,384采样Delay请求返回参数错误8 |
| PCM→PT8211 | PASS；3,436个PCM输出帧、3,437个串行帧，独立解码左右声道并逐样本比对；起始静音不误报underrun |
| 主机诊断代码 | PASS；CRC/噪声字节同步、序列号保存、崩溃后原包恢复；该项使用模拟串口，没有打开真实硬件端口 |

整机仿真将UART位周期、ADC等待和上电等待缩短以加速测试，DSP仍按1024拍一个采样执行。**它不验证真实115200收发时钟误差、ADC模拟建立时间、线路/供电或耳机听感。**

满载 Voice=898拍，FX=71拍，tick→最终PCM=971拍；帧预算1024拍，余量53拍。在仿真内没有引擎超期、PCM溢出、FX入口丢帧或DAC消费underrun。该结论取决于50MHz物理时序成立，不能替代布局布线检查。

## 综合与布局布线

完整板级工程使用 Gowin V1.9.11.03 Education，目标 GW5AT-LV60PG484AC1/I0。

已经发现并修复两类容量问题：

1. 32K/声道Delay的整板映射需要124块BSRAM，超过118；板级改为16K/声道，能力寄存器与参数边界同步调整，库默认仍保留32K。
2. 同步参数表版本仍有262个寄存器无法放置；将多路并行初始化的算子状态改为163-bit单读单写RAM、按有效位初始化，综合寄存器从30,764降至20,395，随后布局通过。

本轮优化后的综合资源为 Logic 35,862/59,904（60%）、Register 20,395/60,780（34%）、BSRAM 90/118（77%）、MULT27X36 59、Latch 0。这是**综合资源**，BSRAM还可能在物理映射时展开，不能替代最终PnR资源。历史失败日志保留在 `reports/build-bits15.log`、`reports/build-async-program.log`、`reports/build-sync-program.log`。

**最终状态：综合、布局完成；布线未完成，50MHz物理时序未验证。** 最后一次构建运行30.17分钟，日志停留在 Routing Phase 0 completed、进程仍在计算，按本轮30分钟观察上限停止，未生成本轮最终时序报告；不把它断言为工具崩溃或设计已布线失败。终止时间与状态保存在 [build-watchdog.json](reports/build-watchdog.json)。`impl/pnr/synth_system.rpt.txt` / `.rpt.html` 仍是08:19的旧失败报告，**不得拿来作为这版上下文RAM优化后的资源或时序结论**。本次没有可声明通过验收的新bitstream。

当前约束只声明系统20ns时钟，外设输入/输出的PCB级时序预算尚未完成；即便内部寄存器时序通过，也不能冒称整个板卡电气时序验收完成。

构建保留一条键盘标定ROM宽度告警（EX2526）：7位十六进制文本被视为28位，而原模块RAM为25位。已检查32个标定字全部小于2^25，最大0x12DF253，被截掉的高3位均为零；未修改旧板门限模块或标定数据来隐藏告警。

综合阶段的最长路径从 `VoiceSynthEngine/mem_age[1]` 到 `VoiceModulation/flag_initialized`，存在串联年龄比较、选择与控制解码。该报告使用综合器默认100MHz估算，给出15.634MHz Fmax，**不是最终50MHz布局布线时序结论**。下一步应将声部分配查找改为多周期控制流程：锁存命令 → 分拍查询身份/空闲/最老声部 → 等待音频帧间边界 → 原子应用事件；音频渲染独立继续。不能用 false-path 或无协议依据的 multicycle 来隐藏这条真实控制路径。

音频计算仅剩53拍余量，所以控制器分拍与音频算子加流水必须分别预算；给48个逻辑算子每次计算都增加2拍会增加96拍，直接超过当前1024拍期限。

## 严格静态门禁

采用 readable-verilog-generator 的严格门禁，完整28文件源闭包：**delivery_ready=false，6,600 errors，40 strict warnings**。这些是工具规则项计数，不代表6,600个独立功能故障，也不能当成无关噪声忽略。

| 公共检查项 | 严格门禁状态 |
|---|---|
| compile | failed；formatter解析8个文件失败；外部xvlog编译实际通过，二者是不同检查 |
| ast | failed |
| readability | failed；格式、过程/组合复杂度等 |
| comment | failed；声明、赋值、实例语义注释不足 |
| naming | failed |
| profile | failed |
| testbench | not_requested（该静态命令未纳入TB）；实际仿真结果见上表 |
| toolchain | not_requested（静态门禁不代跑外部工具）；实际构建结果独立记录 |

完整规则报告保存在本机 `reports/system-gate.json` 和 `.md`；由于JSON约93MB，Git忽略原始报告，提交范围仅保留 [gate-summary.json](reports/gate-summary.json) 与带哈希的 [system-verification.json](reports/system-verification.json)。没有关闭严格模式或放宽阈值。

规范来源：[readable-verilog-generator SKILL.md](C:/Users/asddddd28/.agents/skills/readable-verilog-generator/SKILL.md) 要求 “Generated deliverables must pass the formatter-backed gate with zero errors and zero strict warnings.” 因此当前标为待修复候选实现，不能宣称已经达到最终交付标准。

## 真实硬件与兼容边界

- 本轮没有烧录、未实测耳机声音、未重新测量实体键延迟；旧板上已验证的固件保持原状。
- 新UART协议5已在引脚仿真中通过；旧Tauri/Rust App尚未适配。
- 固定六算子音色描述已执行；通用指令PC、任意模块路径、独立AXI Slave窗和DMA尚未实现。
- 新Voice→FX通路暂未接入旧VCF，也未加入SD装载/USB或BLE-MIDI。

复现命令见 SYSTEM.md。全部仿真日志、源文件/ROM哈希及检查汇总记录在 [system-verification.json](reports/system-verification.json)；旧板导入模块未修改的核验见 [shared-changes.json](reports/shared-changes.json)。
