# GuitarTracker 模块规范

> RTL: `src/GuitarTracker.v`

## 1. 模块目的

未提供模块目的。

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_clk", "frequency_mhz": 50, "edge": "posedge"}`
- 复位：`{"name": "i_rstn", "active": "low", "synchronous": false, "description": "Asynchronous assertion, top synchronizes release"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | 未声明 | clock | i_clk; detailed fields in requirements.md |
| `i_rstn` | input | 1 | 未声明 | reset | i_rstn; detailed fields in requirements.md |
| `i_milliseconds` | input | 32 | 未声明 | data | i_milliseconds; detailed fields in requirements.md |
| `i_raw` | input | 336 | 未声明 | data | i_raw; detailed fields in requirements.md |
| `i_sequence` | input | 16 | 未声明 | data | i_sequence; detailed fields in requirements.md |
| `i_error` | input | 8 | 未声明 | data | i_error; detailed fields in requirements.md |
| `o_event` | output | 1 | 未声明 | data | o_event; detailed fields in requirements.md |
| `o_mask` | output | 6 | 未声明 | data | o_mask; detailed fields in requirements.md |
| `o_flags` | output | 4 | 未声明 | data | o_flags; detailed fields in requirements.md |
| `o_x` | output | 10 | 未声明 | data | o_x; detailed fields in requirements.md |
| `o_y` | output | 10 | 未声明 | data | o_y; detailed fields in requirements.md |
| `o_sequence` | output | 16 | 未声明 | data | o_sequence; detailed fields in requirements.md |
| `o_time` | output | 32 | 未声明 | data | o_time; detailed fields in requirements.md |

## 5. 周期行为与延迟

- On each new sequence, scan12 electrodes and compute two weighted centroids with 10-cycle restoring division.
- Accept one contiguous cluster on each axis; no initial-contact event. Hysteresis20/1024,12ms cooldown,40ms continuity timeout.
- Emit all crossed lines256/512/768 as a6bit mask with two direction flags. Processing finishes within50 clocks.

## 6. WaveDrom 时序图

### Sample to event

Conceptual pipeline, compressed computation interval, not measured timing.

![Sample to event](waveforms/GuitarTracker_crossing.svg)

- WaveJSON：[GuitarTracker_crossing.json5](waveforms/GuitarTracker_crossing.json5)

## 7. 边界、反压与错误

- Reset clears pending events; invalid samples invalidate contact; simultaneous left/right events preserved.

## 8. CDC 与综合约束

- Single clock domain; bounded finite registers; source protocol in requirements.md

## 9. 验证与验收

- tb_guitar_tracker: centroid, multi-line, reverse, dwell, lift, faults; tb_guitar_queue: full simultaneous operation; tb_touchpad_guitar: pin-level I2C/UART.

## 10. 可追溯性

- 规格模块：`GuitarTracker`
- RTL 路径：`src/GuitarTracker.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
