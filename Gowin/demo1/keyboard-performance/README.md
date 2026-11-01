# 键盘合成与响度调试

本工程保留 `../keyboard-axis` 的可听 D3BE 固件及原始合成核心，使用独立的顶层、调度观察、输出混音和响度模块。App 是已有 Tauri/Rust 工程中的独立入口，不改变 HardwareLab 的串口协议。当前为基础正弦音色测试，AM 旁路、FM 深度为零，SVF 低通和 ADSR/VCA 工作；不代表所有 Surge 算法或完整音色迁移。

## 演奏与 App

打开 `app/TangSynthDebug.exe`，选择 COM4 并连接。声音从底板 3.5 mm 耳机接口输出。实体键独立运行，不需要 App 合成声音；App 只负责观察、短试音和主音量控制。勿同时让其他程序连接 COM4。

- 32 键对应 MIDI 48–79，实时显示物理按键状态。
- 主音量 0–100%，当前为 9 档；下发后读取固件回报确认。
- C4 按钮发送一秒测试音，结束试音按钮只结束串口试音，实体键保持有效。
- 包络活动声部数包括松键后的释音；波形、AM、包络峰值和阶段位图为开机以来累计观察，输入/输出采样峰值为衰减保持。
- 日志模式：`TangSynthDebug.exe --capture D:/Projects/ai/Gowin/demo1/keyboard-performance/reports/app_live.jsonl`。

## 数据通路与响度

`KeyboardSampler → KeyboardThresholds → KeyboardVoiceBridge → KeyboardSynthEngine（相位/波形/ADSR/AM/SVF/VCA）→ KeyboardFrameMixer → KeyboardLoudness → I2sTx → PT8211`

32 声部混音先固定除以 32，保留已有数值约定。在这个基础上应用 `4 / sqrt(max(N, 1)) × volume/8` 增益，N 为包络尚未空闲的声部数。这个方法近似补偿不同音高非相关声部的总能量，不能保证同频同相的峰值相同，也不是 LUFS 或跨音色感知响度归一化。

增益在每个音频帧平滑变化：降低约 1.3 ms 时间常数，回升约 84 ms，避免按键数变化直接造成增益跳变；释音参与 N，松键时不会立即按剩余按键数放大。主音量零逐步到达精确静音。最后采用对称舍入和 ±0x700000（约 −1.16 dBFS）保护限幅，并记录限幅次数。该保护不是前视限制器；超过阈值时会截断波形，不能据此宣称无失真。

计算时钟 50 MHz，音频每 1024 拍一帧（48,828.125 Hz）。七阶段核心报告 448 拍；混音流水相对旧版增加 3 拍，响度再增加 4 拍，共约 140 ns，仍在下一音频帧串行输出的截止时间内。原来的每帧缓冲策略不变。

## 验证与构建

- `reports/loudness_xsim.log`：55,500 个独立 Python 整数参考结果，包括最负数、满量程、归一化、音量切换、平滑、精确静音、限幅及在途复位。
- `reports/mixer_xsim.log`：与原混音器逐帧数值等价，256 帧/8192 个输入，包含正负满量程、随机样本、输入停顿和输出反压。
- `reports/simulation.json`：真实 ADC SPI 输入至 PT8211 输出的闭环；三键及32键、包络释音、阶段观测、64字节遥测校验、串行左右声道逐位比较。
- `reports/first_implementation`：第一轮实现未通过50MHz时序，最差−0.974ns，未烧录。随后对混音和观察路径分拍；最终报告以 `reports/build.log`、`impl/pnr` 和实板记录为准。
- 严格源码门禁仍有历史和新增命名/格式/AST/注释等失败，见 `reports/readability.*`。外部 xsim/Gowin 证据不等于严格源码门禁通过，本工程仍是诊断验证版本。

常规复建使用当前源码：

```powershell
$env:PYTHONUTF8='1'
..\desktop\.venv\Scripts\python.exe run_sim.py
& 'C:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' build.tcl
```

`prepare.py` 用于从旧工程重新生成包装层及 ROM，并应用混音流水修改；正常构建无需重复生成。`write_specs.py` 输出接口合同和时序图。测试台含任务形参，技能的 `--source` 接口检查将其误识别为顶层端口，因此测试台合同按显式接口生成；设计模块仍做源接口核对。

App 源码在 `../../demo_test/desktop-tauri`：`npm run build` 后执行 `cargo build --locked --release --features custom-protocol --manifest-path src-tauri/Cargo.toml --bin synth-debug`，复制输出 EXE 即可独立运行。`custom-protocol` 必须启用以嵌入离线界面。原 HardwareLab 入口保留。

## 调试协议

115200/8N1，64字节：头 `A5 5A 02 40`；4帧计数、8物理键位、12已提交键位、16非零PCM计数、20事件数（均u32）；24计算周期u16、26标志、27最近键号、28原始ADC u16；30音量、31包络活动声部数；32增益Q16、36输入峰值、40输出峰值、44限幅计数、48包络峰值、52波形峰值、56AM峰值（均u32）；60七阶段累计位图、61音量副本、62前62字节XOR、63为0D。多字节小端。

命令 `T` 一秒C4、`P` 结束试音、ASCII `0`–`8` 设置主音量。协议为本地板级调试，不与 HardwareLab 的配置帧混用。App 也能只读旧32字节状态，但旧固件没有新版电平和音量功能。
