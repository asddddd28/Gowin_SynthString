# Gowin_SynthString

Tang Mega 60K（GW5AT-60B）上的纯 FPGA 实时合成器，配套 Tauri / React / Rust 桌面工作台。

**终版：Final RGB · 2026-11-04 · `build-keyboard-rgb-02`。** 保持 50 MHz，完整布局布线通过，已下载 SRAM 并完成串口与数字音频测试。本版启用键盘 RGB，停用 SD 存取和 Delay / Reverb；内存音序录制与回放保留。

## 下载与运行

- **[终版 bitstream：synth_hdmi.fs](Gowin/demo1/voice-system/firmware/final-rgb/synth_hdmi.fs)** · [烧录说明与校验值](Gowin/demo1/voice-system/firmware/README.md)
- **[Windows App：TangSynthStudio.exe](Gowin/demo1/voice-system/app/TangSynthStudio.exe)** · [App 使用说明](Gowin/demo1/voice-system/app/README.md)
- [完整操作指南](Gowin/demo1/voice-system/UNIFIED_STUDIO.md) · [RGB 灯效](Gowin/demo1/voice-system/KEYBOARD_RGB.md) · [发布清单](FINAL_RELEASE.json)

App 需要 WebView2 Runtime。请保留同目录的 `assets` 和 `licenses`，不要只复制 exe。连接板卡调试串口（本机为 COM4，其他电脑按实际端口选择）。板卡重新烧录/复位后建立新会话；普通断线重连继续原会话。

当前实板采用 **SRAM 下载**，UserCode **ED65**，未写配置 Flash；断电后需重新加载。不要误选历史 `UNVERIFIED_synth_fm1.fs`。

## 终版功能

| 部分 | 本版能力 |
|---|---|
| Voice Engine | 8 复音，每声部 6 个逻辑算子；共享物理运算核心，独立相位/包络状态；4 个驻留音色槽 |
| 音源 | FM/PM、线性 FM、AM、Ring、基础波形、共享双帧波表与噪声；六算子路由及包络编辑 |
| 音色 | 基础音色、AM/PM/鼓预设及 FM1 Convert；保留 128 条原始目录，其中 21 条已适配验证，并非完整 FM-1/DX7 复刻 |
| 调制/滤波 | LFO 调制引擎；全局双声道低通及 Cutoff LFO，触摸控制音量/音高/Cutoff |
| 键盘与演奏 | 32 键 ADC 采集、逐键校准、按下/松开阈值、速度力度与灵敏度；App/MIDI 演奏、延音、移调 |
| 触摸与控制 | 双触摸板、四种演奏模式（含四弦吉他）；五旋钮及摇杆 |
| 音序器 | SW1 录制/结束/叠录，SW2 清空，SW4 播放/暂停；四拍循环、可调 BPM、每层保留音色；仅 RAM 存储 |
| RGB | 32 颗灯：单键点亮、涟漪、横/纵扫光、十字扩散、彩虹流水及关闭；App 设备页切换，FPGA 独立运行 |
| HDMI | 1280×720，32 键状态、真实 PCM 波形、频谱、延迟与页面导航；显示器不承载音频 |
| 音频输出 | 底板 3.5 mm / PT8211，**48,828.125 Hz、16-bit、双声道** |

声音从 FPGA 实时产生，没有用预录整段音频替代合成。波表用于周期波形查表。4 个驻留槽由琴键与录音层共享，不能同时为 32 键配置 32 种互不相同的驻留音色。波表上传期间会暂停发声。

SD 保存/加载已停用，HDMI 中保留的 SD 库页面不能用来存取文件。RAM 录音断电丢失。Delay/Reverb 源码保留，但终版没有实例化。旋钮音色参数编辑仍由 App 桥接；本地键盘、触摸、音序、RGB、HDMI 波形/频谱可独立运行。

## 资源与验证

Gowin V1.9.11.03 Education，GW5AT-LV60PG484AC1/I0；来自本次最终 PnR 报告。

