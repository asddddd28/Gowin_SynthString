# SynthString Voice System

独立板级候选工程，连接实体键盘、UART命令、AXI主从控制、Voice/LFO/Delay/Reverb与PT8211输出。旧 `keyboard-latency` 工程未替换。

- [完整 hierarchy、容量、数据/参数/控制通路及主机协议](SYSTEM.md)
- [实际仿真、综合/布局布线、严格门禁与上板边界](VERIFICATION.md)
- [顶层 RTL](rtl/SynthSystemTop.v)
- [Gowin 工程](synth_system.gprj)
- [诊断客户端](host/control.py)
- [FM1首批四音色、库管理和使用命令](../voice-engine/FM1.md)

最新候选增加DX对数包络和音高/力度缩放，启动装入PIANO 2、ORGAN 1、BASS 3、BRASS 2。
保留128条原厂数据，4槽驻留、8复音；ABI0x00010005。16组RTL仿真及主机模型检查通过，
最新共享乘法器与调制流水版满载仿真为940/1024拍，板级Delay为每声道8K采样，约167.77ms。
本轮App、资源优化、最终时序与上板结果统一记录在 [BOARD_TEST.md](BOARD_TEST.md)。
新版 [SynthStringVoiceStudio.exe](app/SynthStringVoiceStudio.exe) 使用Tauri/Rust，支持四音色、六算子编辑、演奏、FX与遥测，整页滚动已获用户确认。
严格交付门禁尚未通过；历史 `reports/fm1-verification.json` 不代表本轮最终布线或烧录状态。
