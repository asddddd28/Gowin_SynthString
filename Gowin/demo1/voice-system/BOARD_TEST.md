# FM1 上板与 App 测试记录

当前构建：`reports/gowin-shared-operator`，Tang Mega60K，50 MHz，
48.828125 kHz，8 声部 × 6 逻辑算子，4 个双缓冲驻留音色槽。

## 固定输入与恢复

- 旧的可用固件、App 与本次修改前源码：`reports/pre-board-fm1/backup.zip`。
- 最新 16 组 RTL 回归日志及 42 项源码/资源哈希：`reports/board-tested-inputs.json`。
- 本次只安排 SRAM 编程，不写 Flash 或 SD。
- 烧录器以 15 MHz 读取到 GW5AT-60B，ID `0x0001481B`；实际串口 COM7，可打开。

## 已完成验证

- DX/native 算子、包络、FM1 四音色、复音分配、LFO：7 组通过。
- Delay、Reverb、AXI mailbox、Voice/FX 整链与独立整数 oracle：6 组通过。
- 顶层 ADC/UART/PT8211、AXI 主控、紧凑 Delay RAM：3 组通过。
- 最重完整混合场景：940 / 1024 个时钟（Voice866、FX72、接口2拍）；这属于仿真周期预算，并非布线时序证明。
- Rust 库测试 23 项通过，现有 UI 测试 5 项通过；四音色参数命令与 Python 编译器逐字一致。
- 原生 App 窗口已启动并检查中文与布局。之后用户按 Esc 停止界面自动操作。
- 用户补充要求的整页滚动与可见滚动条已构建到 `app/SynthStringVoiceStudio.exe`，用户已确认可以正常滑动。

## 时序修复

1. Voice 8 行查找逐拍扫描，按采样边界中断/重启，保留空闲/最老/重复 Note ID 次序。
2. UART 整包比较分段寄存，随后分类请求，仍然执行完全相同的重放判断。
3. Voice 预解码、身份/参数校验、完成结果选择分级寄存。
4. Voice 与 FX 的 328/336 位比较拆成 16 位片段；宽零值判断拆成 32 位片段。

旧版实际布局失败：DSP118/118、BSRAM112/118、CLS89%，11288条未布通连线，耗时39分50秒。
混响改为两个乘法通道共享，ALU7829→399、LUT4982→1345，结果逐样本相同，增加一个时钟。
板级Delay改为13位地址，8192采样/声道，约167.77ms，保留当前90/120ms效果。
仅共享混响的布局仍有43条未布通连线，DSP114/118、BSRAM94/118、CLS78%。
继续共享振荡算子的两条signed33×signed32乘法通道，底层MULT27X36从15降到4，十时钟延迟不变。
最新综合估算56.305MHz；逻辑27518/59904、寄存器21550/60780、BSRAM75/118、锁存器0。
实际布线数据应以以下最终记录为准。

上述共享算子版曾完成布线：Logic27671、DSP92/118、BSRAM94/118，实际Fmax47.549MHz、最差setup -1.031ns，未通过50MHz，未烧录。
随后在AXI命令FIFO队首增加保持寄存器，将调制拆成描述符/操作数/乘积/累加流水，完整帧减少32拍至940拍。
四项424位命令队列显式使用寄存器，避免综合器把浅宽RAM切分成大量BSRAM；队列仍在运行时握手时才弹出。
流水数值模型10000组、同目标连续累加及全部16组功能回归已通过。旧报告保存在`reports/pre-route-pipeline`。

## 最终硬件结果

2026-11-02 16:06完成最新布局布线和位流生成，但 **50MHz时序失败**：实际Fmax35.944MHz，
最差setup -7.821ns，共1240个setup端点失败；不能把综合估算57.237MHz当作时序通过。
最终物理资源为Logic27189/59904、CLS24379/29952、Register23643/60780、BSRAM98/118、DSP98/118。
当前版本未烧录，未执行新版Rust探针实板测试，也未听音。此前听音确认属于旧固件。
用户随后要求停止调试、先上传GitHub；未降低时钟，未修改20ns约束，未继续修改RTL。

详细分模块资源、执行拍数和长路径见 [RESOURCE_TIMING.md](RESOURCE_TIMING.md)。
最新机器报告为`reports/gowin-board-summary.json`。GitHub位流标记为UNVERIFIED，仅用于保存当前候选。
App滚动已由用户确认；新版协议的实板联调仍待后续满足时序并烧录后执行。

## 范围与门禁

首批音色为 PIANO 2、ORGAN 1、BASS 3、BRASS 2。128 条资源已编目，
其余尚未开放装载。实体键床固定使用槽 1；App/MIDI 可选择槽位。
严格 RTL 规范门禁仍未通过，本次是用户授权的功能实验版本；功能仿真通过不代表规范门禁通过。
修改文件的门禁报告：`../voice-engine/reports/board-engine-gate.json`、
`../voice-engine/reports/board-fx-gate.json`、`reports/board-uart-gate.json`、`../voice-engine/reports/board-reverb-gate.json`、
`../voice-engine/reports/board-endpoint-gate.json`、`../voice-engine/reports/board-modulation-gate.json`。
