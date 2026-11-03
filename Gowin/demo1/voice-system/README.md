# SynthString Voice System · Final RGB

**终版：2026-11-04，`build-keyboard-rgb-02`，UserCode `ED65`。**
50 MHz 时序通过，已 SRAM 烧录并完成串口与数字音频测试；SD 存取和 Delay/Reverb 停用。

## 运行入口

- 发布固件：`firmware/final-rgb/synth_hdmi.fs`，见 [烧录说明](firmware/README.md)。
- [TangSynthStudio.exe](app/TangSynthStudio.exe) 与同目录 `assets`、`licenses` 配套使用。
- [操作指南](UNIFIED_STUDIO.md) · [App 说明](app/README.md) · [RGB 与本轮验证](KEYBOARD_RGB.md)。
- 本地原始 bitstream：`reports/synthui-hdmi/build-keyboard-rgb-02/impl/pnr/synth_hdmi.fs`，与发布固件逐字节一致。

## 功能与边界

8 复音，每声部 6 个逻辑算子，共享物理运算核心；4 个驻留音色槽。
支持 FM/PM、线性 FM、AM、Ring、共享双帧波表、噪声与独立包络；LFO、全局低通和 Cutoff LFO。
FM1 Convert 保留 128 条目录，其中 21 条已适配验证，不代表完整 FM-1/DX7 兼容。

32 键采集、校准、速度力度；App/MIDI 演奏；双触摸板及吉他模式；四拍 RAM 音序录制、叠录与回放。
HDMI 提供 720p 界面、真实波形/频谱和延迟监测。声音从底板耳机口输出，48,828.125 Hz / 16-bit / 双声道。
RGB 支持单键、涟漪、双向扫光、十字和彩虹流水，在 App「设备与输出」底部选择。

本版不访问 SD，内存录音断电丢失。共享波表上传时停音；旋钮音色编辑需 App 桥接。
本次只写 SRAM，断电需重新加载；未写配置 Flash。

## 最终验证

主时钟 Fmax 50.164 MHz，setup +0.066 ns、hold +0.069 ns；像素域 Fmax 88.407 MHz。
Logic 38053、CLS 26577、FF 28097、BSRAM 107、DSP 68.5。
时序仍贴近边界，每次改动后需重新布局布线。

RGB 像素参考、声像平滑、完整 ADC/UART/PT8211、8 声部压力仿真通过。
上板全部 RGB 模式读回、单音及八音和弦 PCM 正常，串口和音频异常计数为零。
实体灯光的视觉确认尚未记录，严格 RTL 风格门禁未全部通过。

GitHub 中的精选证据在 `reports/final-rgb/`；本地完整记录在 `reports/keyboard-rgb/`。
历史 `BOARD_TEST.md`、`RESOURCE_TIMING.md` 和带 FX 的性能记录保留作溯源，不代表本终版。

重建以仓库根目录 README 的 `tools/prepare_final_build.py` 为入口，使用本次冻结的源码和约束。
