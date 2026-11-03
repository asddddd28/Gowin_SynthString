# AxiSynthEndpoint 模块规范

> RTL: `rtl/AxiSynthEndpoint.v`

## 1. 模块目的

新合成系统的精简AXI顶层，排除旧raw/context调试计算分支。

## 2. 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| — | — | 本模块没有可配置参数。 |

## 3. 时钟与复位

- 时钟：`{"name": "i_axi_aclk", "edge": "posedge", "frequency_hz": 50000000}`
- 复位：`{"name": "i_axi_arstn", "active": "low", "style": "asynchronous"}`

## 4. 接口信号规范

| 信号 | 方向 | 位宽 | 时钟域 | 语义角色 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `i_axi_aclk` | input | 1 | 未声明 | clock | AXI与内部计算共用时钟 |
| `i_axi_arstn` | input | 1 | 未声明 | reset | 清除总线事务与队列 |
| `i_s_axi_awid` | input | 4 | 未声明 | data | 请求awid |
| `i_s_axi_awaddr` | input | 16 | 未声明 | data | 请求awaddr |
| `i_s_axi_awlen` | input | 8 | 未声明 | data | 请求awlen |
| `i_s_axi_awsize` | input | 3 | 未声明 | data | 请求awsize |
| `i_s_axi_awburst` | input | 2 | 未声明 | data | 请求awburst |
| `i_s_axi_awlock` | input | 1 | 未声明 | data | 请求awlock |
| `i_s_axi_awvalid` | input | 1 | 未声明 | control | 请求awvalid |
| `o_s_axi_awready` | output | 1 | 未声明 | control | 接纳aw通道 |
| `i_s_axi_arid` | input | 4 | 未声明 | data | 请求arid |
| `i_s_axi_araddr` | input | 16 | 未声明 | data | 请求araddr |
| `i_s_axi_arlen` | input | 8 | 未声明 | data | 请求arlen |
| `i_s_axi_arsize` | input | 3 | 未声明 | data | 请求arsize |
| `i_s_axi_arburst` | input | 2 | 未声明 | data | 请求arburst |
| `i_s_axi_arlock` | input | 1 | 未声明 | data | 请求arlock |
| `i_s_axi_arvalid` | input | 1 | 未声明 | control | 请求arvalid |
| `o_s_axi_arready` | output | 1 | 未声明 | control | 接纳ar通道 |
| `i_s_axi_wdata` | input | 32 | 未声明 | data | AXI wdata事务字段 |
| `i_s_axi_wstrb` | input | 4 | 未声明 | data | AXI wstrb事务字段 |
| `i_s_axi_wlast` | input | 1 | 未声明 | control | AXI wlast事务字段 |
| `i_s_axi_wvalid` | input | 1 | 未声明 | control | AXI wvalid事务字段 |
| `o_s_axi_wready` | output | 1 | 未声明 | control | AXI wready事务字段 |
| `o_s_axi_bid` | output | 4 | 未声明 | data | AXI bid事务字段 |
| `o_s_axi_bresp` | output | 2 | 未声明 | data | AXI bresp事务字段 |
| `o_s_axi_bvalid` | output | 1 | 未声明 | control | AXI bvalid事务字段 |
| `i_s_axi_bready` | input | 1 | 未声明 | control | AXI bready事务字段 |
| `o_s_axi_rid` | output | 4 | 未声明 | data | AXI rid事务字段 |
| `o_s_axi_rdata` | output | 32 | 未声明 | data | AXI rdata事务字段 |
| `o_s_axi_rresp` | output | 2 | 未声明 | data | AXI rresp事务字段 |
| `o_s_axi_rlast` | output | 1 | 未声明 | control | AXI rlast事务字段 |
| `o_s_axi_rvalid` | output | 1 | 未声明 | control | AXI rvalid事务字段 |
| `i_s_axi_rready` | input | 1 | 未声明 | control | AXI rready事务字段 |
| `o_pcm_valid` | output | 1 | 未声明 | control | PCM 队列输出有效 |
| `i_pcm_ready` | input | 1 | 未声明 | control | PCM 消费者接纳 |
| `o_pcm_data` | output | 64 | 未声明 | data | 左右 signed Q26 采样 |
| `o_pcm_frame` | output | 32 | 未声明 | data | 采样帧编号 |
| `i_touch_gain` | input | 18 | 未声明 | data | i_touch_gain |
| `i_touch_pitch` | input | 32 | 未声明 | data | i_touch_pitch |
| `i_touch_cutoff` | input | 20 | 未声明 | data | i_touch_cutoff |
| `i_touch_cutoff_active` | input | 1 | 未声明 | data | i_touch_cutoff_active |

## 5. 周期行为与延迟

- Same AXI/PCM ports and bounded AXI protocol as AxiVoiceEndpoint, with LEGACY_ENABLE=0.
- Voice A0..A9, LFO B0..B3, FX C0..C4 remain available. Legacy capability/context capacity registers are zero.
- Unsupported command returns status 1 with original tag; does not hang or block audio. ABI 0x00010004.
- C_DELAY_ADDR_BITS defaults15 in the library; board top uses14. Depth=2**bits, Q16.16 maximum delay=(depth<<16)-1; capability registers report actual depth. Supported board configurations14/15.
- C_DELAY_ADDR_BITS defaults15 in the library; board top uses13. Depth=2**bits, Q16.16 maximum delay=(depth<<16)-1; capability registers report actual depth. Supported board configurations13/14/15.
- C_FX_ENABLE编译期选择；整板SynthSystemTop默认0，内核默认1保留回归。关闭时不实例化Delay/Reverb，Voice PCM直接进入原四项PCM队列，FX能力/容量/遥测为0，C0..C4通过不支持完成路径返回状态1。开机使用剔除FX命令的boot_dry.hex，正常音色、键床、UART及音频频率不变。
- C_TOUCH_ENABLE默认0，透传注册的硬件触摸调制源到Voice和Lowpass；AXI继续管理基础参数和音色程序。开启触摸的AxiVoiceEndpoint报告ABI1.7，否则保持1.6。

## 6. WaveDrom 时序图

### 触摸事件与调制提交

触摸采集在系统域提交，调制每毫秒平滑；音频帧独立执行，NoteOff确认之后才重新起音。

![触摸事件与调制提交](waveforms/AxiSynthEndpoint_touch.svg)

- WaveJSON：[AxiSynthEndpoint_touch.json5](waveforms/AxiSynthEndpoint_touch.json5)

## 7. 边界、反压与错误

- backpressure and bubbles
- full and empty queues
- reset with in-flight tasks
- invalid stage or operation or bus request

## 8. CDC 与综合约束

- Candidate subsystem; existing board top unchanged; no Gowin timing/area claim.
- Common core clock only, no CDC. Caller provides synchronous reset release.
- AXI endpoint is a slave; it does not fetch RAM itself or implement a program scheduler.

## 9. 验证与验收

- independent integer reference
- mixed tagged transactions and all sideband stability
- event/phase transition sequence
- AXI IDs, independent channels, WSTRB, bursts and FIFO side effects
- 关闭FX的整板启动、真实键床/UART、不支持命令和重放、PCM/PT8211一致性；保留FX配置兼容回归。

## 10. 可追溯性

- 规格模块：`AxiSynthEndpoint`
- RTL 路径：`rtl/AxiSynthEndpoint.v`
- 交付要求：本文档、WaveJSON 和 SVG 必须与同一版本规格一同发布。
