# Gowin_SynthString

Tang Mega 60K（GW5AT-60B）合成器与综合硬件调试工程。2026-11-02新增FM1四音色Voice Engine及Tauri/Rust Voice Studio快照；保留此前已测试的音频合成器、综合硬件调试、Python App和pair固件。

**最新Voice Engine候选尚未烧录，50MHz时序未通过。** 16组RTL仿真通过，8声部×6算子加LFO/FX最重940/1024拍；实际布局Fmax35.944MHz，setup -7.821ns。按用户要求暂停进一步调试并先保存快照，未降低50MHz时钟。当前候选不能替代下面已验证的演奏固件。

- [各模块资源、执行拍数与长路径报告](Gowin/demo1/voice-system/RESOURCE_TIMING.md)
- [完整结构与协议](Gowin/demo1/voice-system/SYSTEM.md) · [当前验证状态](Gowin/demo1/voice-system/BOARD_TEST.md)
- [SynthStringVoiceStudio.exe](Gowin/demo1/voice-system/app/SynthStringVoiceStudio.exe) · [使用方法](Gowin/demo1/voice-system/app/README.md)
- [未通过时序的候选位流](Gowin/demo1/voice-system/firmware/README.md)，文件名明确带有UNVERIFIED。

新版App包含可滚动界面、四槽音色、六算子电平/频率/DX包络编辑、电脑键盘/MIDI/鼠标演奏、旋钮、延音、共享FX及硬件遥测。滚动已由用户确认；新版协议实板联调尚未执行。库保留128条原厂数据，只开放PIANO 2、ORGAN 1、BASS 3、BRASS 2四个已验证参数配置。

## 运行入口与固件配对

| 用途 | Windows App | FPGA 固件 / 工程 |
|---|---|---|
| 键盘、六键开关、RGB、游戏、编码器、摇杆、双触摸板、触摸吉他 | [TangHardwareLab.exe](Gowin/demo_test/desktop-tauri/release/TangHardwareLab.exe) | [hardware_lab.fs](Gowin/demo_test/diagnostics/hardware_lab/impl/pnr/hardware_lab.fs) |
| 上述综合调试 + HDMI 信息面板 | 同上 | [hardware_hdmi.fs](Gowin/demo_test/diagnostics/hardware_hdmi/impl/pnr/hardware_hdmi.fs) · [说明](Gowin/demo_test/diagnostics/hardware_hdmi/README.md) |
| 六颗轻触开关独立测试 | 同上 | [tactile_buttons.fs](Gowin/demo_test/diagnostics/tactile_buttons/impl/pnr/tactile_buttons.fs) · [说明](Gowin/demo_test/diagnostics/tactile_buttons/README.md) |
| 32 声部 AXIS 合成器、音色编辑、起音延迟监测、板载 DAC/喇叭 | [TangSynthStudio.exe](Gowin/demo1/keyboard-timbres/app/TangSynthStudio.exe) | [keyboard_latency.fs](Gowin/demo1/keyboard-latency/impl/pnr/keyboard_latency.fs) · [说明](Gowin/demo1/keyboard-latency/README.md) |

以上是独立固件，不会同时运行。综合调试 App 的吉他通过电脑原生音频发声；板载喇叭测试使用 AXIS 合成器固件。HDMI 面板当前显示 K01 ADC 曲线，不是音频 FFT，也没有 HDMI 音频。

Windows App 需要 WebView2 Runtime。当前实板 DEBUG 串口为 COM4（FTDI B）；其他电脑请按实际枚举选择。App 与测试脚本需要轮流使用串口。优先进行 SRAM 下载；本次 HDMI / 喇叭测试没有写外部 Flash。

## 源码与工程

- [Rust + Tauri / React App](Gowin/demo_test/desktop-tauri/README.md)：综合硬件界面以及共享目录中的 Synth Studio 模块，含 Cargo/npm 锁文件、图标、测试和协议样本。
- [综合硬件 RTL](Gowin/demo_test/diagnostics/hardware_lab/README.md)：键盘扫描、校准阈值、响应灯效、FPGA 游戏、六键、编码器、摇杆和双触摸板。六键独立 5 ms 去抖、10 Hz B1 快照，支持同时按键和按下／松开计数；新 H1 为能力 0x00FF / build 0x0101。App 仍兼容旧综合版和独立六键固件。
- [HDMI 工程](Gowin/demo_test/diagnostics/hardware_hdmi/)：无软核，1280×720 视频，显示输入值、按键/触摸高亮及状态；含 GPRJ、CST、SDC、布局 ROM、仿真及厂商 DVI/PLL 文件。
- [合成器 RTL](Gowin/demo1/rtl/) 与 [keyboard-latency](Gowin/demo1/keyboard-latency/)：32 声部双振荡器/双包络/SVF，保留 keyboard-performance、keyboard-studio、keyboard-parallel 源码依赖和初始化数据。
- [五类基础音色](Gowin/demo1/keyboard-timbres/README.md)：16 个基础音色与 32 键示范库。
- [2 针喇叭测试](Gowin/demo_test/diagnostics/speaker_test/README.md)：短音脚本、下载记录和串口原始数据。J27 / J28 为左右桥接喇叭输出。

