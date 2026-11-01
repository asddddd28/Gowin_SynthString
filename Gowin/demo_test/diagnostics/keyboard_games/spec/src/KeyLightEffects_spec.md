# KeyLightEffects 模块规范

> RTL: `src/KeyLightEffects.v`

## 1. 模块目的

未提供模块目的。

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_clk", "frequency_mhz": 50, "edge": "posedge"}`
- 复位：`{"name": "i_rstn", "active": "low", "synchronous": false, "description": "Async assertion; synchronous release provided by top"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | 未声明 | clock | 50 MHz rising-edge clock |
| `i_rstn` | input | 1 | 未声明 | reset | Active-low reset; top synchronizes release |
| `i_press` | input | 32 | 未声明 | data | press |
| `i_clear` | input | 1 | 未声明 | data | clear |
| `i_mode` | input | 4 | 未声明 | data | mode |
| `i_direction` | input | 1 | 未声明 | data | direction |
| `i_frame_tick` | input | 1 | 未声明 | data | frame tick |
| `i_pixel` | input | 5 | 未声明 | data | pixel |
| `o_grb` | output | 24 | 未声明 | data | grb |

## 5. 周期行为与延迟

- At frame tick snapshot animation state; combinational GRB lookup stays consistent throughout frame.
- Mode1 uses32 independent50-frame timers. New press restarts its timer; holding does not repeat.
- Mode2 Manhattan ripple and mode4 same-row/column cross: age/3 radius, one-cell trail,36-frame lifetime.
- Mode3 global sweep uses age/2, horizontal22-frame or vertical14-frame lifetime.
- New press interrupts modes2/3/4, advances color; simultaneous event bits use highest index center.

## 6. WaveDrom 时序图

### KeyLightEffects operation

Conceptual phases; exact cycle contract and verification are specified above.

![KeyLightEffects operation](waveforms/KeyLightEffects_operation.svg)

- WaveJSON：[KeyLightEffects_operation.json5](waveforms/KeyLightEffects_operation.json5)

## 7. 边界、反压与错误

- Reset aborts active operation; valid/configured state cleared.
- Mode0 off; all colors <=32/255; frame tick50Hz for one-second timers.
- Clear removes active effects; out-of-bounds propagation clips at matrix edge.

## 8. CDC 与综合约束

- Mode0 off; all colors <=32/255; frame tick50Hz for one-second timers.
- Clear removes active effects; out-of-bounds propagation clips at matrix edge.

## 9. 验证与验收

- Independent Python pixel oracle checks215 frames/6880 pixels, retrigger, interruption, both sweep axes, boundary clipping and off.

## 10. 可追溯性

- 规格模块：`KeyLightEffects`
- RTL 路径：`src/KeyLightEffects.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
