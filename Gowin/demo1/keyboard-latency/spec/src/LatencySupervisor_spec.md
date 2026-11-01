# LatencySupervisor 模块规范

> RTL: `src/LatencySupervisor.v`

## 1. 模块目的

每键一个监测事务，8状态：空闲、扫描确认、等待提交、等待非零声部、等待非零PCM、等待加载、等待DAC左字锁存、完成。

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
| `i_clear` | input | 1 | 未声明 | data | i clear |
| `i_initialized` | input | 1 | 未声明 | data | i initialized |
| `i_sample_valid` | input | 1 | 未声明 | data | i sample valid |
| `i_sample_key` | input | 5 | 未声明 | data | i sample key |
| `i_candidate` | input | 1 | 未声明 | data | i candidate |
| `i_confirm` | input | 1 | 未声明 | data | i confirm |
| `i_cancel` | input | 1 | 未声明 | data | i cancel |
| `i_physical` | input | 32 | 未声明 | data | i physical |
| `i_effective` | input | 32 | 未声明 | data | i effective |
| `i_commit` | input | 1 | 未声明 | data | i commit |
| `i_commit_key` | input | 5 | 未声明 | data | i commit key |
| `i_result_valid` | input | 1 | 未声明 | data | i result valid |
| `i_result_key` | input | 5 | 未声明 | data | i result key |
| `i_result_sample` | input | 32 | 未声明 | data | i result sample |
| `i_pcm_valid` | input | 1 | 未声明 | data | i pcm valid |
| `i_pcm_nonzero` | input | 1 | 未声明 | data | i pcm nonzero |
| `i_frame_load` | input | 1 | 未声明 | data | i frame load |
| `i_dac_left_latch` | input | 1 | 未声明 | data | i dac left latch |
| `o_payload` | output | 880 | 未声明 | data | o payload |

## 5. 周期行为与延迟

- 每键一个监测事务，8状态：空闲、扫描确认、等待提交、等待非零声部、等待非零PCM、等待加载、等待DAC左字锁存、完成。
- 物理起点为首次ADC越过按下门限，确认在第二次扫描；远程起点为FPGA内部有效gate上升沿，不含主机/串口时间。
- 记录第一次声部返回和后续选中的非零返回；零PCM继续等待，实际加载该帧后在PT8211左声道锁存沿结束。
- 分段总和=扫描确认+事件排队+首次计算+非零起音等待+输出等待；输出等待中包含单独列出的混音耗时。
- 32位50MHz时间戳模减，约85.9秒回绕；事务1秒超时。默认预算10ms，不改变音频节拍。
- 全部事件与原始时间戳先寄存一拍；逐键快照→差值计算→发布；代号校验丢弃旧事务。32键同时完成最多36拍发布完；统计读出时间不计入延迟。
- 扫描周期使用共享减法器；PCM/DAC时间戳按帧共享，完成批次必须在下一次相隔1024拍的DAC左字锁存前排空。
- 新起音覆盖未完成旧事务并累计覆盖计数；每键8位覆盖暂存计数饱和255，每32拍汇总一次。
- 最小、最大、64位和、完成数、物理/远程数、超预算、超时、取消候选及pending位图通过固定小端字段发布。
- 没有声学回采；其他声部的混音和非零数据不能保证目标音符已达到可闻响度。

## 6. WaveDrom 时序图

### 采集到数字起音

概念时序，扫描等待与音频帧间隔被压缩；所有时间戳来自同一50MHz计数器。

![采集到数字起音](waveforms/LatencySupervisor_onset.svg)

- WaveJSON：[LatencySupervisor_onset.json5](waveforms/LatencySupervisor_onset.json5)

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

- 规格模块：`LatencySupervisor`
- RTL 路径：`src/LatencySupervisor.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
