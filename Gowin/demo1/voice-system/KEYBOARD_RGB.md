# 键盘 RGB 灯效

2026-11-04：按用户要求暂停 SD 存取，活动工程移除 SD 控制器；保留
内存音序录制、叠录及循环回放。被暂停的 SD 源码保留在磁盘，集成快照位于
`reports/keyboard-rgb/sd-integration-suspended.zip`，没有格式化或改写 SD 卡。

灯效复用 demo_test 已验证模块，通过当前键盘采集结果触发，不重复实例化 ADC。

```
SynthHdmiTop
├─ SynthSystemTop → o_display_keys[31:0]
├─ SynthKeyboardRgb
│  ├─ 上升沿提取 / 校准屏蔽 / 模式寄存器
│  ├─ SynthKeyboardLightEffects（等价移位缩放）
│  └─ LedFrameTx → o_rgb / R19 / CN1.1
└─ 原有 HDMI 显示与音频分析通路
```

App：设备与输出 → HDMI 显示与实体控制 → 键盘 RGB 灯效。
模式为关闭、单键点亮、涟漪、扫光、十字扩散、彩虹流水。
扫光可选左右或上下方向；默认单键点亮。32 颗灯按四行八列排列。
灯效与音频独立运行，50 Hz 刷新，沿用参考程序的 32/255 峰值亮度。
长按不重复触发；单键效果约一秒，重复按下重新计时。
关闭 App 不影响灯效；FPGA 复位后恢复默认模式。

构建：`python hdmi/model/build_hdmi.py build-keyboard-rgb-01`，随后在输出目录运行
Gowin `gw_sh.exe build.tcl`。工程快照固定全部源文件与约束。

本轮证据保存在 `reports/keyboard-rgb/`：
- `rgb-test-opt.log`：新适配模块边沿、校准、配置与脉冲验证。
- `rgb-effects-opt.log`：215 帧 / 6880 像素独立参考模型比对。
- `board/`：烧录前备份、恢复、控制读回与音频实测。

完整时序与板级验证状态以该目录最终报告为准，仿真通过不等同于上板完成。

首轮构建记录：RGB 直接复用版本时序未通过（50 MHz 约束下 45.384 MHz），未烧录。
第二轮将颜色缩放和半径计算移除 DSP，并把 Voice 的增益/声像平滑在调制等待期间分拍。
4096 组平滑参考向量、板级 ADC/UART/滤波/PT8211 与 6133 帧调度回归通过。

## 最终构建与上板记录

`build-keyboard-rgb-02` 已完成 PnR 并烧录 SRAM（UserCode ED65）。
主时钟维持 50 MHz：Fmax 50.164 MHz，WNS +0.066 ns，最差 hold +0.069 ns，
setup/hold 零违例；余量仍偏小，不能据此保证以后增删模块仍然直接通过。
像素域 Fmax 88.407 MHz，对应 73.333 MHz 约束。

| 资源 | 原已验证 SD 诊断版 | 本次 RGB / 无 SD 版 |
|---|---:|---:|
| Logic | 39674 | 38053 |
| CLS | 27191 | 26577 |
| FF | 28668 | 28097 |
| BSRAM | 110 | 107 |
| DSP | 68 | 68.5 |

已恢复原四个音色、32 键映射、2048 点波表、键盘校准、触摸、低通与音量。
原 RAM 录音为空；备份与恢复结果一致。全部灯效模式及两种扫光方向通过
断开重连后的硬件查询验证。流水运行时，单音/八音和弦采集到有效 PCM，
峰值分别为 570/2200，串口零重试、音频欠载/超期/丢帧/坏包均为零。
HDMI 八页命令读回通过。App 已更新并连接 COM4，界面切换彩虹流水成功。
实体灯效位置与视觉效果等待用户确认，不能用串口 ACK 代替实物观察。

本次为 SRAM 临时烧录，断电会丢失；未改写配置 Flash 或 SD 卡。
严格 readable-verilog 交付门禁未通过，风格/规范包/子模块上下文诊断记录在
`reports/keyboard-rgb/readable-gate.*`，与本轮真实仿真、PnR、上板测试分开记录。
完整汇总：`reports/keyboard-rgb/verification.json`。
