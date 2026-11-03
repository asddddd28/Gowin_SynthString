# SynthTouchPerformance 模块规范

> RTL: `rtl/SynthTouchPerformance.v`

## 1. 模块目的

模式0强度、1音高、2Cutoff、3吉他。i_next_mode单拍递增一次；UART kind3 0x30..0x33提供能力、原子配置和状态。

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
| `i_next_mode` | input | 1 | 未声明 | data | i_next_mode |
| `i_silent` | input | 1 | 未声明 | data | i_silent |
| `i_update` | input | 2 | 未声明 | data | i_update |
| `i_touch` | input | 2 | 未声明 | data | i_touch |
| `i_x` | input | 20 | 未声明 | data | i_x |
| `i_y` | input | 20 | 未声明 | data | i_y |
| `i_error` | input | 16 | 未声明 | data | i_error |
| `i_pressed` | input | 32 | 未声明 | data | i_pressed |
| `i_delivered` | input | 32 | 未声明 | data | i_delivered |
| `i_keys_idle` | input | 1 | 未声明 | data | i_keys_idle |
| `o_pressed` | output | 32 | 未声明 | data | o_pressed |
| `o_mode` | output | 2 | 未声明 | data | o_mode |
| `o_gain` | output | 18 | 未声明 | data | o_gain |
| `o_pitch` | output | 32 | 未声明 | data | o_pitch |
| `o_cutoff` | output | 20 | 未声明 | data | o_cutoff |
| `o_cutoff_active` | output | 1 | 未声明 | data | o_cutoff_active |
| `i_request` | input | 1 | 未声明 | data | i_request |
| `i_opcode` | input | 8 | 未声明 | data | i_opcode |
| `i_argument` | input | 8 | 未声明 | data | i_argument |
| `i_words` | input | 64 | 未声明 | data | i_words |
| `o_response_valid` | output | 1 | 未声明 | data | o_response_valid |
| `o_response` | output | 136 | 未声明 | data | o_response |

## 5. 周期行为与延迟

- 模式0强度、1音高、2Cutoff、3吉他。i_next_mode单拍递增一次；UART kind3 0x30..0x33提供能力、原子配置和状态。
- 1kHz共享乘法器计算(X-Y)×范围；音高查256×18 exp2 ROM，三个目标用1/8一阶平滑，每毫秒更新一次。松手/过期40ms/错误恢复到中性。
- 增益Q16的18位无符号数、音高Q26有符号频率增量、Cutoff20位有符号对数索引；配置上限100%、12半音、6oct。左板优先连续调制。
- 四根横弦Y=128/384/640/896，滞回20，冷却12ms，每板独立运动历史。首次落指、方向设置更改、模式更改、断流不拨弦。
- 每行8键取最右侧按住键，空行静音。每行一个pending目标；先清旧键，等待i_keys_idle且i_delivered==当前门控图，再重发，合并快速重复请求并计数。
- 进入/离开吉他停止旧实体键；离开时已按键抑制到释放。连续调制模式之间切换不停止已按键。校准silent强制不发声。

## 6. WaveDrom 时序图

### 触摸事件与调制提交

触摸采集在系统域提交，调制每毫秒平滑；音频帧独立执行，NoteOff确认之后才重新起音。

![触摸事件与调制提交](waveforms/SynthTouchPerformance_touch.svg)

- WaveJSON：[SynthTouchPerformance_touch.json5](waveforms/SynthTouchPerformance_touch.json5)

## 7. 边界、反压与错误

- 复位、数据过期、触点跳变、重复包、在途按键命令、方向与模式切换、空行。

## 8. CDC 与综合约束

- 50MHz系统域；实时控制不依赖串口；ROM由touch_model.py生成。

## 9. 验证与验收

- touch/model/run_simulations.py:位置/失联/四模式/右侧优先/重触发完成握手。
- tb_touch_voice5120帧逐样本等效；tb_touch_filter4096帧；tb_touch_system真实UART/ADC/PT8211通路。

## 10. 可追溯性

- 规格模块：`SynthTouchPerformance`
- RTL 路径：`rtl/SynthTouchPerformance.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
