# VoiceSynthEngine 声像乘法分拍实验

日期：2026-11-02，18:51 完成独立布局布线。比较基线为已完成公共完成缓冲隔离的 P0-A；目标保持 50 MHz / 20 ns。**本轮声像长路径已消除，整板 Fmax 从 34.028 提升到 45.327 MHz，但仍未满足 50 MHz，未烧录。**

## 修改及数值约束

原最差路径为 `reg_mod_pan → 左系数相减 → 乘法 → reg_left_product`，WNS −9.387 ns。此次唯一变化的构建输入为 `voice-engine/rtl/VoiceSynthEngine.v`，不改变公共完成缓冲、命令译码、RAM、包络或调制算法。

- state16 提前锁存左右声像系数，各为无符号 27 位，范围 `[0, 2^26]`。
- state7 用 signed32 音频乘以 `{0, coefficient[25:0]}`，得到完整 signed59 乘积并寄存；同时保存输入音频。
- 新增 state18：最高系数位为 1 时，系数必为精确满增益，选择 `sample << 26`；其他情况将原始乘积符号扩展到 64 位。
- state8 保留原来的 `product[57:26]` 取样和立体声累加。

因此完整乘积与原表达式逐位一致，没有增加舍入、截断或近似。必须依赖已有 state15 将声像限幅到 `[0,2^26]` 的不变量；不能将此旁路推广到任意大于满增益的系数。

原有增益/声像平滑写回、禁用声部处理和 state1 清零后直达 state8 的快速路径均保留。新增寄存器异步复位清零，没有删除任何原 DSP 复位。端口、ABI、音色格式、完成握手和采样周期不变。

时序图与完整合同：`../voice-engine/spec/VoiceSynthEngine_spec.md`。

## 验证结果

| 验证 | 结果 |
|---|---|
| Python 精确整数模型 | 400180 次左右乘积检查通过，覆盖 signed32 全范围随机值和系数边界 |
| `tb_voice_pan_pipeline` | 2090 组、4180 乘积、2090 次非活动快速路径、11 次流水中复位通过 |
| `tb_axi_fx` | Voice 874 拍、FX 72 拍、整链 948 拍，117 条命令通过 |
| 独立完整 PCM 整数模型 | 6133 帧一致，停止时没有在途帧 |
| `tb_axi_synth_engine` | 快照、重放、实时提交、旧协议和溢出通过 |
| `tb_axi_lfo` | 全局/局部、重放及非法输入通过 |
| `tb_completion_isolation` | 4843 接收、4839 交付、4 个复位取消，隔离保持有效 |
| `tb_synth_system` | 四音色、66 键事件、134 UART 回复、3436 PCM；最大 948 拍 |

每个走完整路径的声部增加一拍，八声部增加 8 拍。满载总计算由 940 → 948 拍（50 MHz 下为 18.96 μs），距离 1024 拍截止还剩 76 拍 / 1.52 μs。该数值仅描述本次回归覆盖的负载，不代表物理 50 MHz 已收敛，也不是按键到耳机总延迟。

两处回归中的“必须观察到满载”断言从 866/940 更新为 874/948；严格小于 1024 拍的 deadline 断言未放宽。对应测试生成模板及当前合同同步更新，历史构建报告保留原数值。

常规 `voice-engine/model/run_fx_validation.ps1` 的测试列表已加入 `voice_pan_pipeline` 和 `completion_isolation`；本轮逐项执行了上表中的六项仿真。入口脚本通过 PowerShell 语法解析，未重复运行未改动的独立 Delay/Reverb 测试。

## 资源与物理检查

综合报告：`MULT27X36` 原语 48 → 46，寄存器 23787 → 23917（+130），BSRAM/SSRAM 数量不变。Voice 本体的 `MULT27X36` 为 16 → 14。最终物理 DSP 为 98 → 94。综合网表由工具加密，因此没有据此宣称每个新增乘积寄存器都已吸收到 DSP 内；实际收益以资源与 STA 为证。

独立目录：`reports/voice-pan-pipeline/build/`。使用与 P0-A 一致的 50 MHz、器件、CST 和布局布线选项，setup 报告展开 5000 条、每终点一条。输入哈希与唯一变化记录在 `inputs.json`，源码差异为 `VoiceSynthEngine.diff`。

## 门禁与局限

`VoiceSynthEngine.v` 的 compile 门禁通过；ast（formatter 模板）、readability、comment、naming、profile 仍失败，严格错误从 1509 → 1546，并非所有问题都是历史遗留。新测试严格门禁为 0 错误、0 警告。静态门禁的 testbench/toolchain 项未请求；实际 xsim 外部证据如上，不能把静态项状态与真实执行结果混同。

