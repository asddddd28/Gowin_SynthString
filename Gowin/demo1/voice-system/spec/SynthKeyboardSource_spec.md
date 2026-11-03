# SynthKeyboardSource 模块规范

> RTL: `rtl/SynthKeyboardSource.v`

## 1. 模块目的

Physical key bitmap becomes edge events; holding a key never emits another NoteOn.

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_clk", "edge": "posedge", "frequency_hz": 50000000}`
- 复位：`{"name": "i_rstn", "active": "low", "style": "asynchronous", "values": "all pipeline valid and output data/tag registers clear; external synchronous release"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | 未声明 | clock | i_clk |
| `i_rstn` | input | 1 | 未声明 | reset | i_rstn |
| `o_request` | output | 392 | 未声明 | data | o_request |
| `o_request_valid` | output | 1 | 未声明 | control | o_request_valid |
| `i_request_ready` | input | 1 | 未声明 | control | i_request_ready |
| `i_response` | input | 136 | 未声明 | data | i_response |
| `i_response_valid` | input | 1 | 未声明 | control | i_response_valid |
| `o_response_ready` | output | 1 | 未声明 | control | o_response_ready |
| `i_enabled` | input | 1 | 未声明 | control | i_enabled |
| `i_pressed` | input | 32 | 未声明 | data | i_pressed |
| `o_delivered` | output | 32 | 未声明 | data | o_delivered |
| `o_events` | output | 32 | 未声明 | data | o_events |
| `o_fault` | output | 1 | 未声明 | control | o_fault |
| `i_config_write` | input | 1 | i_clk | control | i_config_write |
| `i_config_key` | input | 5 | i_clk | data | i_config_key |
| `i_config_data` | input | 48 | i_clk | data | i_config_data |
| `o_config_data` | output | 48 | i_clk | data | o_config_data |
| `o_event_start` | output | 1 | i_clk | control | o_event_start |
| `o_event_finish` | output | 1 | i_clk | control | o_event_finish |
| `o_event_failed` | output | 1 | i_clk | control | o_event_failed |
| `o_event_key` | output | 5 | i_clk | data | o_event_key |
| `o_event_frame` | output | 32 | i_clk | data | o_event_frame |
| `o_velocity_key` | output | 5 | i_clk | data | o_velocity_key |
| `i_velocity` | input | 7 | i_clk | data | i_velocity |
| `i_velocity_enabled` | input | 1 | i_clk | data | i_velocity_enabled |
| `o_idle` | output | 1 | 未声明 | data | o_idle |

## 5. 周期行为与延迟

- 32 physical keys use a synchronous 48-bit RAM mapping: phase32, slot2, MIDI7, velocity7. Power-up defaults remain MIDI48..79, patch0, velocity100.
- The scan port latches a complete mapping before preparing a note. Configuration writes acknowledge after the write edge. Concurrently prepared events retain the latched mapping.
- Held-key remapping never retriggers; Note-Off retains its original identity. New presses receive a fresh bit31-set identity and use the new mapping.
- o_event_start observes PREPARE for Note-On; o_event_finish observes the accepted response. o_event_frame is completion bits63:32. Failed events are cancelled by the passive monitor.
- Keyboard frontend supports banked calibration and measured velocity. Enabled physical NoteOn gain=(velocity+1)/128; fixed mode retains unity. Calibration flag drives HDMI overlay.
- o_idle在SCAN状态有效；拨弦调度必须同时确认o_delivered等于预期门控图，防止在途NoteOn尚未ACK就覆盖重触发。

## 6. WaveDrom 时序图

### 触摸事件与调制提交

触摸采集在系统域提交，调制每毫秒平滑；音频帧独立执行，NoteOff确认之后才重新起音。

![触摸事件与调制提交](waveforms/SynthKeyboardSource_touch.svg)

- WaveJSON：[SynthKeyboardSource_touch.json5](waveforms/SynthKeyboardSource_touch.json5)

## 7. 边界、反压与错误

- signed minima/maxima and zero
- changing tags and parameters every accepted beat
- long backpressure and bubbles
- reset while pipeline holds transactions

## 8. CDC 与综合约束

- Verilog-2001, single50MHz clock; asynchronous reset assertion, externally synchronized release.
- See SYSTEM.md and model/system_model.py for ABI, numerical behavior, memory images and validation scope.

## 9. 验证与验收

- Full existing board regression: 134 UART replies, all 32 keys, eight-voice load and serial DAC.
- tb_studio_system: local command CRC/replay, distinct key patches, held remapping/release, 512 signed16 capture samples compared to DAC quantization, tagged latency.

## 10. 可追溯性

- 规格模块：`SynthKeyboardSource`
- RTL 路径：`rtl/SynthKeyboardSource.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
