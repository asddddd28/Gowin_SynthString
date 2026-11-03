# 干声固件与 FM1 音色上板测试

2026-11-02 晚间完成 Tang Mega 60K SRAM 编程及 COM4 调试。用户确认：**“声音正常，已按键”**。
此次没有修改 RTL、启动 ROM 或时钟，也没有写 Flash / SD。

## 音色与容量

| App 编号（从 1 开始） | 音色 | Program ID | 算法 | 默认驻留 |
| --- | --- | --- | --- | --- |
| 005 | PIANO 2 | 4 | 5 | 槽 1 |
| 002 | ORGAN 1 | 1 | 32 | 槽 2 |
| 043 | BASS 3 | 42 | 17 | 槽 3 |
| 069 | BRASS 2 | 68 | 5 | 槽 4 |
| 033 | GUITAR 1 | 32 | 8 | 按需装载 |
| 044 | SYN BASS3 | 43 | 16 | 按需装载 |
| 080 | VOICE 4 | 79 | 5 | 按需装载 |
| 107 | COWBELL | 106 | 6 | 按需装载 |

保留 M-VAVE 原厂 128 个原始 VMEM 条目；当前开放 8 个经过验证的转换音色，4 槽驻留、8 复音。
实体键盘使用第一槽，App / MIDI 可选择其他槽。未适配参数仍拒绝转换，没有静默删除 Pitch EG、DX LFO 或特殊反馈。
这是当前定点硬件子集的适配，不是原 FM1 / DX7 的逐位声音复刻。

## 验证结果

- 新增四音色通过原有、未修改的 RTL testbench：10,240 帧与独立整数模型逐帧一致，147 条命令通过；包含多音高、力度、混合复音、重复包、参数冲突及 native / DX 切换。
- 烧录前核对 43 项当前与冻结输入，位流 SHA256：`c4d5ec761a5008dca715872338e7a60971f72ec435fdc33ad4461db620ed4e15`。
- Gowin 实际芯片 ID `0x0001481B`，编程进度 100%，`Finished.`，耗时 13.72 秒。
- 实板使用与 GUI 相同的 Rust 后台：8 个音色依次装载、单音、八复音和弦、延音、重复输入不发包、六算子参数编辑、持久会话重连全部通过。305 次请求，0 次重试。
- 实测遥测中八复音 Voice 计算为 **877 / 1024 拍（17.54 μs / 20.48 μs）**。这是帧内计算时间，不是按键到模拟音频的端到端延迟。
- 音频欠载、PCM 丢帧、Voice 超时、坏包均为 0。FX 能力及 FX 计数为 0，App 自动禁用 Delay / Reverb，紧急停止不再发送不存在的 FX 命令。
- 用户确认耳机输出正常。此前 45 秒实体键观察窗口没有捕获位图变化，不能据此声称新测得键床事件或扫描延迟；没有采集模拟音频波形。
- Rust 库 24 项通过，原有前端 5 项测试通过，TypeScript 与正式构建通过。严格 RTL 风格门禁的历史问题没有在此次音色任务中修复。

固件仍为 50 MHz、48.828125 kHz / 16-bit 双声道。资源为 CLS 21,597 / 29,952、BSRAM 62 / 118、DSP 58 / 118；布线 Fmax 50.425 MHz，WNS +0.169 ns。余量有限，但本次没有增加硬件资源。

## 使用

独立测试页为 `app/SynthStringVoiceStudio.exe`。选择 **COM4**；当前会话已建立，**不要再次勾选“板卡刚烧录 / 复位”**。只有重新编程或复位 FPGA 后才建立新会话。请选择槽位，再从音色库装载，松键后修改参数并重新起音试听。

重新烧录可运行 `program_dry_verified.py --program --port COM4`，需本机 pyserial。脚本核对固定输入和时序结果后只写 SRAM；端口应按实际设备枚举选择。

完整证据在 `reports/dry-audition/`：`programmed.json`、`program.log`、`patch-qualification.json`、`simulation/xsim-console.log`、`board-probe.log`、`keyboard-monitor.log`、`result.json`。首次调试器未连接的失败记录保留为 `program-no-debugger.log`，不会当作成功烧录。
