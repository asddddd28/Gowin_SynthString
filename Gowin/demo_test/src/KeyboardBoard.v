`timescale 1ns/1ps
// Board startup and PLL are reused from the working demo1 31004 project.
// 板级时钟复用demo1：上电等待、PLLA初始化、锁定后同步释放键盘复位。
module KeyboardBoard (
    input wire i_clk,
    input wire i_rstn,
    input wire i_adc_dout,
    output wire [2:0] o_mux_sel,
    output wire o_mux_en,
    output wire o_adc_cs_n,
    output wire o_adc_sclk,
    output wire o_adc_din,
    output wire o_uart_tx,
    output wire o_rgb
);
    // FPGA配置时清零；计满65535个50MHz时钟后允许PLL初始化。
    reg [15:0] cnt_powerup = 0;
    wire flag_clock_ready;
    wire clk_core;
    wire flag_pll_locked;
    wire rstn_core;
    assign flag_clock_ready = &cnt_powerup;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) cnt_powerup <= 0;
        else if (!flag_clock_ready) cnt_powerup <= cnt_powerup + 1'b1;
    end
    // 与demo1完全相同的49.152542MHz PLL及厂商初始化模块。
    Gowin_PLL Clock_Inst (
        .clkin(i_clk), .clkout0(clk_core), .lock(flag_pll_locked),
        .mdclk(i_clk), .reset(!flag_clock_ready)
    );
    ResetSync Reset_Inst (
        .i_clk(clk_core), .i_rstn(i_rstn && flag_pll_locked), .o_rstn(rstn_core)
    );
    // 49152542/115200四舍五入为427；模拟建立时间仍保持约200us。
    KeyboardDebug #(
        .C_SETTLE_CYCLES(9831), .C_HALF_CYCLES(6), .C_UART_CYCLES(427)
    ) Keyboard_Inst (
        .i_clk(clk_core), .i_rstn(rstn_core), .i_adc_dout(i_adc_dout),
        .o_mux_sel(o_mux_sel), .o_mux_en(o_mux_en), .o_adc_cs_n(o_adc_cs_n),
        .o_adc_sclk(o_adc_sclk), .o_adc_din(o_adc_din),
        .o_uart_tx(o_uart_tx), .o_rgb(o_rgb)
    );
endmodule
