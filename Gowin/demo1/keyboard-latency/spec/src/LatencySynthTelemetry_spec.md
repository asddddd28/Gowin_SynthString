# LatencySynthTelemetry 模块规范

> RTL: `src/LatencySynthTelemetry.v`

## 1. 模块目的

192字节协议4；头A5 5A 04 C0，0..77保留Studio公共字段；80..189为110字节延迟快照。

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
| `i_latency` | input | 880 | 未声明 | data | i latency |

## 5. 周期行为与延迟

- 192字节协议4；头A5 5A 04 C0，0..77保留Studio公共字段；80..189为110字节延迟快照。
- 190=XOR(0..189)，191=CR；整包发送期间快照不可变；约10Hz触发加串行发送耗时。
- 命令仍使用原Studio长/短CRC16包。延迟统计L为包外ASCII命令。

## 6. WaveDrom 时序图

### 采集到数字起音

概念时序，扫描等待与音频帧间隔被压缩；所有时间戳来自同一50MHz计数器。

![采集到数字起音](waveforms/LatencySynthTelemetry_onset.svg)

- WaveJSON：[LatencySynthTelemetry_onset.json5](waveforms/LatencySynthTelemetry_onset.json5)

## 7. 边界、反压与错误

- 32键同时完成
- 计数回绕
- 候选取消
- 静音与慢起音
- 覆盖与超时并发
- 清零时仍按住键

## 8. CDC 与综合约束

- 50MHz同一时钟域，异步低有效复位，顶层同步释放。
- 监测无音频控制反馈；一次事件窗口小于32位时间戳周期，默认1秒超时。

## 9. 验证与验收

- 独立时间差模型
- 逐分段确定值比较
- 真实ADC和PT8211 WS边沿关联
- 协议4全部分包边界及坏包恢复
- Gowin时序与板上串口/听感

## 10. 可追溯性

- 规格模块：`LatencySynthTelemetry`
- RTL 路径：`src/LatencySynthTelemetry.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