旧版 [demo1 App](Gowin/demo1/desktop-tauri/README.md)、[Python Keyboard Lab](Gowin/demo_test/desktop/README.md) 和 `demo1_pair_31002/31004.fs` 保留为历史版本，不是上表的新 App / 固件组合。历史发布包见 [Releases](https://github.com/asddddd28/Gowin_SynthString/releases)；这次新程序直接放在表中的仓库路径。

## 验证记录

| 固件 | User Code | SHA-256 |
|---|---|---|
| HDMI 综合调试 + 六键 | `7180` | `5545f79fc81c29b7aa9764f03e245f5db66f7cdcbb3e333f7bee9f7595a2dee5` |
| 普通综合调试 + 六键 | 本轮未下载此变体 | `574e8a836868e195f7a8db6536bbae108238fac9d1aa986b946ed0f22c7b3bba` |
| 六键独立测试 | `5CC2` | `f59c66ac3652b2298f4e3d7ce3c962d3a46f5783cf76e29634b8b7283815d6ce` |
| AXIS 音频 / 延迟监督 | `FED2` | `3a75079156d8297e54b693b39644fd1981deadba368cbdc0e5d5e6e1047d02ec` |

六键合并版通过联合 RTL 仿真、六源串口仲裁、HDMI 解析／光栅仿真、Gowin 时序检查及 28 项 Rust 测试。HDMI 版已实际下载 SRAM，收到 35/35 校准确认，六颗开关均出现按下与释放，串口校验／序号错误为 0。本轮 RGB 关闭。两块触摸板当时未应答，App 显示 44/46；不能将此记录当作双 Pad／划弦验收。详见 [本轮验证](Gowin/demo_test/diagnostics/hardware_lab/reports/buttons_merge/validation.md)。

HDMI 保持原仪表盘布局，六键详情在 App 页面显示。上一版 89B5 曾完成实屏确认：画面正常，数据与高亮跟随输入变化，详见 [历史验证](Gowin/demo_test/diagnostics/hardware_hdmi/reports/validation.md)；不能将旧版实屏观察当作新位流的再次确认。

音频固件通过 50 MHz 时序检查（余量很小）和数字链路验收。4 Ω / 3 W 喇叭在 3/8 主音量测试中，用户反馈有声音但较小；6/8 测试记录到非零 PCM，未单独确认听感。没有测量实际声压、输出功率或两个物理声道。测试结束静音，详见 [喇叭记录](Gowin/demo_test/diagnostics/speaker_test/README.md)。

上述是此前独立固件的实测记录；本次Voice Engine快照重新进行了综合和布局布线，但未通过时序、未烧录。严格RTL风格审查仍有未通过项，不能将功能仿真理解为全部门禁通过。

## 构建与快照边界

App 可在 `Gowin/demo_test/desktop-tauri` 执行 `npm ci`、`npm test`、`npm run test:ui` 和 `./build.ps1`。前置依赖为 Node.js、Rust MSVC、Visual Studio C++ Build Tools 和 WebView2。旧Synth Studio入口是Cargo二进制`synth-debug`；新Voice Studio执行`./build-voice-studio.ps1`，二进制入口`synthstring-voice-studio`，共用前端及Rust模块。新DSP测试向量由`voice-engine/model`生成，未上传大型生成向量及构建缓存。

本次补齐新增工程及直接依赖的 GPRJ / CST / SDC 文件。为保留已验证源文件的 SHA-256，源码、生成脚本和报告中的原工作区路径 `D:/Projects/ai` 未自动改写。换目录重建时需调整 GPRJ/Tcl、ROM 路径及仿真文件列表，并重新生成验证结果；历史报告不能直接作为修改后源码的通过证明。HDMI 的厂商文件和 `layout.hex` 已随附，普通重建不必重新运行依赖外部 reference 目录的 `prepare_assets.py`；历史迁移/生成脚本也不应无差别执行。

不追加 `reference` / `material`、原始 88 键 WAV 库、完整备份、个人 App 配置／校准、安装依赖、编译缓存、崩溃转储和重复发布包。保留必要 ROM、示范音色、许可证、测试样本、选定的仿真/时序/实板证据和当前可执行程序。本轮 App 诊断 JSON 仅导出计数／协议摘要，详细严格风格报告导出失败摘要，原始 profile/settings 不随报告上传。旧说明中的部分 baseline、大型报告或历史发布包未纳入仓库。

[UPLOAD_MANIFEST.json](UPLOAD_MANIFEST.json) 记录所收录工程文件的路径、大小和 SHA-256；运行 `python tools/verify_snapshot.py` 可只读核对文件及新增工程的直接依赖。原工作目录未移动或改写。第三方代码保留各自许可证，厂商加密 IP 保留原始标记；未另行给整个项目指定统一许可证。