规格生成器的可选 `--source` 校验将旧式函数的局部输入 count/product/target_value 误当作模块端口，因此该源交叉检查未通过。沿用项目 `publish_specs.py` 中已有的显式合同渲染方式生成 Voice 文档与 WaveDrom；未添加虚假接口端口。新测试的源接口交叉检查正常通过。Python 辅助文件只改了生成字符串和期望周期，已通过语法编译检查，未运行专用 Python 风格门禁。

本轮为单一计算边界实验；布局布线完成但 50 MHz STA 未通过，当前没有烧录或发布 GitHub。

## 全覆盖 STA 对比

解析 5000 条 setup 路径，覆盖报告中的全部 222 个失败终点，5000 条 arc 延迟加和一致。42 个构建输入在构建期间未变化；与 P0-A 相比仅 VoiceSynthEngine.v 改动，器件、约束与 place/route 选项一致，旧基线时序报告哈希未变化。

| 指标 | P0-A | 声像分拍候选 |
|---|---:|---:|
| 约束频率 | 50 MHz | 50 MHz |
| 报告 Fmax | 34.028 MHz | 45.327 MHz |
| Setup WNS | −9.387 ns | −2.062 ns |
| Setup TNS（工具汇总） | −625.236 ns | −115.792 ns |
| Setup 失败终点 | 347 | 222 |
| Hold 失败终点 | 0 | 0 |
| VoiceSynthEngine 失败终点 | 118 | 30 |
| 原声像左乘积路径族失败终点 | 32 | 0 |
| 完成计数器起点失败路径 | 0 | 0 |
| 命令头起点失败路径 | 171 | 166 |

本轮报告中 27 条以声像寄存器/乘积命名的相关路径全部非负，最小已报告裕量 +1.753 ns；完整失败集合没有声像路径。hold 总失败终点为 0，已报告的各 100 条 recovery/removal 没有负裕量。其他未改动模块的改善或变差也受重新综合/布局影响，不能全部归因于其内部逻辑发生变化。

| 剩余路径归属 | 终点数 | 最差裕量 | 主要路径 |
|---|---:|---:|---|
| 命令头 → AxisFxEngine | 74 | −2.062 ns | `reg_command_head → reg_delay_active/CE` 等 |
| 命令头 → Reverb | 86 | −1.413 ns | `reg_lowpass/CE`、`reg_pointer/CE` 等 |
| DX Envelope 内部 | 6 | −1.239 ns | `reg_level → reg_shift/reg_next_level` |
| 命令头 → Delay | 4 | −1.206 ns | `reg_state/CE` |
| Modulation → LFO | 22 | −1.126 ns | `reg_context → LFO乘法器输入` |
| VoiceSynthEngine 内部 | 28 | −0.774 ns | 参数ROM→算子请求17个、gain平滑11个 |
| 命令头 → Voice | 2 | −0.735 ns | `reg_prechecked_status` |
| 合计 | 222 | | |

最差命令控制路径数据延迟中 net 18.320 ns、cell 3.421 ns；当前不再由声像算术限制 Fmax。命令头相关 166/222 个终点约占 74.8%，应进入独立 P0-B 控制路径隔离实验。

## 最终物理资源

| 资源 | P0-A | 声像分拍候选 | 变化 |
|---|---:|---:|---:|
| Logic | 27531/59904 | 27386/59904 | −145 |
| Register | 23787/60780 | 23917/60780 | +130 |
| CLS | 24310/29952 | 24488/29952 | +178 |
| BSRAM | 98/118 | 98/118 | 0 |
| DSP | 98/118 | 94/118 | −4 |

CLS 仍为报告占用 82%，BSRAM 84%，DSP 从 84% 降为 80%。

## 下一轮优先级

1. **P0-B：命令译码及配置/清空控制的本地寄存边界。** 先检查命令头跨 AxisSynthSystem、AxisFxEngine 到 Delay/Reverb 的接受、提交和清空链；保留单次执行、反压、音频优先与原子提交语义，不增加音频计算状态。
2. 分别处理 DX 包络电平判定和 Modulation→LFO 上下文选择路径；每次独立验证，避免把多个调度周期变化叠加后才检查 1024 拍期限。
3. Voice 仍有 28 条本体违例，主要是参数 ROM 到算子请求与 gain 平滑；声像路径不再继续盲调，后续依新报告推进。

原始报告及机器可读对比：`reports/voice-pan-pipeline/analysis/{summary.json,paths.json,setup-violations.csv}`、`comparison.json`、`verification.json`。可独立重跑常规回归入口 `../voice-engine/model/run_fx_validation.ps1`；Gowin 入口为实验目录内 `build/build.tcl`。
