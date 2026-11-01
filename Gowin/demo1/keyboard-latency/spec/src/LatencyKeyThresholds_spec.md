# LatencyKeyThresholds 模块规范

> RTL: `src/LatencyKeyThresholds.v`

## 1. 模块目的

沿用原门限ROM、迟滞和连续两次完整扫描确认，音频事件行为不变。

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
| `i_key` | input | 5 | 未声明 | data | i key |
| `i_raw` | input | 12 | 未声明 | data | i raw |
| `i_valid` | input | 1 | 未声明 | data | i valid |
| `o_candidate` | output | 1 | 未声明 | data | o candidate |
| `o_confirm` | output | 1 | 未声明 | data | o confirm |
| `o_cancel` | output | 1 | 未声明 | data | o cancel |
| `o_pressed` | output | 32 | 未声明 | data | o pressed |

## 5. 周期行为与延迟

- 沿用原门限ROM、迟滞和连续两次完整扫描确认，音频事件行为不变。
- 候选、确认和取消脉冲均在相应ADC样本握手沿有效，只针对按下过程；释放仍按原逻辑处理。

## 6. WaveDrom 时序图

### 采集到数字起音

概念时序，扫描等待与音频帧间隔被压缩；所有时间戳来自同一50MHz计数器。

![采集到数字起音](waveforms/LatencyKeyThresholds_onset.svg)

- WaveJSON：[LatencyKeyThresholds_onset.json5](waveforms/LatencyKeyThresholds_onset.json5)

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

- 规格模块：`LatencyKeyThresholds`
- RTL 路径：`src/LatencyKeyThresholds.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
