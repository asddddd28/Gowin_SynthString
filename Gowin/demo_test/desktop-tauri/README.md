# Tang Hardware Lab — Rust + Tauri

Windows 原生硬件调试 App。Rust 负责串口、协议、校准事务、状态模型和音频；React + TypeScript 负责八个可视化页面。运行不需要 Python，也不需要启动网页服务器。

## 运行

双击 `release/TangHardwareLab.exe`。选择 DEBUG 串口（这块板为 COM4，FTDI B）并连接。Windows 需要 WebView2 Runtime；本机已安装。

```powershell
./release/TangHardwareLab.exe --port COM4
./release/TangHardwareLab.exe --replay ../diagnostics/hardware_lab/reports/live_serial.bin
./release/TangHardwareLab.exe --diagnostics ./reports/app-live.json
```

首选匹配固件：`../diagnostics/hardware_lab/impl/pnr/hardware_lab.fs`，H1 / 0x007F / build 0x0100。兼容旧独立键盘、编码器、摇杆、触摸板及 FPGA 吉他遥测。收到未知协议时显示明确提示，禁止下发硬件配置；App 不会自行重新烧录或重启 USB 调试器。

页面包括：

- 硬件总览：40 路更新状态、帧率、校验计数、输入缩略图及会话日志。
- 键盘与灯效：4×8 原始值和深度、单键曲线、全键/单键校准、迟滞阈值、关闭/四种响应灯效/连续流水。
- 编码器：从左到右 E5–E1，四边沿一格，原始/滤波 A/B、P/N/X、会话归零、回绕和断线计数。
- 六键开关：SW1–SW6 实物造型，原始/去抖电平、按下/松开/原始翻转次数。配套 `../diagnostics/tactile_buttons/impl/pnr/tactile_buttons.fs` 为独立六键固件，50 Hz B1 遥测、FPGA 5 ms 去抖；RGB 数据保持低，其他外围扫描暂停。连接后自动显示此页，超过 0.6 秒未更新取消高亮。SW2 按实际原理图使用 AB18，修正表格误写的 AA18。
- 摇杆：实体杆造型、九向和按压、原始/去抖位图、方向映射。
- 双 Pad：左右拼接、43.596×61.976 mm 单板有效区域比例、90.832 mm 总跨度、触点及12电极响应。
- 吉他：每板三根竖弦，E2/A2/D3/G3/B3/E4，FPGA G1 事件直接驱动原生音频。
- 小游戏：FPGA 贪吃蛇、打地鼠、钢琴块的启动/结束、画面、倒计时与得分；无 PC 游戏逻辑。

右上“会话工具”提供原始串口 `.bin` 录制、回放和诊断 JSON 导出。回放是历史数据，按字节速率播放，不能复原精确动作时序；禁止向硬件发送命令，也不发声。

## 配置迁移

首次读取 `%LOCALAPPDATA%/TangKeyboardLab` 的 `calibration.json`、`effects.json`、`joystick_mapping.json` 和 `touchpad_mapping.json`。后续保存至 `%LOCALAPPDATA%/TangHardwareLab`，旧版文件保留。配置采用临时文件同步写入后替换。

连接后先清空两秒 USB 桥缓存。确认有效板卡状态后，自动下发完整校准及灯效，每条命令必须收到匹配序号、CRC 正确的 ACK。超时重试两次，序号冲突重新分配；任一步失败不发送 COMMIT。正在运行的 FPGA 游戏会保留，不自动重新校准打断。

综合固件约10次/秒/键的遥测下，松开校准采集4秒，至少30个样本，检查5%–95%噪声范围；按下端点用7样本中位数拒绝尖峰。候选数据不覆盖原配置，直到完整采集并应用。端点支持增/减两个方向，Rust 使用 ties-to-even 舍入，与旧版 Python 下发字节一致。

## 音频和时效

串口线程直接接收 FPGA G1 事件；跨弦判断仍由 FPGA 完成。Rust 只映射轴/方向/左右板/弦号，拒绝重复和超过150 ms的积压事件。原生 CPAL/WASAPI 回调播放预计算拨弦音色，最多24复音，快速多弦事件按方向相隔1.5 ms播放。支持设备默认采样率及256帧缓冲（设备不支持时退回默认缓冲）。前端轮询快照约25 Hz，不参与发声路径。

音频仅在吉他页、实时连接、有效 Pad 数据及启用开关同时满足时开启。离开吉他页、断线和回放会止音；Panic 使旧队列失效。所有输入超过0.6秒未更新均取消活动显示。

## 构建与检查

```powershell
npm ci
npm test
npm run tauri -- dev
./build.ps1
```

依赖固定于 `package-lock.json` 和 `src-tauri/Cargo.lock`。`build.ps1` 输出单文件可执行程序至 `release`。开发前置条件为 Rust MSVC、Visual Studio C++ Build Tools、Node.js 和 WebView2，见 [Tauri 官方说明](https://v2.tauri.app/start/prerequisites/)。串口和原生输出分别使用 [serialport](https://docs.rs/serialport/latest/serialport/struct.SerialPortBuilder.html) 与 [CPAL](https://docs.rs/cpal/0.16.0/cpal/)。

`src-tauri/tests/fixtures` 含旧综合固件真实记录及旧 Python 生成的期望值。测试覆盖不同分片尺寸、所有八类帧、CRC/范围错误恢复、校准逐字节兼容、稳定性/尖峰/中断、ACK/重试/冲突、编码器回绕、吉他事件方向/重复/过期、复音与止音。`hardware-probe` 直接复用 App 的 Rust Service 验证真实回放或实板连接，详情见 `reports`。

## 目录

`src/pages/`：八个页面。`src/components.tsx`：键盘、旋钮、摇杆、触摸板、曲线等共享显示。`src-tauri/src/protocol.rs`：纯字节协议；`link.rs`：确认事务；`calibration.rs`：校准及持久化；`model.rs`：状态、映射、时效；`runtime.rs`：串口、录制、回放及命令门控；`audio.rs`：原生音频；`lib.rs`：有限的 Tauri IPC 接口。

`scripts/golden.py` 仅用于从旧版生成测试基准，`scripts/icon.py` 仅用于生成应用图标；发布程序不调用它们。`scripts/split_ui.py` 是初版拆分记录，不要对已经拆分的目录重复执行。

2026-11-02: six-switch B1 telemetry now coexists with all comprehensive firmware streams. Accept H1 0x00FF/build 0x0101 as well as the existing 0x007F/build 0x0100; show 46 channels for the new hub and six for standalone. The hardware_buttons_uart.bin fixture is real mixed RTL UART output.
