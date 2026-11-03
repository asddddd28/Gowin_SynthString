# Tang Synth Studio · 统一工作台

> 当前终版为 Final RGB（2026-11-04）：50 MHz、键盘 RGB、RAM 音序；SD 存取及 Delay/Reverb 停用。已构建 App 位于 `../voice-system/app/TangSynthStudio.exe`，固件与验证入口见 [Voice System README](../voice-system/README.md)。

Tauri 2 + React/TypeScript + 原生 Rust，面向 Tang Mega 60K。运行 `release-merged/TangSynthStudio/TangSynthStudio.exe`；便携包保留 `assets` 与 `licenses`。完整操作和验证边界见 [UNIFIED_STUDIO.md](UNIFIED_STUDIO.md)。

## 使用

1. 连接 FTDI 调试串口，默认进入“状态显示”：32 键、真实 PCM 波形/频谱、数字输出延迟与链路诊断。
2. 点击键名进入声音设计，通过旋钮/滑杆编辑振荡器与包络；六算子按钮打开完整参数弹窗。
3. “选择预设音色”打开基础库或 FM1 Convert。载入经过硬件确认后返回编辑，实体键与 App 使用同一份逐键映射。
4. 演奏控制集中在状态页，提供电脑键盘、MIDI、延音、移调、力度和音量。切页/失焦释放 App 持音。
5. HDMI固件连接后，“设备与输出”提供八页切换、当前槽草稿应用/取消及五旋钮输入诊断。实体从左到右E5→E1；E1切槽不会丢失其他槽草稿，摇杆上下选择算子、按下应用当前槽。旋钮参数编辑目前需要App保持连接，离线画面与音频分析仍由FPGA独立运行。

硬件支持同时使用 4 种不同音色、8 复音；FM1 目录 128 条，目前 21 条通过适配验证。波表为全局共享双帧，上传时停音并支持继续。频谱是串口分块读取的硬件快照，不是连续音频流。旧版工程切换与驻留音色栏已移除，旧配置文件保留。

## 构建与验证

首次构建须分别在 `../../demo_test/desktop-tauri` 和本目录运行 `npm ci`，共享前端源码也需要就近解析 React/TypeScript 依赖。

- `npm run desktop:build`：准备资源及许可证，以 Tauri 正式模式构建到 `release-merged/TangSynthStudio`。
- `npm run build`：TypeScript 检查与前端构建。
- `npm run test:backend`：Rust 库回归。
- `npm test -- tests/unified-studio.spec.ts`：统一工作台回归，资源和音色编译使用真实 Rust，板卡接口使用显式模拟。

未启用 `tauri/custom-protocol` 的普通 `cargo build --release` 不能用作桌面发布，否则会访问开发服务器。独立串口实板证据、RTL 仿真和 Gowin 实现在 `../voice-system/reports/unified-studio/`；旧 UI 的历史测试不代表新版导航。

协议会话与已确认按键配置保存在 `%LOCALAPPDATA%/SynthString/voice-engine/`。普通重连沿用会话，板卡复位/重新烧录后才建立新会话。旧素材与 Surge 配置仍在 `%LOCALAPPDATA%/TangSynth32/settings-tauri.json`。
