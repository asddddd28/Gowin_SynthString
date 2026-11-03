`timescale 1ns / 1ps
// SynthString audio + SynthUI display / 合成系统与独立显示域。
module SynthHdmiTop(
    input i_sd_miso,output o_sd_cs_n,output o_sd_sclk,output o_sd_mosi,output o_rgb,
    input [5:0] i_buttons,
    inout [1:0] io_touch_scl,inout [1:0] io_touch_sda,
    input i_clk,input i_rstn,input i_adc_dout,input i_uart_rx,
    input [4:0] i_encoder_a,input [4:0] i_encoder_b,input [4:0] i_joystick,
    output [2:0] o_mux_sel,output o_mux_en,output o_adc_cs_n,output o_adc_sclk,output o_adc_din,output o_uart_tx,
    output HP_BCK,output HP_WS,output HP_DIN,output PA_EN,
    output tmds_clk_p_0,output tmds_clk_n_0,output [2:0] tmds_d_p_0,output [2:0] tmds_d_n_0,output hpd_en
);
    wire clk_pixel,clk_serial,flag_pll_lock,flag_system_reset_n;
    reg [2:0] reg_pixel_reset=0;
    wire flag_pixel_reset_n=reg_pixel_reset[2];
    wire [31:0] wire_keys,wire_latency,wire_underruns,wire_errors,wire_frames;
    wire [15:0] wire_sample;
    wire flag_sample,flag_request,flag_response;
    reg [15:0] reg_analysis_sample;
    reg flag_analysis_sample;
    wire [7:0] wire_opcode,wire_argument;
    wire [63:0] wire_words;
    wire [135:0] wire_response;
    wire flag_display_response,flag_rgb_response;
    reg flag_storage_response;
    wire [135:0] wire_display_response,wire_rgb_response;
    wire flag_storage_select=wire_opcode>=8'h50;
    wire flag_rgb_select=wire_opcode==8'h18 || wire_opcode==8'h19;
    assign flag_response=flag_storage_select ? flag_storage_response : flag_rgb_select ? flag_rgb_response : flag_display_response;
    assign wire_response=flag_storage_select ? {8'd5,128'd0} : flag_rgb_select ? wire_rgb_response : wire_display_response;
    // SD is disabled in this build. Return UNSUPPORTED promptly, never time out.
    assign o_sd_cs_n=1'b1;
    assign o_sd_sclk=1'b0;
    assign o_sd_mosi=1'b1;
    always @(posedge i_clk or negedge flag_system_reset_n) begin
        if(!flag_system_reset_n) flag_storage_response<=0;
        else flag_storage_response<=flag_request && flag_storage_select;
    end
    wire [2:0] wire_page,wire_pixel_page;
    wire flag_text_write,flag_blank,flag_audio,flag_publish;
    wire [9:0] wire_text_address;
    wire [7:0] wire_text_data,wire_wave,wire_wave_address;
    wire [6:0] wire_spectrum;
    wire [5:0] wire_spectrum_address;
    wire [159:0] wire_fields;
    wire [23:0] wire_rgb;
    wire flag_hsync,flag_vsync,flag_de;
    wire flag_host_live,flag_calibrating,flag_touch_next;
    wire [1:0] wire_touch_mode;
    assign hpd_en=1'b1;
    SynthSystemTop #(.C_DISPLAY_ENABLE(1),.C_TOUCH_ENABLE(1),.C_SEQUENCE_ENABLE(1)) Synth_Inst(
        .i_buttons(i_buttons),.o_sequence_status(),.o_sequence_bpm(),
        .i_touch_next(flag_touch_next),.io_touch_scl(io_touch_scl),.io_touch_sda(io_touch_sda),.o_touch_mode(wire_touch_mode),
        .i_clk(i_clk),.i_rstn(i_rstn),.i_adc_dout(i_adc_dout),.i_uart_rx(i_uart_rx),
        .o_mux_sel(o_mux_sel),.o_mux_en(o_mux_en),.o_adc_cs_n(o_adc_cs_n),.o_adc_sclk(o_adc_sclk),.o_adc_din(o_adc_din),.o_uart_tx(o_uart_tx),
        .HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.PA_EN(PA_EN),
        .o_display_calibrating(flag_calibrating),.o_display_reset_n(flag_system_reset_n),.o_display_keys(wire_keys),.o_display_latency(wire_latency),
        .o_display_underruns(wire_underruns),.o_display_errors(wire_errors),.o_display_frames(wire_frames),
        .o_display_sample_valid(flag_sample),.o_display_sample(wire_sample),
        .o_display_request(flag_request),.o_display_opcode(wire_opcode),.o_display_argument(wire_argument),.o_display_words(wire_words),
        .i_display_response_valid(flag_response),.i_display_response(wire_response));
    TMDS_PLL u_tmds_pll(.clkin(i_clk),.clkout0(clk_serial),.clkout1(clk_pixel),.lock(flag_pll_lock));
    always @(posedge clk_pixel or negedge i_rstn or negedge flag_pll_lock) begin
        if(!i_rstn || !flag_pll_lock) reg_pixel_reset<=0;
        else reg_pixel_reset<={reg_pixel_reset[1:0],1'b1};
    end
    SynthDisplayControl Control_Inst(
        .i_clk(i_clk),.i_rstn(flag_system_reset_n),.i_joystick(i_joystick),.i_encoder_a(i_encoder_a),.i_encoder_b(i_encoder_b),
        .i_request(flag_request && !flag_storage_select && !flag_rgb_select),.i_opcode(wire_opcode),.i_argument(wire_argument),.i_words(wire_words),
        .o_response_valid(flag_display_response),.o_response(wire_display_response),.o_text_write(flag_text_write),.o_text_address(wire_text_address),.o_text_data(wire_text_data),
        .o_touch_next(flag_touch_next),.o_page(wire_page),.o_focus(),.o_confirm(),.o_host_live(flag_host_live));
    SynthKeyboardRgb Rgb_Inst(
        .i_clk(i_clk),.i_rstn(flag_system_reset_n),.i_pressed(wire_keys),.i_calibrating(flag_calibrating),
        .i_request(flag_request && flag_rgb_select),
        .i_opcode(wire_opcode),.i_argument(wire_argument),.i_words(wire_words),
        .o_response_valid(flag_rgb_response),.o_response(wire_rgb_response),.o_rgb(o_rgb));
    SynthDisplaySnapshot Snapshot_Inst(
        .i_clk(i_clk),.i_rstn(flag_system_reset_n),.i_pixel_clk(clk_pixel),.i_pixel_rstn(flag_pixel_reset_n),.i_blank_start(flag_blank),
        .i_keys(wire_keys),.i_latency(wire_latency),.i_underruns(wire_underruns),.i_errors(wire_errors),.i_frames(wire_frames),.i_page(wire_page),
        .o_fields(wire_fields),.o_page(wire_pixel_page));
    // The visual analyser consumes a registered copy; the DAC sample timing is unchanged.
    always @(posedge i_clk or negedge flag_system_reset_n)begin
        if(!flag_system_reset_n)begin reg_analysis_sample<=0;flag_analysis_sample<=0;end
        else begin
            flag_analysis_sample<=flag_sample;
            if(flag_sample)reg_analysis_sample<=wire_sample;
        end
    end
    SynthDisplayAudio Analyse_Inst(
        .i_clk(i_clk),.i_rstn(flag_system_reset_n),.i_sample_valid(flag_analysis_sample),.i_sample(reg_analysis_sample),
        .i_pixel_clk(clk_pixel),.i_pixel_rstn(flag_pixel_reset_n),.i_blank_start(flag_blank),
        .i_wave_address(wire_wave_address),.i_spectrum_address(wire_spectrum_address),
        .o_wave(wire_wave),.o_spectrum(wire_spectrum),.o_available(flag_audio),.o_publish(flag_publish));
    SynthDisplayVideo #(.C_TOUCH_ENABLE(1)) Video_Inst(.i_touch_mode(wire_touch_mode),
        .i_clk(clk_pixel),.i_rstn(flag_pixel_reset_n),.i_system_clk(i_clk),.i_page(wire_pixel_page),.i_fields(wire_fields),.i_host_live(flag_host_live),.i_calibrating(flag_calibrating),
        .i_text_write(flag_text_write),.i_text_address(wire_text_address),.i_text_data(wire_text_data),
        .i_wave(wire_wave),.i_spectrum(wire_spectrum),.i_audio_available(flag_audio),.i_publish(flag_publish),
        .o_wave_address(wire_wave_address),.o_spectrum_address(wire_spectrum_address),.o_blank_start(flag_blank),
        .o_rgb(wire_rgb),.o_hsync(flag_hsync),.o_vsync(flag_vsync),.o_de(flag_de));
    DVI_TX_Top Dvi_Inst(
        .I_rst_n(i_rstn && flag_pll_lock),.I_serial_clk(clk_serial),.I_rgb_clk(clk_pixel),
        .I_rgb_vs(flag_vsync),.I_rgb_hs(flag_hsync),.I_rgb_de(flag_de),
        .I_rgb_r(wire_rgb[23:16]),.I_rgb_g(wire_rgb[15:8]),.I_rgb_b(wire_rgb[7:0]),
        .O_tmds_clk_p(tmds_clk_p_0),.O_tmds_clk_n(tmds_clk_n_0),.O_tmds_data_p(tmds_d_p_0),.O_tmds_data_n(tmds_d_n_0));
endmodule
