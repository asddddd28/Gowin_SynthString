`timescale 1ns / 1ps
// KeyboardRgbFlow: preserve ADC scanning while driving the keyboard LED chain.
// 键盘采集与灯效并行封装，复用已验证的键盘扫描模块。
module KeyboardRgbFlow #(
	parameter integer C_SETTLE_CYCLES = 10000, // 模拟通道切换建立时间
	parameter integer C_HALF_CYCLES = 6,       // ADC串行时钟半周期
	parameter integer C_UART_CYCLES = 434      // 串口位宽
)(
	input i_clk,                             // 主板50MHz时钟
	input i_rstn,                            // 低有效外部复位
	input i_adc_dout,                        // ADC转换结果输入
	output [2:0] o_mux_sel,                  // 共享模拟开关列地址
	output o_mux_en,                        // 模拟开关使能
	output o_adc_cs_n,                      // ADC帧片选
	output o_adc_sclk,                      // ADC移位时钟
	output o_adc_din,                       // ADC通道选择命令
	output o_uart_tx,                       // GUI使用的原始值串口流
	output o_rgb                            // 键盘灯串数据
);
// 采集模块源码保持不变，旧的恒低灯光端口不连接。
KeyboardDebug #(
	.C_SETTLE_CYCLES(C_SETTLE_CYCLES),
	.C_HALF_CYCLES(C_HALF_CYCLES),
	.C_UART_CYCLES(C_UART_CYCLES)
) KeyboardScanner_Inst (
	.i_clk(i_clk), .i_rstn(i_rstn), .i_adc_dout(i_adc_dout),
	.o_mux_sel(o_mux_sel), .o_mux_en(o_mux_en), .o_adc_cs_n(o_adc_cs_n),
	.o_adc_sclk(o_adc_sclk), .o_adc_din(o_adc_din), .o_uart_tx(o_uart_tx), .o_rgb()
);
// 灯效使用独立计数器，不会暂停或修改ADC扫描。
RgbFlow KeyboardLights_Inst (.i_clk(i_clk), .i_rstn(i_rstn), .o_data(o_rgb));
endmodule
