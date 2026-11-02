# KeyboardThresholds 模块规范

> RTL: `src/KeyboardThresholds.v`

## 1. 模块目的

ROM由已保存的32键实测校准产生，包含方向、50%按下门限和35%释放门限。

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
| `i_key` | input | 5 | 未声明 | data | 零基键号 |
| `i_raw` | input | 12 | 未声明 | data | ADC结果 |
| `i_valid` | input | 1 | 未声明 | data | 采样提交 |
| `o_pressed` | output | 32 | 未声明 | data | 迟滞判键结果 |

## 5. 周期行为与延迟

- ROM由已保存的32键实测校准产生，包含方向、50%按下门限和35%释放门限。
- 同一键连续两个有效样本越过当前状态的门限才翻转；任何不满足样本清除该键资格。
- 复位清除按键及资格，保留只读门限。

## 6. WaveDrom 时序图

### 接口概念时序

为事件顺序示意，间隔不按比例；实际周期见仿真与构建报告。

![接口概念时序](waveforms/KeyboardThresholds_pipeline.svg)

- WaveJSON：[KeyboardThresholds_pipeline.json5](waveforms/KeyboardThresholds_pipeline.json5)

## 7. 边界、反压与错误

- 复位后按住键
- 门限附近抖动
- 事件遇到音频忙帧
- 多个键同时变化

## 8. CDC 与综合约束

- 固定32个逻辑声部；50MHz；板型31004；只用于本轮SRAM诊断验证。

## 9. 验证与验收

- 上电静音
- 跨行多键按下和释放
- ADC至DAC引脚解码
- 配置反压保持
- 命令自测与物理键隔离

## 10. 可追溯性

- 规格模块：`KeyboardThresholds`
- RTL 路径：`src/KeyboardThresholds.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
