`timescale 1ns / 1ps
// 键盘接口高阻隔离，供复核异常供电与接线。
module KeyboardHighImpedance (
    inout [2:0] o_mux_sel,
    inout o_mux_en,
    inout o_adc_cs_n,
    inout o_adc_sclk,
    inout o_adc_din,
    inout o_rgb,
    inout io_adc_dout,
    output o_uart_tx
);
assign o_mux_sel=3'bzzz;
assign o_mux_en=1'bz;
assign o_adc_cs_n=1'bz;
assign o_adc_sclk=1'bz;
assign o_adc_din=1'bz;
assign o_rgb=1'bz;
assign io_adc_dout=1'bz;
assign o_uart_tx=1'b1;
endmodule
