# SynthUartControl 模块规范

> RTL: `rtl/SynthUartControl.v`

## 1. 模块目的

Protocol5: fixed52-byte request SY/version/kind/sequence/opcode/argument/payload40/CRC16-CCITT, little-endian.

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

## 5. 周期行为与延迟

- Protocol5: fixed52-byte request SY/version/kind/sequence/opcode/argument/payload40/CRC16-CCITT, little-endian.
- Response32 bytes SR/version/kind/sequence/result128/transport_status/opcode/argument/replayflag/reserved16/CRC16.
- Kind0 engine command; kind1 read AXI register (payload W0); kind2 local status. Stop-and-wait, latest exact request cached, conflicts/stale/gaps reject without execution.
- Invalid CRC, framing, byte gap or packets while busy never execute. RX and TX use independent byte engines; host retries on timeout.
- DECODE registers packet equality and payload-zero chunks; CLASSIFY registers replay/conflict/sequence/payload decisions before CHECK. Adds two control clocks, preserves byte-exact retry semantics.
- Host NoteIDs must have bit31 clear; physical key IDs reserved. Boot-not-ready rejects engine/read requests. Local status is accepted while the parser is idle; a permanently stalled AXI request holds WAIT_REPLY until handshake or reset.

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

- Independent protocol/PCM model
- Real UART/ADC pins to serial DAC simulation
- AXI stalls, transaction ownership, duplicate/conflicting/invalid requests and reset
- Boot, physical chord, release, host voice/FX commands and resource/timing checks

## 10. 可追溯性

- 规格模块：`SynthUartControl`
- RTL 路径：`rtl/SynthUartControl.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
