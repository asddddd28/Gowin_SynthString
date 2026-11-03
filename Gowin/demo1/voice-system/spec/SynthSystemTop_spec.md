# SynthSystemTop 模块规范

> RTL: `rtl/SynthSystemTop.v`

## 1. 模块目的

Single50MHz board hierarchy: ADC scanner and hysteresis → note source; UART → framed control; boot/keys/host → arbiter → AXI master → AxiSynthEndpoint → PT8211.

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
| `i_adc_dout` | input | 1 | 未声明 | control | i_adc_dout |
| `i_uart_rx` | input | 1 | 未声明 | control | i_uart_rx |
| `o_mux_sel` | output | 3 | 未声明 | data | o_mux_sel |
| `o_mux_en` | output | 1 | 未声明 | control | o_mux_en |
| `o_adc_cs_n` | output | 1 | 未声明 | control | o_adc_cs_n |
| `o_adc_sclk` | output | 1 | 未声明 | control | o_adc_sclk |
| `o_adc_din` | output | 1 | 未声明 | control | o_adc_din |
| `o_uart_tx` | output | 1 | 未声明 | control | o_uart_tx |
| `HP_BCK` | output | 1 | 未声明 | control | HP_BCK |
| `HP_WS` | output | 1 | 未声明 | control | HP_WS |
| `HP_DIN` | output | 1 | 未声明 | control | HP_DIN |
| `PA_EN` | output | 1 | 未声明 | control | PA_EN |
| `o_display_reset_n` | output | 1 | i_clk | data | Passive display / local request interface: o_display_reset_n |
| `o_display_keys` | output | 32 | i_clk | data | Passive display / local request interface: o_display_keys |
| `o_display_latency` | output | 32 | i_clk | data | Passive display / local request interface: o_display_latency |
| `o_display_underruns` | output | 32 | i_clk | data | Passive display / local request interface: o_display_underruns |
| `o_display_errors` | output | 32 | i_clk | data | Passive display / local request interface: o_display_errors |
| `o_display_frames` | output | 32 | i_clk | data | Passive display / local request interface: o_display_frames |
| `o_display_sample_valid` | output | 1 | i_clk | data | Passive display / local request interface: o_display_sample_valid |
| `o_display_sample` | output | 16 | i_clk | data | Passive display / local request interface: o_display_sample |
| `o_display_request` | output | 1 | i_clk | data | Passive display / local request interface: o_display_request |
| `o_display_opcode` | output | 8 | i_clk | data | Passive display / local request interface: o_display_opcode |
| `o_display_argument` | output | 8 | i_clk | data | Passive display / local request interface: o_display_argument |
| `o_display_words` | output | 64 | i_clk | data | Passive display / local request interface: o_display_words |
| `i_display_response_valid` | input | 1 | i_clk | data | Passive display / local request interface: i_display_response_valid |
| `i_display_response` | input | 136 | i_clk | data | Passive display / local request interface: i_display_response |
| `o_display_calibrating` | output | 1 | i_clk | data | o_display_calibrating |
| `i_touch_next` | input | 1 | 未声明 | data | i_touch_next |
| `io_touch_scl` | inout | 2 | 未声明 | data | io_touch_scl |
| `io_touch_sda` | inout | 2 | 未声明 | data | io_touch_sda |
| `o_touch_mode` | output | 2 | 未声明 | data | o_touch_mode |
| `i_buttons` | input | 6 | 未声明 | data | i_buttons |
| `o_sequence_status` | output | 32 | 未声明 | data | o_sequence_status |
| `o_sequence_bpm` | output | 9 | 未声明 | data | o_sequence_bpm |

## 5. 周期行为与延迟

- SynthStudioMonitor connects to the UART local command port, keyboard mapping RAM and actual PT8211 frame acceptance.
- DSP AXI routing, six-operator pool, eight voices, 50MHz clock and 1024-cycle sample period remain unchanged.
- Audio capture and host reads are passive. The monitor tracks one key dispatch at a time, correlates the Note-On completion frame tag, and reports cycles to that exact output frame.
- HDMI observer interface: no display backpressure into audio. Display commands are enabled only with C_DISPLAY_ENABLE=1; default0 retains original monitor routing.
- Keyboard frontend supports banked calibration and measured velocity. Enabled physical NoteOn gain=(velocity+1)/128; fixed mode retains unity. Calibration flag drives HDMI overlay.
- Keyboard local opcodes20..28 include atomic microsecond timing observation;50MHz scanner cadence unchanged.
- C_TOUCH_ENABLE默认0；HDMI顶层开启后，串口0x30..0x33分派触摸模块，物理按键先经TouchPerformance再交给KeyboardSource。
- C_SEQUENCE_ENABLE默认0；启用后实例化SynthSequencer/SynthMetronome，真实键盘命令在ready/valid同时有效时采样。校准中静音停录/停播。
- 本地0x40..0x42与原键盘/显示/滤波/触摸本地指令解码互斥；音序器是第三个运行期AXI命令来源。
- 本地0x40..0x48与原键盘/显示/滤波/触摸本地指令解码互斥；音序器是第三个运行期AXI命令来源。
- 本地0x40..0x49与原键盘/显示/滤波/触摸本地指令解码互斥；音序器是第三个运行期AXI命令来源。
- SD local requests 0x50..0x55 share the existing CRC/replay-protected UART. SynthHdmiTop instantiates autonomous storage mount; archive save/load control is not yet connected.

## 6. WaveDrom 时序图

### 小节提交与回放握手

按键事件暂存，停止后保留完成的小节；回放命令稳定等待仲裁和回执。

![小节提交与回放握手](waveforms/SynthSystemTop_record-play.svg)

- WaveJSON：[SynthSystemTop_record-play.json5](waveforms/SynthSystemTop_record-play.json5)

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

- 规格模块：`SynthSystemTop`
- RTL 路径：`rtl/SynthSystemTop.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
