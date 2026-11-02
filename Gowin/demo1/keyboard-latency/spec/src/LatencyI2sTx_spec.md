# LatencyI2sTx 模块规范

> RTL: `src/LatencyI2sTx.v`

## 1. 模块目的

沿用原PT8211/I2S音频位流、舍入和待播放缓冲；观察口不影响功能。

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
| `i_sample_valid` | input | 1 | 未声明 | data | i sample valid |
| `i_left` | input | 24 | 未声明 | data | i left |
| `i_right` | input | 24 | 未声明 | data | i right |
| `o_sample_tick` | output | 1 | 未声明 | data | o sample tick |
| `o_bclk` | output | 1 | 未声明 | data | o bclk |
| `o_lrclk` | output | 1 | 未声明 | data | o lrclk |
| `o_sdata` | output | 1 | 未声明 | data | o sdata |
| `o_frame_load` | output | 1 | 未声明 | data | o frame load |
| `o_dac_left_latch` | output | 1 | 未声明 | data | o dac left latch |
| `o_mclk` | output | 1 | 未声明 | data | o mclk |
| `o_underrun` | output | 1 | 未声明 | data | o underrun |

## 5. 周期行为与延迟

- 沿用原PT8211/I2S音频位流、舍入和待播放缓冲；观察口不影响功能。
- o_frame_load在真实帧边界且有新PCM可加载时有效，含同拍旁路。
- PT8211模式下o_dac_left_latch在cnt_frame=512-C_FRAME_STEP且该播放帧有效时有效；这个沿使WS从高转低。
- 板级只使用PT8211、C_FRAME_STEP=1；锁存是数字终点，不代表模拟输出无额外延迟。

## 6. WaveDrom 时序图

### 采集到数字起音

概念时序，扫描等待与音频帧间隔被压缩；所有时间戳来自同一50MHz计数器。

![采集到数字起音](waveforms/LatencyI2sTx_onset.svg)

- WaveJSON：[LatencyI2sTx_onset.json5](waveforms/LatencyI2sTx_onset.json5)

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

- 规格模块：`LatencyI2sTx`
- RTL 路径：`src/LatencyI2sTx.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
