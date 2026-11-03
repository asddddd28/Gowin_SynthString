# SynthTouchInput 模块规范

> RTL: `rtl/SynthTouchInput.v`

## 1. 模块目的

两套原有MprScanner/I2cRegister/OpenCores I2C引擎分别采集两块MPR121，错误互不影响。

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_clk", "edge": "posedge", "frequency_hz": 50000000}`
- 复位：`{"name": "i_rstn", "active": "low", "style": "asynchronous", "values": "all pipeline valid and output data/tag registers clear; external synchronous release"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | 未声明 | clock | i_clk |
| `i_rstn` | input | 1 | 未声明 | reset | i_rstn |
| `io_scl` | inout | 2 | 未声明 | data | io_scl |
| `io_sda` | inout | 2 | 未声明 | data | io_sda |
| `o_update` | output | 2 | 未声明 | data | o_update |
| `o_touch` | output | 2 | 未声明 | data | o_touch |
| `o_x` | output | 20 | 未声明 | data | o_x |
| `o_y` | output | 20 | 未声明 | data | o_y |
| `o_error` | output | 16 | 未声明 | data | o_error |

## 5. 周期行为与延迟

- 两套原有MprScanner/I2cRegister/OpenCores I2C引擎分别采集两块MPR121，错误互不影响。
- SCL/SDA为开漏，遵循demo_test引脚与初始化；无需IRQ，软件串口轮询不参与实时采集。
- 每块接一套TouchPosition；位置和更新脉冲都在50MHz系统域。

## 6. WaveDrom 时序图

### 触摸事件与调制提交

触摸采集在系统域提交，调制每毫秒平滑；音频帧独立执行，NoteOff确认之后才重新起音。

![触摸事件与调制提交](waveforms/SynthTouchInput_touch.svg)

- WaveJSON：[SynthTouchInput_touch.json5](waveforms/SynthTouchInput_touch.json5)

## 7. 边界、反压与错误

- 复位、数据过期、触点跳变、重复包、在途按键命令、方向与模式切换、空行。

## 8. CDC 与综合约束

- 50MHz系统域；实时控制不依赖串口；ROM由touch_model.py生成。

## 9. 验证与验收

- touch/model/run_simulations.py:位置/失联/四模式/右侧优先/重触发完成握手。
- tb_touch_voice5120帧逐样本等效；tb_touch_filter4096帧；tb_touch_system真实UART/ADC/PT8211通路。

## 10. 可追溯性

- 规格模块：`SynthTouchInput`
- RTL 路径：`rtl/SynthTouchInput.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
