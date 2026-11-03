# 终版固件 · Final RGB

使用 [final-rgb/synth_hdmi.fs](final-rgb/synth_hdmi.fs)。这是 `build-keyboard-rgb-02` 的原始文件副本，未重新综合或改动位流。

- 芯片：Tang Mega 60K / GW5AT-60B，GW5AT-LV60PG484AC1/I0。
- 主时钟：50 MHz；RGB 已启用，SD/Delay/Reverb 停用。
- UserCode：`0xED65`。
- SHA-256：`d2f4793f8d67c0b1ba3f4a762c002a36f6178b546996eb3120ab6f66a33325c9`。
- 配套 App：`../app/TangSynthStudio.exe`。

在 Gowin Programmer 选择对应器件和实际连接的调试器，用 SRAM Program 加载该 `.fs`。
下载前退出占用串口的 App，下载后等待启动，再连接 App 并按板卡复位后的流程建立新会话。
串口号和 cable-index 与电脑枚举有关，不要照抄其他电脑的编号。

本次实板通过 SRAM 下载验证，未写配置 Flash；断电后需要重新加载。
setup +0.066 ns / hold +0.069 ns，余量较小；重建或改动后必须重新检查时序。

同目录 `UNVERIFIED_synth_fm1.fs` 是历史未通过时序候选，仅保留作溯源，请勿当作终版使用。
