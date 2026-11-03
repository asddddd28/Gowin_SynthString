# SDP 拆分资源对照

2026-11-02，使用 Gowin V1.9.11.03 Education，器件 GW5AT-LV60PG484AC1/I0（B）。目标仍为 50 MHz；不改 RTL、音色、采样周期或 SDC。基线为 `reports/fm-interpolation-pipeline`，单独将 `convert_sdp32_36_to_sdp16_18` 从默认开启改为关闭。

42 个输入已冻结到 `reports/sdp-conversion-off/build/snapshot` 并逐个核对 SHA256；项目文件仅重定位输入路径，构建命令已确认没有 SDP 拆分选项。该实验没有与后续 Voice RTL 修改混合。

## 实际布局布线结果

| 指标 | 基线：开启拆分 | 实验：关闭拆分 |
|---|---:|---:|
| Logic | 27110 | 27105 |
| Register | 24090 | 24090 |
| CLS / 29952 | 24337 | 24348 |
| BSRAM / 118 | 98 | 77 |
| SDPB / SDPX9B / pROM | 76 / 10 / 12 | 60 / 5 / 12 |
| DSP / 118 | 94 | 94 |
| Fmax | 50.037 MHz | 50.000 MHz |
| 最小 setup slack | +0.015 ns | +0.000 ns（报告精度） |
| Setup / Hold 失败终点 | 0 / 0 | 0 / 0 |
| Setup TNS | 0 ns | 0 ns |

BSRAM 减少 21 块，占用由 83.05% 降至 65.25%。CLS 增加 11，变化很小；本实验没有得到 CLS 降至 71% 或时序裕量显著增加的结果。工具以整数向上显示占比为 84%/66%，不影响上述实际分数。

工具分析 76700 条路径、77807 个端点。展开 5000 条 setup 路径均通过逐弧核对；hold、recovery、removal 各展开 100 条，最小 slack 分别为 +0.078 / +4.112 / +1.517 ns。最紧 setup 路径转到命令地址 `reg_command_head[320]` → Voice `reg_prechecked_status[0]`，数据延迟 19.936 ns，其中网络延迟 15.517 ns；最长单条布线 12.738 ns。关闭拆分没有解决此控制路径。

## 使用边界

高云 [ADV-SW-20240920-CN 技术公告](https://cdn.gowinsemi.com.cn/ADV-SW-20240920-CN.pdf) 指出该选项与 GW5AT-60ES/B 的 SDP32/36 抗电源噪声能力有关，关闭的条件是确保 VCC 不低于 0.9 V。工程里填写 `vcc=0.9` 不能证明实板瞬态电压下限。

因此本次关闭拆分的码流只作为离线实验，**未烧录，也未改成默认选项**。功能仿真可沿用相同 RTL 的证据，但不能据此声称该存储物理模式已经通过实板验证。后续 Voice RTL 的布局布线仍开启拆分，便于分别归因。

## 复核入口

- 构建：`reports/sdp-conversion-off/build/build.tcl`
- 42 个冻结输入及哈希：`reports/sdp-conversion-off/inputs.json`
- 结果摘要：`reports/sdp-conversion-off/result.json`
- 完整时序分析：`reports/sdp-conversion-off/analysis/summary.json`、`paths.json`
- 原始报告与码流：`reports/sdp-conversion-off/build/impl/pnr/`

本实验码流 SHA256：`cc6502b3d8ea1f1fab59f44272768baf4adb77be028bab46c9d0bc0adc25e406`。
