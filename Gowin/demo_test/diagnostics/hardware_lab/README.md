# HardwareLab 综合调试

GW5AT-60B，50 MHz，COM4 / 115200 / 8N1。SRAM 位流为 `impl/pnr/hardware_lab.fs`，User Code `34A0`。配套 App 为 `../../desktop/release_hardware_lab/TangKeyboardLab/TangKeyboardLab.exe`。不写外部 Flash，断电后需重新下载。

整合32键 ADC、原校准与 FPGA 阈值判键、四种响应灯效、连续彩色流水、三款 FPGA 小游戏、五编码器、摇杆、左右双 MPR121、FPGA 六弦事件。全部并行运行；吉他由电脑播放，游戏和灯效在板上运行。既有校准/方向文件沿用。

键盘采样与上报解耦，ADC完整扫描约6.7ms，上报10轮/秒；新快照只在32键扫描边界生成。双Pad仍100kHz I²C，实板约213Hz采集，原始显示各10Hz。编码器各10Hz、摇杆20Hz上报。115200串口按整行仲裁：真实划弦与ACK优先，最多连续3个优先帧后服务普通状态，两个类别独立轮询。静止数据预算8400字节/秒，剩余带宽供划弦突发使用。两个Pad各自16项事件队列，溢出在G1帧中可见。

App收到有效H1能力声明后启用综合模式与总览，各页同时更新。综合记录为完整混合 `.bin`，历史回放不发送命令、不播放声音。连续彩色流水使用mode6，mode5保留小游戏；旧单功能固件不接受新灯效。吉他页启用声音，切走页面自动止音。

验证证据：

- `reports/live_validation.json`：16.17秒实板混合数据，全部帧/序号错误为0，48条命令确认成功，最大确认往返32ms；已恢复保存校准与mode4灯效。没有伪造外部传感器输入。
- `reports/simulation_uart.json` 与 `sim/simulation.log`：真实引脚级ADC/I²C/UART联合仿真；32键校准、重试、门限、钢琴块，以及其他外设同时运行。
- `sim/mux_sim.log`：五路饱和输入下整行原子性和公平性。
- `sim/flow_sim.log`：连续彩色流水命令、四行一致、运动/变色、保留mode5校验。
- `../../desktop/build_hardware_lab.log`：68项软件测试通过及打包记录。
- `reports/readability.json`：严格可读性工具仍未通过（解析/命名/注释等1789错误、15严格警告）；不得表述为严格风格验收通过。Gowin与xsim真实编译通过，50MHz布线时序无违例，fMax50.968MHz，12929逻辑单元。

复建：从本目录执行 Gowin `gw_sh.exe build.tcl`；App在desktop目录执行 `build.ps1 -Destination release_hardware_lab`。`prepare_sources.py`记录从旧单功能工程提取综合副本的过程，重新运行会覆盖本目录生成副本；日常构建不需要运行它。原工程与原位流未修改。详细接口及概念时序在 `spec/src`，文件哈希在 `reports/manifest.json`。
