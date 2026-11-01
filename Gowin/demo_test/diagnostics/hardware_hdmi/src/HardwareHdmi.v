`timescale 1ns / 1ps
// HardwareHdmi / 硬件仪表盘：既有外围调试核心 + 独立像素域显示。
// Contract: ../spec/HardwareHdmi_spec.md. No soft CPU or external framebuffer.
module HardwareHdmi(
    input i_clk, input i_rstn, input i_adc_dout, input i_uart_rx,
    input [4:0] i_encoder_a, i_encoder_b, i_joystick, input [1:0] i_irq,
    inout [1:0] io_scl, io_sda,
    output [2:0] o_mux_sel,
    output o_mux_en, o_adc_cs_n, o_adc_sclk, o_adc_din, o_rgb, o_uart_tx,
    output tmds_clk_p_0, tmds_clk_n_0,
    output [2:0] tmds_d_p_0, tmds_d_n_0,
    output hpd_en
);
    wire clk_serial, clk_pixel, flag_pll_lock;
    reg [2:0] reg_reset_release = 0;
    wire flag_video_reset_n=reg_reset_release[2];
    // Vendor DVI IP has a shared asynchronous reset for its PCLK/FCLK domains.
    // Keep the official example's lock-qualified reset, separate from pixel logic.
    wire flag_dvi_reset_n=i_rstn && flag_pll_lock;
    wire [7:0] reg_byte;
    wire flag_byte_valid, flag_byte_error;
    wire [383:0] bus_keys;
    wire [79:0] bus_encoders;
    wire [4:0] bus_joystick;
    wire [23:0] bus_touch;
    wire [1:0] bus_touch_ok;
    wire [31:0] bus_pressed;
    wire flag_configured, flag_live, flag_sample;
    wire [3:0] bus_effect;
    wire [11:0] bus_key_value;
    wire [23:0] bus_rgb;
    wire flag_hsync, flag_vsync, flag_de;
    assign hpd_en=1'b1;

    HardwareLab HardwareLab_Inst(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_adc_dout(i_adc_dout),.i_uart_rx(i_uart_rx),
        .i_encoder_a(i_encoder_a),.i_encoder_b(i_encoder_b),.i_joystick(i_joystick),.i_irq(i_irq),
        .io_scl(io_scl),.io_sda(io_sda),.o_mux_sel(o_mux_sel),.o_mux_en(o_mux_en),
        .o_adc_cs_n(o_adc_cs_n),.o_adc_sclk(o_adc_sclk),.o_adc_din(o_adc_din),.o_rgb(o_rgb),.o_uart_tx(o_uart_tx));
    TMDS_PLL u_tmds_pll(.clkin(i_clk),.clkout0(clk_serial),.clkout1(clk_pixel),.lock(flag_pll_lock));
    // Only serial TX crosses clock domains; UartRx owns its two-flop input synchronizer.
    always @(posedge clk_pixel or negedge i_rstn or negedge flag_pll_lock) begin
        if(!i_rstn || !flag_pll_lock) reg_reset_release<=0;
        else reg_reset_release<={reg_reset_release[1:0],1'b1};
    end
    UartRx #(.C_CLOCK_HZ(73333333),.C_BAUD(115200)) Observer_Inst(
        .i_clk(clk_pixel),.i_rstn(flag_video_reset_n),.i_rx(o_uart_tx),
        .o_byte(reg_byte),.o_valid(flag_byte_valid),.o_error(flag_byte_error));
    DashboardTelemetry Telemetry_Inst(
        .i_clk(clk_pixel),.i_rstn(flag_video_reset_n),.i_byte(reg_byte),.i_valid(flag_byte_valid),.i_error(flag_byte_error),
        .o_keys(bus_keys),.o_encoders(bus_encoders),.o_joystick(bus_joystick),.o_touch(bus_touch),.o_touch_ok(bus_touch_ok),
        .o_pressed(bus_pressed),.o_configured(flag_configured),.o_effect(bus_effect),.o_live(flag_live),
        .o_key_sample(flag_sample),.o_key_value(bus_key_value));
    DashboardVideo Video_Inst(
        .i_clk(clk_pixel),.i_rstn(flag_video_reset_n),.i_keys(bus_keys),.i_encoders(bus_encoders),.i_joystick(bus_joystick),
        .i_touch(bus_touch),.i_touch_ok(bus_touch_ok),.i_pressed(bus_pressed),.i_configured(flag_configured),
        .i_effect(bus_effect),.i_live(flag_live),.i_key_sample(flag_sample),.i_key_value(bus_key_value),
        .o_rgb(bus_rgb),.o_hsync(flag_hsync),.o_vsync(flag_vsync),.o_de(flag_de));
    DVI_TX_Top Dvi_Inst(
        .I_rst_n(flag_dvi_reset_n),.I_serial_clk(clk_serial),.I_rgb_clk(clk_pixel),
        .I_rgb_vs(flag_vsync),.I_rgb_hs(flag_hsync),.I_rgb_de(flag_de),
        .I_rgb_r(bus_rgb[23:16]),.I_rgb_g(bus_rgb[15:8]),.I_rgb_b(bus_rgb[7:0]),
        .O_tmds_clk_p(tmds_clk_p_0),.O_tmds_clk_n(tmds_clk_n_0),
        .O_tmds_data_p(tmds_d_p_0),.O_tmds_data_n(tmds_d_n_0));
endmodule
