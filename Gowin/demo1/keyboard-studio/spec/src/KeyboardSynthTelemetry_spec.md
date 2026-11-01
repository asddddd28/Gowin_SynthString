# KeyboardSynthTelemetry 模块规范

> RTL: `src/KeyboardSynthTelemetry.v`

## 1. 模块目的

周期性锁存32字节原子状态快照，计算前30字节异或，最后字节0D。

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
| `i_clk` | input | 1 | 未声明 | clock | 50MHz统一计算时钟 |
| `i_rstn` | input | 1 | 未声明 | reset | 低有效复位，异步置位同步释放 |
| `i_frames` | input | 32 | 未声明 | data | 音频帧计数 |
| `i_pressed` | input | 32 | 未声明 | data | 物理键状态 |
| `i_delivered` | input | 32 | 未声明 | data | 提交键状态 |
| `i_nonzero` | input | 32 | 未声明 | data | 非零PCM计数 |
| `i_events` | input | 32 | 未声明 | data | 事件计数 |
| `i_cycles` | input | 16 | 未声明 | data | 合成周期 |
| `i_flags` | input | 8 | 未声明 | data | 错误及测试标志 |
| `i_key` | input | 5 | 未声明 | data | 最近键号 |
| `i_raw` | input | 12 | 未声明 | data | 最近ADC结果 |
| `o_uart_tx` | output | 1 | 未声明 | data | 115200 8N1输出 |
| `i_volume` | input | 4 | 未声明 | data | 主音量0至8 |
| `i_active_count` | input | 6 | 未声明 | data | ADSR非空闲声部数，包括释音 |
| `i_gain` | input | 19 | 未声明 | data | 平滑后的Q16增益 |
| `i_input_peak` | input | 24 | 未声明 | data | 处理前采样峰值保持 |
| `i_output_peak` | input | 24 | 未声明 | data | 处理后采样峰值保持 |
| `i_clips` | input | 32 | 未声明 | data | 保护限幅累计次数 |
| `i_stages` | input | 7 | 未声明 | data | 已提交阶段累计位图 |
| `i_wave_peak` | input | 32 | 未声明 | data | 振荡波形绝对峰值 |
| `i_mod_peak` | input | 32 | 未声明 | data | AM输出绝对峰值 |
| `i_env_peak` | input | 18 | 未声明 | data | 包络整数峰值 |
| `i_ack_seq` | input | 8 | 未声明 | data | i ack seq |
| `i_ack_op` | input | 8 | 未声明 | data | i ack op |
| `i_ack_status` | input | 8 | 未声明 | data | i ack status |
| `i_ack_key` | input | 8 | 未声明 | data | i ack key |
| `i_ack_crc` | input | 16 | 未声明 | data | i ack crc |
| `i_commits` | input | 32 | 未声明 | data | i commits |

## 5. 周期行为与延迟

- 80字节快照：A5 5A 03 50；0..61保持旧遥测布局。
- 62seq、63op、64status、65key、66..67CRC、68..71配置提交数、72..75能力位、76..77保留、78 XOR(0..77)、79=0D。
- 100ms周期锁存一次，发完整包后再锁存；ACK不是命令发送的本地回显。

## 6. WaveDrom 时序图

### 参数与任务提交

有效期间保持完整事务，接受后才发射或确认；算术延迟见行为合同。

![参数与任务提交](waveforms/KeyboardSynthTelemetry_handshake.svg)

- WaveJSON：[KeyboardSynthTelemetry_handshake.json5](waveforms/KeyboardSynthTelemetry_handshake.json5)

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

- 规格模块：`KeyboardSynthTelemetry`
- RTL 路径：`src/KeyboardSynthTelemetry.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
