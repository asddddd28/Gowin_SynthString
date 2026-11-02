# tb_axi_lfo 模块规范

> RTL: `sim/tb_axi_lfo.v`

## 1. 模块目的

Three actual compiled LFO example patches via AXI; persistent PCM, global/local lifetime, duplicate NoteOn, exact B2 replay and invalid requests.

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "clk", "edge": "posedge", "frequency_hz": 50000000}`
- 复位：`{"name": "rstn", "active": "low", "style": "asynchronous"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `o_done` | output | 1 | 未声明 | data | All self-checking cases completed; observable by an enclosing simulation fixture. |

## 5. 周期行为与延迟

- Three actual compiled LFO example patches via AXI; persistent PCM, global/local lifetime, duplicate NoteOn, exact B2 replay and invalid requests.

## 6. WaveDrom 时序图

### 任务提交与结果保持

输入握手移交所有权；结果等待消费时数据和事务身份保持。精确延迟以行为合同为准。

![任务提交与结果保持](waveforms/tb_axi_lfo_flow.svg)

- WaveJSON：[tb_axi_lfo_flow.json5](waveforms/tb_axi_lfo_flow.json5)

## 7. 边界、反压与错误

- backpressure and bubbles
- full and empty queues
- reset with in-flight tasks
- invalid stage or operation or bus request

## 8. CDC 与综合约束

- Simulation-only testbench. Actual completion output is part of this explicit contract. Design RTL specifications are source-cross-checked.

## 9. 验证与验收

- Three actual compiled LFO example patches via AXI; persistent PCM, global/local lifetime, duplicate NoteOn, exact B2 replay and invalid requests.

## 10. 可追溯性

- 规格模块：`tb_axi_lfo`
- RTL 路径：`sim/tb_axi_lfo.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
