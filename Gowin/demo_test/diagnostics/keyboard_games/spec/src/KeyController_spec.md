# KeyController 模块规范

> RTL: `src/KeyController.v`

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
| `i_command` | input | 80 | 未声明 | data | command |
| `i_command_valid` | input | 1 | 未声明 | data | command valid |
| `i_crc_error` | input | 1 | 未声明 | data | crc error |
| `i_key` | input | 5 | 未声明 | data | key |
| `i_raw` | input | 12 | 未声明 | data | raw |
| `i_sample_valid` | input | 1 | 未声明 | data | sample valid |
| `o_ack` | output | 1 | 未声明 | data | ack |
| `o_ack_seq` | output | 8 | 未声明 | data | ack seq |
| `o_ack_result` | output | 8 | 未声明 | data | ack result |
| `o_configured` | output | 1 | 未声明 | data | configured |
| `o_generation` | output | 8 | 未声明 | data | generation |
| `o_mode` | output | 4 | 未声明 | data | mode |
| `o_direction` | output | 1 | 未声明 | data | direction |
| `o_pressed` | output | 32 | 未声明 | data | pressed |
| `o_press_pulse` | output | 32 | 未声明 | data | press pulse |
| `o_clear_effect` | output | 1 | 未声明 | data | clear effect |
| `o_game_start` | output | 1 | 未声明 | data | One-cycle start for a fresh accepted command41 |
| `o_game_stop` | output | 1 | 未声明 | data | One-cycle stop on42, ordinary effect or calibration commit |
| `o_game_type` | output | 2 | 未声明 | data | 1snake2mole3piano |

## 5. 周期行为与延迟

- BEGIN resets inactive-bank write mask; KEY writes one validated calibration; COMMIT swaps only a complete bank.
- Increasing/decreasing ADC polarities; hysteresis with two consecutive threshold-crossing samples.
- Press pulse only on qualified released-to-pressed transition. Commit clears all recognition state.
- Last identical sequence/payload returns cached result without executing again; collision returns error7.
- Commands produce a one-cycle ACK; mode change clears effects.
- Command41 starts selected game and mode5 only after calibration. Duplicate replay does not restart.
- Command42 restores chosen ordinary mode0..4; normal EFFECT/COMMIT stop current game.

## 6. WaveDrom 时序图

### KeyController operation

Conceptual phases; exact cycle contract and verification are specified above.

![KeyController operation](waveforms/KeyController_operation.svg)

- WaveJSON：[KeyController_operation.json5](waveforms/KeyController_operation.json5)

## 7. 边界、反压与错误

- Reset aborts active operation; valid/configured state cleared.
- All32 valid records required; endpoint span >=100; thresholds ordered inside endpoints.
- Active bank remains valid while staging; no nonvolatile storage; memories ignored before configured.
- Stop-and-wait host protocol. Commit overrides same-cycle sample.

## 8. CDC 与综合约束

- All32 valid records required; endpoint span >=100; thresholds ordered inside endpoints.
- Active bank remains valid while staging; no nonvolatile storage; memories ignored before configured.
- Stop-and-wait host protocol. Commit overrides same-cycle sample.

## 9. 验证与验收

- Invalid/incomplete commit, duplicate retry, both polarities, single spike, held-key no-repeat, hysteresis, reset.

## 10. 可追溯性

- 规格模块：`KeyController`
- RTL 路径：`src/KeyController.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
