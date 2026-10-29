`timescale 1ns / 1ps
// AdcClockHighHold：固定SCLK为高，CS保持高，供测ADC时钟线路。
module AdcClockHighHold (
	output [2:0] o_mux_sel, // 地址100选择S5，对应每行物理第1键
	output o_mux_en,        // 四颗模拟开关共用的高有效使能
	output o_adc_cs_n,      // ADC片选保持无效，避免转换扰动
	output o_adc_sclk,      // ADC时钟保持高电平，供万用表测通路
	output o_adc_din,       // ADC命令输入保持低电平
	output o_uart_tx,       // 串口保持空闲高电平
	output o_rgb            // 灯珠数据保持低电平
);

// 静态选择S5，四行对应K01、K09、K17和K25。
assign o_mux_sel = 3'b100;
assign o_mux_en = 1'b1;

// 模拟测量期间保持数字接口空闲，下载完成后无需时钟或复位。
assign o_adc_cs_n = 1'b1;
assign o_adc_sclk = 1'b1;
assign o_adc_din = 1'b0;
assign o_uart_tx = 1'b1;
assign o_rgb = 1'b0;
endmodule
