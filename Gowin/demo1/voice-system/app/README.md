# Tang Synth Studio · Final RGB 配套 App

直接运行本目录 `TangSynthStudio.exe`，并保留 `assets` 和 `licenses`。
配套固件为 `../firmware/final-rgb/synth_hdmi.fs`（Final RGB，ED65）。需要 WebView2 Runtime。

1. 连接调试串口，本机 COM4；板卡刚复位/烧录时建立新会话，普通重连沿用原会话。
2. 默认状态页显示 32 键、PCM 波形/频谱、数字输出延迟。点击键名进入声音设计。
3. 从声音设计进入音色浏览器；六算子配置通过弹窗编辑。支持电脑键盘、MIDI、延音与临时移调。
4. 「设备与输出」配置键盘校准、阈值/力度、触摸、低通/Cutoff LFO 与 HDMI。
5. 页底「键盘 RGB 灯效」选择单键、涟漪、扫光、十字、彩虹流水或关闭；扫光可选择横向/纵向。

4 个驻留音色槽、8 复音；录音层也占用槽。FM1 目录 128 条，当前 21 条经过适配验证。
波表全局共享，上传时暂停发声。音序仅保存在 RAM，SD 存取已停用。
RGB 退出 App 后继续运行；固件复位恢复单键模式。本次 SRAM 下载断电丢失，需要重新加载固件。

实体旋钮从左到右 E5→E1：E1 切槽、E2 选算子、E3 调电平、E4 调频率比、E5 调主音量。
摇杆左右切页，上下选算子，短按应用当前槽草稿，长按切触摸演奏模式。
旋钮编辑需要 App 保持连接；本地演奏、RGB 和 HDMI 分析独立运行。

声音从底板 3.5 mm 耳机输出，48.828125 kHz / 16-bit / 双声道；HDMI 不携带音频。
个人会话与已确认设置位于 `%LOCALAPPDATA%/SynthString/voice-engine/`，没有随仓库上传。
完整说明见 [UNIFIED_STUDIO.md](UNIFIED_STUDIO.md)、[RGB](KEYBOARD_RGB.md)。
