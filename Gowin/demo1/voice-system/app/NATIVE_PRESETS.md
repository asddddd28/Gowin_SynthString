# Native AM / PM / Drum bank

本目录生成 20 个适用于现有六算子 FPGA 引擎的音色：AM 6、PM 6、Drum 8。音色是参数与路由配置，不包含采样素材，不需要更改 RTL 或上传波表。

## 使用

1. App 状态页选择一个音键，进入声音设计 → 选择预设音色。
2. 选择 AM、PM 或 Drum，确认“预设应用范围”，点击“载入此键”。应用范围可为当前键、共享音色的键或全部 32 键。
3. FPGA 确认后返回声音设计，从实体键或 App 演奏。多于两个算子的音色请通过“六算子配置”修改完整路由；主页面仅编辑 OP1 / OP2。

| 类别 | 音色 |
| --- | --- |
| AM | Tone 柔和合成、Tone 锯齿合奏、柔光钟、芦管、呼吸铺底、木质拨弦 |
| PM | Tone 经典、Tone 明亮主音、柔亮电钢、圆润贝斯、木琴、玻璃钟 |
| Drum | 深底鼓、电子军鼓、低音通鼓、闭镲、开镲、木击、牛铃、Tone 噪声击 |

鼓音色固定频率，不随琴键音高变化；持续电平为零，按住自然衰减。提前松键遵循各自释放段。音色使用现有的力度增益。静音后声部仍按现有 Note-Off 生命周期回收，并未增加鼓专用自动释放或开闭镲互斥组。

建议四键鼓组先用底鼓、军鼓、闭镲、开镲。当前硬件仍为 **4 个不同音色 / 8 复音**，20 个预设是可切换的目录，不表示可同时驻留 20 个。共享低通仍影响所有音色；低 Cutoff 会让镲片和军鼓变暗。载入音色不会自行旁路低通、修改按键音高、音量、键盘校准或波表。

## 来源与适配边界

5 个音色参考 [Tone.js](https://github.com/Tonejs/Tone.js/tree/105c04cc00289caf49684ac5c7621bce8a042c4c) 的 MIT 开源默认参数与示例，其余 15 个为 SynthString 原创配方。来源文件、提交号、SHA256 与完整 MIT 许可随 App 放在 `assets/native-bank-sources`。每张音色卡的“适配说明”列出具体来源和差异。

- AM：保留谐波比率及载波、调制波的独立包络。fatsawtooth 用三个显式失谐载波实现。
- Tone FM：方波频率调制转换为三角波相位调制；稳态深度（周期）为 `modulationIndex * 10^(-10/20) / (4 * harmonicity)`。时间变化包络与相位初值使其仍为近似。
- 包络：指数曲线转换为现有线性分段包络。编译字段为满量程斜坡时间，生成器按各段目标电平换算。
- 打击乐：采用固定频率、AM/PM、噪声与衰减包络，无真实鼓采样、无 808 音高下滑、无独立高通。未带限的锯齿/方波可能产生混叠。
- 本库不会扩大 FM1 Convert 的 DX7 算法兼容范围，也不宣称逐样本还原 Tone.js 或商业鼓机。

## 再生与验证

从 `voice-system` 运行：

```powershell
python presets/build_native_bank.py            # 确定性生成，无需网络
python presets/build_native_bank.py --fetch    # 重新获取固定提交的源码与 MIT 许可
python presets/validate_native_bank.py         # 整数模型、参考 WAV、协议字 oracle
```

从 `desktop-tauri` 运行：

```powershell
node scripts/rust-task.mjs test --lib --locked
node scripts/rust-task.mjs build --bin studio-test-harness --features test-harness --locked
npx playwright test tests/native-presets.spec.ts tests/unified-studio.spec.ts
```

`presets/test_native_bank_board.py` 使用现有 Rust 硬件 backend，需先正常退出 App、独占 COM4，使用 `fresh=false`。脚本备份当前会话、临时旁路低通、逐项装载并采集 PCM、测试六算子八复音，最后恢复原槽位与低通。报告在 `reports/native-presets`。不得对仍在占用串口的 App 并行运行。
