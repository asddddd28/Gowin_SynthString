# MprScanner 模块规范

> RTL: `src/MprScanner.v`

## 1. 模块目的

未提供模块目的。

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_clk", "frequency_mhz": 50, "edge": "posedge"}`
- 复位：`{"name": "i_rstn", "active": "low", "synchronous": false, "description": "Two-cycle synchronized release"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_clk` | input | 1 | 未声明 | clock | i_clk; see behavior contract |
| `i_rstn` | input | 1 | 未声明 | reset | i_rstn; see behavior contract |
| `io_scl` | inout | 1 | 未声明 | data | io_scl; see behavior contract |
| `io_sda` | inout | 1 | 未声明 | data | io_sda; see behavior contract |
| `o_raw` | output | 336 | 未声明 | data | o_raw; see behavior contract |
| `o_sequence` | output | 16 | 未声明 | data | o_sequence; see behavior contract |
| `o_address` | output | 7 | 未声明 | data | o_address; see behavior contract |
| `o_error` | output | 8 | 未声明 | data | o_error; see behavior contract |

## 5. 周期行为与延迟

- Configure 5C=10,5D=20,5E=8C; read 42 bytes continuously and atomically commit into FPGA registers.
- Verify configuration at initialization and every 128 samples; immediate error and retry on NACK/timeout.

## 6. WaveDrom 时序图

### Register read

Conceptual START-write-address-register-repeatedSTART-read-data-NACK-STOP; not measured timing.

![Register read](waveforms/MprScanner_burst.svg)

- WaveJSON：[MprScanner_burst.json5](waveforms/MprScanner_burst.json5)

## 7. 边界、反压与错误

- One missing sensor does not block the other.
- Clock stuck low returns timeout; stale payload never implies valid touch.
- Reset aborts UART and releases both buses.

## 8. CDC 与综合约束

- 50MHz;100kHz nominal I2C; external edge quality requires live validation.

## 9. 验证与验收

- Behavioral dual-sensor scan, NACK, stuck bus, ECR repair.

## 10. 可追溯性

- 规格模块：`MprScanner`
- RTL 路径：`src/MprScanner.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
