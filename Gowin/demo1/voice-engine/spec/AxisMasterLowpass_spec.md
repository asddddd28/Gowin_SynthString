# AxisMasterLowpass 模块规范

> RTL: `rtl/AxisMasterLowpass.v`

## 1. 模块目的

Shared stereo two-pole lowpass and independent Cutoff LFO

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_clk", "edge": "posedge", "frequency_hz": 50000000}`
- 复位：`{"name": "i_rstn", "active": "low", "style": "asynchronous", "values": "bypass; zero phase and audio state; default2000Hz cutoff; command/audio valid cleared"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | i_clk | clock | i_clk |
| `i_rstn` | input | 1 | i_clk | reset | i_rstn |
| `i_command` | input | 384 | i_clk | data | i_command |
| `i_tag` | input | 32 | i_clk | data | i_tag |
| `i_opcode` | input | 8 | i_clk | data | i_opcode |
| `i_command_valid` | input | 1 | i_clk | data | i_command_valid |
| `o_command_ready` | output | 1 | i_clk | data | o_command_ready |
| `o_result` | output | 128 | i_clk | data | o_result |
| `o_tag` | output | 32 | i_clk | data | o_tag |
| `o_opcode` | output | 8 | i_clk | data | o_opcode |
| `o_result_valid` | output | 1 | i_clk | data | o_result_valid |
| `i_result_ready` | input | 1 | i_clk | data | i_result_ready |
| `i_audio` | input | 64 | i_clk | data | i_audio |
| `i_frame` | input | 32 | i_clk | data | i_frame |
| `i_audio_valid` | input | 1 | i_clk | data | i_audio_valid |
| `o_audio_ready` | output | 1 | i_clk | data | o_audio_ready |
| `o_audio` | output | 64 | i_clk | data | o_audio |
| `o_frame` | output | 32 | i_clk | data | o_frame |
| `o_audio_valid` | output | 1 | i_clk | data | o_audio_valid |
| `i_audio_ready` | input | 1 | i_clk | data | i_audio_ready |
| `i_touch_cutoff` | input | 20 | 未声明 | data | i_touch_cutoff |
| `i_touch_cutoff_active` | input | 1 | 未声明 | data | i_touch_cutoff_active |

## 5. 周期行为与延迟

- D0 validates five-word configuration then atomically replaces shadow registers; D1 reads flags/revision/current-cutoff. Result holds under backpressure independently of audio.
- Audio accept snapshots all config. Phase increments once/frame; sine/triangle bipolar LFO changes log-frequency target. Clamp20..18000Hz, smooth with1/256, synchronous18bit coefficient ROM.
- Single signed33x20 multiplier executes four one-pole updates and two dry/wet blends. Left/right states independent. Bypass transition256frames; exact dry aftersettling. Full-scale input/state convex bounds prevent overflow.
- 30clocks to audio valid, output data/frame stable under backpressure. Global LFO free-running peraccepted audio frame, no NoteOn retrigger.
- C_TOUCH_ENABLE默认0；帧边界锁存触摸偏移，AUDIO_WAVE寄存base+touch，AUDIO_TARGET再叠加LFO。触摸有效临时开启滤波，不修改已保存配置。

## 6. WaveDrom 时序图

### 触摸事件与调制提交

触摸采集在系统域提交，调制每毫秒平滑；音频帧独立执行，NoteOff确认之后才重新起音。

![触摸事件与调制提交](waveforms/AxisMasterLowpass_touch.svg)

- WaveJSON：[AxisMasterLowpass_touch.json5](waveforms/AxisMasterLowpass_touch.json5)

## 7. 边界、反压与错误

- Full signed32range, opposite polarity stereo, silent channel, cutoff clamps, fast automation, bypass, zero depth, command completion stalled, invalid params.

## 8. CDC 与综合约束

- System feeds one frame per1024clocks and always drains filter output into existingPCMqueue. LFO .05..20Hz,depth0..6oct. Filter helper is one physical instance, not one pervoice.
- Command UART exact replay owns duplicate suppression; repeatedD0 is idempotent and never resets phase/state. Independent master filter sequence prevents voice/fx gaps.

## 9. 验证与验收

- Python magnitude response -3dB at declared cutoff, bitexact12288frame model comparison, random output backpressure; entire keyboard/UART/AXI/PCM chain; real50MHz implementation and hardware capture.

## 10. 可追溯性

- 规格模块：`AxisMasterLowpass`
- RTL 路径：`rtl/AxisMasterLowpass.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
