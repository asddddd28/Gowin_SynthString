# SynthUartControl 模块规范

> RTL: `rtl/SynthUartControl.v`

## 1. 模块目的

Protocol5: fixed52-byte request SY/version/kind/sequence/opcode/argument/payload40/CRC16-CCITT, little-endian.

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
| `i_rx` | input | 1 | 未声明 | control | i_rx |
| `o_tx` | output | 1 | 未声明 | control | o_tx |
| `i_initialized` | input | 1 | 未声明 | control | i_initialized |
| `i_status` | input | 128 | 未声明 | data | i_status |
| `o_bad_packets` | output | 32 | 未声明 | data | o_bad_packets |
| `o_replayed` | output | 32 | 未声明 | data | o_replayed |
| `o_local_request` | output | 1 | i_clk | control | o_local_request |
| `o_local_opcode` | output | 8 | i_clk | data | o_local_opcode |
| `o_local_argument` | output | 8 | i_clk | data | o_local_argument |
| `o_local_words` | output | 64 | i_clk | data | o_local_words |
| `i_local_valid` | input | 1 | i_clk | control | i_local_valid |
| `i_local_response` | input | 136 | i_clk | data | i_local_response |

## 5. 周期行为与延迟

- Protocol5 retains 52-byte requests and 32-byte CRC16 responses. Kinds0/1/2 preserve existing AXI/status behavior.
- Kind3 dispatches to a board-local monitor, with unused payload words2..9 required zero. LOCAL_SEND is a single-cycle pulse; LOCAL_WAIT waits for completion.
- Duplicate sequence plus identical complete payload replays the cached response without another write or capture trigger. Changed duplicate and out-of-order sequence reject without side effects.
- Local operation errors consume their sequence and are cached, exactly like other validated requests.
- Allow D0/D1 globalfilter mailbox commands and aligned capability read through0x64; preserve CRC/exact replay andsequence handling.

## 6. WaveDrom 时序图

### 流水接纳与反压

事件或命令稳定保持至握手，执行后完成返回；音频按固定帧节拍独立运行。示意图不表示绝对运算周期。

![流水接纳与反压](waveforms/SynthUartControl_stream.svg)

- WaveJSON：[SynthUartControl_stream.json5](waveforms/SynthUartControl_stream.json5)

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

- 规格模块：`SynthUartControl`
- RTL 路径：`rtl/SynthUartControl.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
