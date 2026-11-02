# I2cRegister 模块规范

> RTL: `src/I2cRegister.v`

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
| `i_start` | input | 1 | 未声明 | data | i_start; see behavior contract |
| `i_read` | input | 1 | 未声明 | data | i_read; see behavior contract |
| `i_address` | input | 7 | 未声明 | data | i_address; see behavior contract |
| `i_register` | input | 8 | 未声明 | data | i_register; see behavior contract |
| `i_write` | input | 8 | 未声明 | data | i_write; see behavior contract |
| `i_count` | input | 6 | 未声明 | data | i_count; see behavior contract |
| `o_done` | output | 1 | 未声明 | data | o_done; see behavior contract |
| `o_error` | output | 2 | 未声明 | data | o_error; see behavior contract |
| `o_valid` | output | 1 | 未声明 | data | o_valid; see behavior contract |
| `o_index` | output | 6 | 未声明 | data | o_index; see behavior contract |
| `o_data` | output | 8 | 未声明 | data | o_data; see behavior contract |
| `io_scl` | inout | 1 | 未声明 | data | io_scl; see behavior contract |
| `io_sda` | inout | 1 | 未声明 | data | io_sda; see behavior contract |

## 5. 周期行为与延迟

- Register write or 1..42 byte read; repeated START and final NACK; error 1=NACK,2=timeout/arbitration.
- One-cycle start accepted only in idle. Done pulse finalizes transaction. Read valid strobes may precede a failure and must be staged by caller.

## 6. WaveDrom 时序图

### Register read

Conceptual START-write-address-register-repeatedSTART-read-data-NACK-STOP; not measured timing.

![Register read](waveforms/I2cRegister_burst.svg)

- WaveJSON：[I2cRegister_burst.json5](waveforms/I2cRegister_burst.json5)

## 7. 边界、反压与错误

- One missing sensor does not block the other.
- Clock stuck low returns timeout; stale payload never implies valid touch.
- Reset aborts UART and releases both buses.

## 8. CDC 与综合约束

- 50MHz. Top C_DIVIDER999 yields nominal10kHz for initial hardware diagnosis; external pullups still required.
- C_TIMEOUT5000000 at top (100ms) exceeds42-byte transaction at10kHz. Independent bus masters.

## 9. 验证与验收

- Behavioral5A/5C address scan, exact configuration and burst byte order.
- NACK and stuck-clock isolation, recovery; ECR corruption detects/reconfigures sensor.
- 18 complete UART packets independently checked for framing/CRC; termination cuts an additional32-byte tail.
- App52 regression tests; real I2C register readback and zero-sample evidence separately recorded.

## 10. 可追溯性

- 规格模块：`I2cRegister`
- RTL 路径：`src/I2cRegister.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
