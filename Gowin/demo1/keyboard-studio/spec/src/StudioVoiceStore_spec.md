# StudioVoiceStore 模块规范

> RTL: `src/StudioVoiceStore.v`

## 1. 模块目的

参数512位及384位状态按字段分同步RAM；读延迟一拍，调度器至少等待两拍预取。

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_clk", "edge": "posedge", "period_ns": 20}`
- 复位：`{"name": "i_rstn", "active": "low", "style": "asynchronous", "values": "取消事件和任务，键状态及计数清零"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | 未声明 | clock | i clk |
| `i_rstn` | input | 1 | 未声明 | reset | i rstn |
| `i_cfg_write` | input | 1 | 未声明 | data | i cfg write |
| `i_cfg_voice` | input | 5 | 未声明 | data | i cfg voice |
| `i_cfg_data` | input | 512 | 未声明 | data | i cfg data |
| `i_read_voice` | input | 5 | 未声明 | data | i read voice |
| `o_profile` | output | 512 | 未声明 | data | o profile |
| `o_state` | output | 384 | 未声明 | data | o state |
| `i_write` | input | 1 | 未声明 | data | i write |
| `i_write_voice` | input | 5 | 未声明 | data | i write voice |
| `i_write_stage` | input | 3 | 未声明 | data | i write stage |
| `i_write_data` | input | 192 | 未声明 | data | i write data |
| `i_event_consume` | input | 1 | 未声明 | data | i event consume |
| `i_event_voice` | input | 5 | 未声明 | data | i event voice |

## 5. 周期行为与延迟

- 参数512位及384位状态按字段分同步RAM；读延迟一拍，调度器至少等待两拍预取。
- 写回先寄存，再写RAM。每个状态字段仅一个写口；不复位RAM本体，启动配置bit482清零状态。
- bit483只写事件并保留发声参数。调制包络先读事件，振幅包络发射后消费一次性事件。

## 6. WaveDrom 时序图

### 参数与任务提交

有效期间保持完整事务，接受后才发射或确认；算术延迟见行为合同。

![参数与任务提交](waveforms/StudioVoiceStore_handshake.svg)

- WaveJSON：[StudioVoiceStore_handshake.json5](waveforms/StudioVoiceStore_handshake.json5)

## 7. 边界、反压与错误

- 复位取消旧任务
- 输出背压
- 32键复音
- CRC失败与残包
- 参数在释音中更新

## 8. CDC 与综合约束

- 50MHz单时钟域；异步低有效复位，板级同步释放。
- 新固件协议与旧96kHz Studio不兼容，必须核对版本3。

## 9. 验证与验收

- 完整ADC/UART/PT8211闭环
- 400个混合整数向量
- 配置ACK及短演奏包
- 无覆盖的活动参数快照
- Gowin综合实现时序

## 10. 可追溯性

- 规格模块：`StudioVoiceStore`
- RTL 路径：`src/StudioVoiceStore.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
