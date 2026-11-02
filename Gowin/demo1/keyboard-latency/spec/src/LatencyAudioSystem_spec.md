# LatencyAudioSystem 模块规范

> RTL: `src/LatencyAudioSystem.v`

## 1. 模块目的

复用原32声部多核合成与响度；仅增加监测输出，不改变音频数据或背压。

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_clk", "edge": "posedge", "period_ns": 10}`
- 复位：`{"name": "i_rstn", "active": "low", "style": "asynchronous", "values": "全局清除任务、相位包络滤波状态，保留波表RAM；外部同步释放"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | 未声明 | clock | 统一计算时钟 |
| `i_rstn` | input | 1 | 未声明 | reset | 全系统低有效复位，释放须同步 |
| `i_run` | input | 1 | 未声明 | data | 配置结束后启动音频；只在空闲时停止 |
| `i_cfg_valid` | input | 1 | 未声明 | data | 源端持有完整声部配置 |
| `o_cfg_ready` | output | 1 | 未声明 | data | 仅空闲帧接收配置 |
| `i_cfg_voice` | input | 5 | 未声明 | data | 目标声部索引 |
| `i_cfg_data` | input | 512 | 未声明 | data | 音色参数和一次性门控事件 |
| `i_wave_valid` | input | 1 | 未声明 | data | 波表上传字有效 |
| `o_wave_ready` | output | 1 | 未声明 | data | 空闲时允许更新波表 |
| `i_wave_frame` | input | 1 | 未声明 | data | 选择波表的A或B帧 |
| `i_wave_address` | input | 11 | 未声明 | data | 银行位及1024点地址 |
| `i_wave_data` | input | 16 | 未声明 | data | 有符号波表采样 |
| `o_pcm_valid` | output | 1 | 未声明 | data | 完整混音帧可消费 |
| `o_pcm_left` | output | 24 | 未声明 | data | 限幅后的左声道PCM |
| `o_pcm_right` | output | 24 | 未声明 | data | 首版复制单声道到右声道 |
| `o_busy` | output | 1 | 未声明 | data | 当前音频帧尚未完全退役 |
| `o_overrun` | output | 1 | 未声明 | data | 忙时采样触发丢失的粘滞标志 |
| `o_fault` | output | 1 | 未声明 | data | 返回身份或算法错误，需要复位 |
| `o_frame_cycles` | output | 16 | 未声明 | data | 最近完成帧的计算周期数 |
| `o_result_valid` | output | 1 | 未声明 | data | 一个有效声部尾部结果提交 |
| `o_result_voice` | output | 5 | 未声明 | data | 本次提交所属声部 |
| `o_result_data` | output | 192 | 未声明 | data | 完整音频与滤波新状态 |
| `o_sample_tick` | output | 1 | 未声明 | data | 音频帧节拍监测 |
| `o_bclk` | output | 1 | 未声明 | data | 串行位时钟 |
| `o_lrclk` | output | 1 | 未声明 | data | 左右声道选择 |
| `o_sdata` | output | 1 | 未声明 | data | I2S音频输出 |
| `o_mclk` | output | 1 | 未声明 | data | 主音频时钟 |
| `o_underrun` | output | 1 | 未声明 | data | I2S缺帧粘滞标志 |
| `i_volume` | input | 4 | 未声明 | data | 主音量0至8 |
| `o_active_count` | output | 6 | 未声明 | data | ADSR非空闲声部数，包括释音 |
| `o_gain` | output | 19 | 未声明 | data | 平滑后的Q16增益 |
| `o_input_peak` | output | 24 | 未声明 | data | 处理前采样峰值保持 |
| `o_output_peak` | output | 24 | 未声明 | data | 处理后采样峰值保持 |
| `o_clips` | output | 32 | 未声明 | data | 保护限幅累计次数 |
| `o_stages` | output | 7 | 未声明 | data | 已提交阶段累计位图 |
| `o_wave_peak` | output | 32 | 未声明 | data | 振荡波形绝对峰值 |
| `o_mod_peak` | output | 32 | 未声明 | data | AM输出绝对峰值 |
| `o_env_peak` | output | 18 | 未声明 | data | 包络整数峰值 |
| `o_frame_load` | output | 1 | 未声明 | data | o frame load |
| `o_dac_left_latch` | output | 1 | 未声明 | data | o dac left latch |
| `o_pcm_nonzero` | output | 1 | 未声明 | data | o pcm nonzero |

## 5. 周期行为与延迟

- 复用原32声部多核合成与响度；仅增加监测输出，不改变音频数据或背压。
- 输出实际串行器加载帧与左声道锁存脉冲；o_pcm_nonzero取24→16位舍入后的非零判断。

## 6. WaveDrom 时序图

### 采集到数字起音

概念时序，扫描等待与音频帧间隔被压缩；所有时间戳来自同一50MHz计数器。

![采集到数字起音](waveforms/LatencyAudioSystem_onset.svg)

- WaveJSON：[LatencyAudioSystem_onset.json5](waveforms/LatencyAudioSystem_onset.json5)

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

- 规格模块：`LatencyAudioSystem`
- RTL 路径：`src/LatencyAudioSystem.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
