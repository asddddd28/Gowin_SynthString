# 六键合入综合测试固件 — 2026-11-02

六颗轻触开关已合入 HardwareLab 与 HardwareHdmi，共用 115200/8N1 UART。
当前下载的是含 HDMI 的综合版，SRAM User Code **0x7180**，器件 ID
0x0001481B，Status 0x76026238。没有写外部 Flash，也没有修改调试器、驱动或 PLL。
下载 Finished 与再次读取 User Code 一致；未做 SRAM 全量回读。

## 功能与接线

- 六键独立两拍同步、5 ms 连续电平去抖；同时按键互不阻塞，长按只计一次。
- SW1..SW6 = AA19、AB18、Y18、N15、U17、P15；高有效、LVCMOS33、弱下拉。
  Gowin 实际 pin 报告确认六路均为输入。TP2 SCL 仍是 AA18。
- B1 相干快照每 100 ms 发送；按下/释放/原始翻转计数继续独立运行，16 bit 回绕。
- 仲裁从五源扩为六源，保持 LF 整行原子性和最多三个优先帧后的普通流服务。
  H1 能力 0x00FF/build 0x0101：`H100FF0101*9B\r\n`。
- 保留键盘校准、FPGA 判键、灯效、小游戏、编码器、摇杆、双 Pad、FPGA 划弦事件。
  六键详情在 App 显示，HDMI 保留既有仪表盘布局，没有新增六键图块。
- App 兼容旧 0x007F 综合版及独立 B1；新综合版总容量 46。按本轮要求保存 effect=0，
  校准文件未改；旧设置备份仅保留本机，不纳入 GitHub。

## 自动验证

- `simulation.log`：实际 ADC/I²C/UART 联合仿真通过。包括 32 键校准原子提交、
  命令重试/错误校验、门限/迟滞、全部灯效选择、钢琴块及游戏启动/停止。
  新增六键同时短按，后续 B1 的按下/释放计数均为 `[1,1,1,1,1,1]`。
- `mux_sim.log`：六路饱和输入，96 帧，整行不交错、优先流限额、全部源均前进。
- `../../../hardware_hdmi/sim/run-buttons.log`：HDMI 忽略 B1/new H1 后，
  原有数据解析、溢出恢复、空白、1280×720 有效像素和 HS/VS 时序通过。
- Rust 28 项测试全部通过（18 unit、3 六键、5 旧版兼容、2 新综合混合流）；
  新混合测试使用真实 RTL UART 输出 50,283 bytes，覆盖任意分片、九种报文、
  新身份声明前后 B1 到达顺序、46 路模型更新。TypeScript/Vite/Tauri 打包通过。
- `timing_lab.json`：50 MHz 约束，fMax 50.301 MHz，无报告时序违例，Logic 13,892。
- `timing_hdmi.json`：50 MHz 域 fMax 57.368 MHz；73.333 MHz 像素域 fMax 73.524 MHz；
  无报告时序违例，Logic 16,518（28%），Register 10,816，BSRAM 11。
  保留 Gowin 通用时钟布线警告 PR1014，不能称“无警告”。像素域余量有限，不提高时钟。
- 严格风格门禁 **未通过**（仓库保存 `readable-summary.json` 失败摘要）：2,070 errors、20 strict warnings，
  包括既有紧凑 RTL 的 AST/命名/注释/布局问题。功能仿真与 Gowin 编译成功不能替代
  此门禁；本轮不声称完成严格风格认证。新增模块规范及概念 WaveDrom 在 `spec/src`。

## 实板证据与边界

- 合并前 `switches_after_repair.json` 已记录六键按下/释放各
  `[8,17,24,32,28,15]`，SW1/SW4 也已有动作，CRC 错误 0。
- 新位流下载后 `live_uart.bin` 连续 8 秒，共 74,137 bytes；同一 Rust App 服务回放：
  counts `[2560,80,79,400,160,160,160,32,80]`
  （key/status/game/encoder/joystick/touch/guitar/identity/buttons），
  CRC/格式错误 0、序号错误 0；只读捕获与回放均 TX=0。见 `live_replay.json`。
- 更新后 App 已连接 COM4，H1=0x00FF/0x0101；自动恢复 32 键校准，35/35 ACK、失败 0，
  FPGA configured=true/mode=0。六键 B1 约 10 Hz，复位后松开态与计数均 0。
- 此时两块触摸板都报告 error=1（地址探测未应答）、采样序号 0，App 正确显示
  **44/46** 而非伪报全在线。已经询问实际连接/供电情况；尚未据此认定芯片损坏或软件回归。
  两块 Pad、划弦实物动作本轮未通过验收。原 I²C 引脚/扫描 RTL 未改，联合行为仿真通过。
- 随后同轮实板观察（App 会话约 198.7 s）：六颗开关的按下／释放计数均为 `[1,1,1,1,1,1]`，
  原始翻转 `[2,2,12,2,4,2]`，CRC/序号错误 0。这是用户操作后的真实输入，没有软件注入。
  新 HDMI 画面的实际显示仍需屏幕观察，不能由 UART/JTAG 推断。旧 HDMI 画面此前已由用户确认。

## 文件与回退

- HDMI 位流 SHA-256：`5545f79fc81c29b7aa9764f03e245f5db66f7cdcbb3e333f7bee9f7595a2dee5`
- 无 HDMI 位流 SHA-256：`574e8a836868e195f7a8db6536bbae108238fac9d1aa986b946ed0f22c7b3bba`
- `preflight.json`：项目、RTL、约束、依赖和位流哈希；下载前再次核对。
- `program_sram.log`、`codes_before.log`、`codes_after.log`：真实器件操作。
- `../../baseline/buttons_merge_20261102`：合并前总测试源文件、位流、App。
  原独立六键 `tactile_buttons` 源码/位流没有修改。

## GitHub 导出边界

本目录 switches_after_repair.json 和 live_replay.json 为历史诊断的精简导出，仅保留计数、协议、板卡及传输摘要，不包含个人校准、设置或主机设备信息。before_calibration.json、before_settings.json、持续更新的 app-live.json 和本机 baseline 未上传。完整风格日志体积较大，仅上传 readable-summary.json，失败结论未改变。GitHub 上传阶段未重新烧录或操作 App 窗口。
