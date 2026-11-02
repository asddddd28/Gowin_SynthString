# VoiceModulation 模块规范

> RTL: `rtl/VoiceModulation.v`

## 1. 模块目的

两LFO和八路稀疏调制的参数银行、状态池与帧调度。

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_axis_aclk", "edge": "posedge", "frequency_hz": 50000000}`
- 复位：`{"name": "i_axis_arstn", "active": "low", "style": "asynchronous", "values": "all pipeline valid and output data/tag registers clear; external synchronous release"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_axis_aclk` | input | 1 | 未声明 | clock | 共用50MHz时钟 |
| `i_axis_arstn` | input | 1 | 未声明 | reset | 低有效复位 |
| `i_start_frame` | input | 1 | 未声明 | control | 开始一次全源更新 |
| `i_patch_valid` | input | 4 | 未声明 | data | 有效音色槽 |
| `i_patch_bank` | input | 4 | 未声明 | data | 各音色活动银行 |
| `i_voice_active` | input | 8 | 未声明 | data | 活动声部 |
| `i_voice_patch` | input | 16 | 未声明 | data | 每声部2位音色槽 |
| `i_start_voice` | input | 1 | 未声明 | control | 开始某声部路由计算 |
| `i_voice` | input | 3 | 未声明 | data | 当前声部 |
| `i_patch` | input | 2 | 未声明 | data | 当前声部音色 |
| `i_note_on` | input | 1 | 未声明 | control | 实际新分配声部事件，重试不能置位 |
| `i_note_voice` | input | 3 | 未声明 | data | 新分配声部 |
| `i_restart` | input | 1 | 未声明 | control | 仅新执行的显式重触发 |
| `i_restart_context` | input | 5 | 未声明 | data | 需要重触发的上下文 |
| `i_begin` | input | 1 | 未声明 | control | 清空草稿的启用掩码 |
| `i_config_write` | input | 1 | 未声明 | control | 写草稿参数 |
| `i_config_route` | input | 1 | 未声明 | control | 路由参数或LFO参数 |
| `i_config_bank` | input | 1 | 未声明 | control | 草稿银行 |
| `i_config_patch` | input | 2 | 未声明 | data | 草稿音色槽 |
| `i_config_index` | input | 3 | 未声明 | data | LFO或路由编号 |
| `i_config_data` | input | 160 | 未声明 | data | LFO五字或路由两字 |
| `i_inspect` | input | 5 | 未声明 | data | 调试上下文索引 |
| `o_inspect` | output | 128 | 未声明 | data | 当前源值/相位/资格/RNG快照 |
| `o_busy` | output | 1 | 未声明 | control | 帧或路由执行中 |
| `o_done` | output | 1 | 未声明 | control | 单周期完成通知 |
| `o_modulation` | output | 480 | 未声明 | data | 15个有符号32位调制累加结果 |

## 5. 周期行为与延迟

- 24 state slots: eight patch-global and sixteen voice-local. Only enabled/eligible source contexts advance, once per frame; routes never advance source state.
- Parameters are double banked with the voice program. Begin disables the inactive bank LFO and route masks without disturbing the active bank.
- New NoteID allocation clears local LFO initialization; first eligible frame restarts phase and seed. Global phase is independent of note events.
- Eight routes accumulate in 36-bit guards across fifteen targets; output saturates to signed32. Base musical parameters are not modified.
- Route descriptor, source/depth operands, product and accumulator are registered separately. Eight descriptors issue at II=1, drain before final clamp; start-to-done is13 clocks. Disabled routes force both operands to zero; same-target writes retain source order.
- Start pulses and configuration writes are only accepted while idle by contract; parent prevents control writes during a render.

## 6. WaveDrom 时序图

### 流水接纳与反压

先发frame启动，24上下文流水扫描完成后发done；每个声部再启动8路累加；配置仅在idle提交。

![流水接纳与反压](waveforms/VoiceModulation_stream.svg)

- WaveJSON：[VoiceModulation_stream.json5](waveforms/VoiceModulation_stream.json5)

## 7. 边界、反压与错误

- signed minima/maxima and zero
- changing tags and parameters every accepted beat
- long backpressure and bubbles
- reset while pipeline holds transactions

## 8. CDC 与综合约束

- Verilog-2001, one clock domain. No board integration claim.
- See MODULATION.md for units, commands, source scopes and reset behavior.

## 9. 验证与验收

- Independent integer model and mixed waveform PCM comparisons
- Free-run versus key restart; voice steal and duplicate request
- Eight routes, signed saturation and disabled sources
- Worst-case sample deadline and concurrent AXI traffic

## 10. 可追溯性

- 规格模块：`VoiceModulation`
- RTL 路径：`rtl/VoiceModulation.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
