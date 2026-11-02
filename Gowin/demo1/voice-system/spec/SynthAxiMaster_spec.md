# SynthAxiMaster 模块规范

> RTL: `rtl/SynthAxiMaster.v`

## 1. 模块目的

Single-outstanding AXI4 master; aligned 32-bit single-beat INCR, ID=0 and full strobes tied at top.

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
| `i_request` | input | 392 | 未声明 | data | i_request |
| `i_request_valid` | input | 1 | 未声明 | control | i_request_valid |
| `o_request_ready` | output | 1 | 未声明 | control | o_request_ready |
| `o_response` | output | 136 | 未声明 | data | o_response |
| `o_response_valid` | output | 1 | 未声明 | control | o_response_valid |
| `i_response_ready` | input | 1 | 未声明 | control | i_response_ready |
| `o_axi_awaddr` | output | 16 | 未声明 | data | o_axi_awaddr |
| `o_axi_awvalid` | output | 1 | 未声明 | control | o_axi_awvalid |
| `i_axi_awready` | input | 1 | 未声明 | control | i_axi_awready |
| `o_axi_wdata` | output | 32 | 未声明 | data | o_axi_wdata |
| `o_axi_wvalid` | output | 1 | 未声明 | control | o_axi_wvalid |
| `i_axi_wready` | input | 1 | 未声明 | control | i_axi_wready |
| `i_axi_bresp` | input | 2 | 未声明 | data | i_axi_bresp |
| `i_axi_bvalid` | input | 1 | 未声明 | control | i_axi_bvalid |
| `o_axi_bready` | output | 1 | 未声明 | control | o_axi_bready |
| `o_axi_araddr` | output | 16 | 未声明 | data | o_axi_araddr |
| `o_axi_arvalid` | output | 1 | 未声明 | control | o_axi_arvalid |
| `i_axi_arready` | input | 1 | 未声明 | control | i_axi_arready |
| `i_axi_rdata` | input | 32 | 未声明 | data | i_axi_rdata |
| `i_axi_rresp` | input | 2 | 未声明 | data | i_axi_rresp |
| `i_axi_rlast` | input | 1 | 未声明 | control | i_axi_rlast |
| `i_axi_rvalid` | input | 1 | 未声明 | control | i_axi_rvalid |
| `o_axi_rready` | output | 1 | 未声明 | control | o_axi_rready |
| `o_fault` | output | 1 | 未声明 | control | o_fault |
| `o_completed` | output | 32 | 未声明 | data | o_completed |

## 5. 周期行为与延迟

- Single-outstanding AXI4 master; aligned 32-bit single-beat INCR, ID=0 and full strobes tied at top.
- 392-bit request words: payload[319:0], opcode[327:320], argument[335:328], read flag[336], register[359:344], tag[391:360].
- Commands stage 15 register writes, poll completion, read result/tag/opcode, verify ownership, then POP. Separate Voice and FX sequences owned here, epoch=1.
- 136-bit response: result128 and transport status8. Result held under backpressure. AXI channel VALID remains asserted until handshake.
- Bus response errors or watchdog set a sticky fault; no new command accepted. Watchdog does not withdraw an outstanding AXI beat. Reset is required to recover.

## 6. WaveDrom 时序图

### 流水接纳与反压

事件或命令稳定保持至握手，执行后完成返回；音频按固定帧节拍独立运行。示意图不表示绝对运算周期。

![流水接纳与反压](waveforms/SynthAxiMaster_stream.svg)

- WaveJSON：[SynthAxiMaster_stream.json5](waveforms/SynthAxiMaster_stream.json5)

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

- 规格模块：`SynthAxiMaster`
- RTL 路径：`rtl/SynthAxiMaster.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
