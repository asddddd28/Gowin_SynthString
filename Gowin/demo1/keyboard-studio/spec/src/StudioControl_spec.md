# StudioControl 模块规范

> RTL: `src/StudioControl.v`

## 1. 模块目的

长包71字节：A5 C3 op seq key payload64 CRC16小端；CRC-CCITT初始化FFFF，覆盖头及数据。

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
| `i_rx_valid` | input | 1 | 未声明 | data | i rx valid |
| `i_rx_error` | input | 1 | 未声明 | data | i rx error |
| `i_rx_data` | input | 8 | 未声明 | data | i rx data |
| `o_ascii_valid` | output | 1 | 未声明 | data | o ascii valid |
| `o_ascii_data` | output | 8 | 未声明 | data | o ascii data |
| `o_patch_valid` | output | 1 | 未声明 | data | o patch valid |
| `i_patch_ready` | input | 1 | 未声明 | data | i patch ready |
| `o_patch_key` | output | 5 | 未声明 | data | o patch key |
| `o_patch_data` | output | 512 | 未声明 | data | o patch data |
| `o_wave_valid` | output | 1 | 未声明 | data | o wave valid |
| `i_wave_ready` | input | 1 | 未声明 | data | i wave ready |
| `o_wave_frame` | output | 1 | 未声明 | data | o wave frame |
| `o_wave_address` | output | 11 | 未声明 | data | o wave address |
| `o_wave_data` | output | 16 | 未声明 | data | o wave data |
| `o_remote` | output | 32 | 未声明 | data | o remote |
| `o_velocity` | output | 224 | 未声明 | data | o velocity |
| `o_volume` | output | 4 | 未声明 | data | o volume |
| `o_volume_valid` | output | 1 | 未声明 | data | o volume valid |
| `o_ack_seq` | output | 8 | 未声明 | data | o ack seq |
| `o_ack_op` | output | 8 | 未声明 | data | o ack op |
| `o_ack_status` | output | 8 | 未声明 | data | o ack status |
| `o_ack_key` | output | 8 | 未声明 | data | o ack key |
| `o_ack_crc` | output | 16 | 未声明 | data | o ack crc |
| `o_commits` | output | 32 | 未声明 | data | o commits |

## 5. 周期行为与延迟

- 长包71字节：A5 C3 op seq key payload64 CRC16小端；CRC-CCITT初始化FFFF，覆盖头及数据。
- 短包8字节：A5 C4 op seq key value CRC16小端；仅演奏、音量、心跳命令允许。载荷不解释为ASCII。
- 仅CRC与参数范围通过后提交；配置等待Bridge接受才ACK，波表块等待32个写握手才ACK。
- 20ms字节超时取消残包；1.5秒无有效主机包释放远程键，实体键不受影响。
- 64块完成位图保护双帧波表可用性；第0块重置位图，失败需重新完整上传。

## 6. WaveDrom 时序图

### 参数与任务提交

有效期间保持完整事务，接受后才发射或确认；算术延迟见行为合同。

![参数与任务提交](waveforms/StudioControl_handshake.svg)

- WaveJSON：[StudioControl_handshake.json5](waveforms/StudioControl_handshake.json5)

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

- 规格模块：`StudioControl`
- RTL 路径：`src/StudioControl.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