| 资源 | 用量 / 总量 | 占比 |
|---|---:|---:|
| Logic | 38,053 / 59,904 | 63.5% |
| CLS | 26,577 / 29,952 | 88.7% |
| FF | 28,097 / 60,780 | 46.2% |
| BSRAM | 107 / 118 | 90.7% |
| DSP | 68.5 / 118 | 58.1% |

- 主时钟约束 50 MHz，报告 Fmax **50.164 MHz**；最差 setup **+0.066 ns**、hold **+0.069 ns**，零违例。余量仍小，修改源码或重建后必须重新检查时序。
- 像素域约束 73.333 MHz，报告 Fmax **88.407 MHz**。
- RGB 215 帧 / 6,880 像素参考比对、4,096 组声像平滑向量、完整 ADC/UART/滤波/PT8211 回归通过；8 声部/48 算子压力测试通过。
- 已上板验证全部灯效模式的硬件读回，单音和八音和弦有有效 PCM，串口重试、音频欠载/超期/丢帧/坏包均为 0；原音色与键盘设置已恢复。
- TypeScript 构建通过，Rust 81 项通过、1 项需专用实板条件的测试未执行。
- 实体 RGB 的肉眼效果尚未记录用户确认；严格 RTL 风格门禁也未全部通过。以上功能/时序结果不等同于全部质量门禁或模拟音质测量。

[时序与资源 JSON](Gowin/demo1/voice-system/reports/final-rgb/timing.json) · [最差路径](Gowin/demo1/voice-system/reports/final-rgb/paths.json) · [仿真与上板摘要](Gowin/demo1/voice-system/reports/final-rgb/verification.json)

## 源码与重建

[硬件顶层](Gowin/demo1/voice-system/hdmi/rtl/SynthHdmiTop.v) · [Voice Engine](Gowin/demo1/voice-engine/rtl/VoiceSynthEngine.v) · [工作台源码](Gowin/demo1/desktop-tauri/) · [共享 Rust 后台](Gowin/demo_test/desktop-tauri/src-tauri/src/voice_engine.rs)

从仓库根目录创建可迁移的终版工程（无需 `reference` 或原电脑绝对路径）：

```powershell
python tools/verify_snapshot.py
python tools/prepare_final_build.py
cd build/final-rgb
& 'C:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' build.tcl
```

该脚本校验发布输入、生成 55 个 RTL 文件的 GPRJ/Tcl、复制最终约束及必要 ROM。输出在 `build/final-rgb/impl/pnr/synth_hdmi.fs`；脚本不会自动烧录。最终 bitstream 的 SHA-256 见发布清单，重新构建不保证产生相同哈希。

App 构建需要 Node.js、Rust MSVC、Visual Studio C++ Build Tools 和 WebView2：

```powershell
cd Gowin/demo_test/desktop-tauri
npm ci
cd ../../demo1/desktop-tauri
npm ci
npm run build
npm run test:backend
npm run desktop:build
```

输出位于 `release-merged/TangSynthStudio/`。共享的 `demo_test/desktop-tauri` 源码目录必须保留；必要的内置资源、许可证和锁文件已随仓库收录。开发脚本、历史 GPRJ/报告仍可能保留原工作区路径，终版请使用上面的可迁移构建入口。

## 历史版本与收录范围

`demo_test` 的硬件综合调试、旧 `keyboard-latency`、Python App 和 `UNVERIFIED_synth_fm1.fs` 均为历史版本；其验证记录只适用于各自的固件。2026-11-02 的未通过时序候选已被本终版取代，不能把历史报告用于当前源码。

按项目约定不上传 `reference`、`material`、大型原始音频库、完整备份、个人会话/配置、依赖安装目录或编译缓存。仅收录源码、必要资源、固件、App 和选定验证证据。[UPLOAD_MANIFEST.json](UPLOAD_MANIFEST.json) 记录文件哈希；第三方代码和厂商 IP 保留原许可证，仓库未另外声明统一许可证。
