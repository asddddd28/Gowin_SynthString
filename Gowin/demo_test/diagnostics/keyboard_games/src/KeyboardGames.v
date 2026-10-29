`timescale 1ns / 1ps
// Calibrated keyboard controller, UART configuration and reactive RGB effects.
// 统一同步复位；数据采样、命令接收、状态回传和灯串发送并行运行。
module KeyboardGames #(
 parameter integer C_SETTLE_CYCLES=10000,parameter integer C_HALF_CYCLES=6,
 parameter integer C_UART_CYCLES=434,parameter integer C_FRAME_CYCLES=1000000
)(
 input i_clk,input i_rstn,input i_adc_dout,input i_uart_rx,
 output [2:0] o_mux_sel,output o_mux_en,output o_adc_cs_n,output o_adc_sclk,
 output o_adc_din,output o_uart_tx,output o_rgb
);
reg [1:0] reg_reset;
wire flag_reset_n;
wire [7:0] enc_byte,enc_ack_seq,enc_ack_result,enc_generation;
wire flag_byte_valid,flag_byte_error,flag_command_valid,flag_crc_error;
wire [79:0] enc_command;
wire [4:0] enc_key,enc_pixel;
wire [11:0] enc_raw;
wire flag_sample_valid,flag_sample_ready,flag_sample_transfer;
wire flag_ack,flag_configured,flag_direction,flag_clear,flag_frame_tick;
wire [3:0] enc_mode;
wire [31:0] reg_pressed,reg_press;
wire [23:0] enc_grb;
wire flag_game_start,flag_game_stop,flag_game_active;
wire [1:0] enc_game_type;
wire [63:0] enc_game_pixels;
wire [127:0] enc_game_status;
wire [23:0] enc_game_grb,enc_output_grb;
assign enc_output_grb=flag_game_active ? enc_game_grb : enc_grb;
assign flag_reset_n=reg_reset[1];
assign flag_sample_transfer=flag_sample_valid && flag_sample_ready;
always @(posedge i_clk or negedge i_rstn)begin
 if(!i_rstn)begin reg_reset<=0; end else begin reg_reset<={reg_reset[0],1'b1}; end
end
UartRx #(.C_CLOCK_HZ(C_UART_CYCLES*115200),.C_BAUD(115200)) UartInput_Inst(
 .i_clk(i_clk),.i_rstn(flag_reset_n),.i_rx(i_uart_rx),.o_byte(enc_byte),.o_valid(flag_byte_valid),.o_error(flag_byte_error));
CommandFrameRx CommandParser_Inst(.i_clk(i_clk),.i_rstn(flag_reset_n),.i_byte(enc_byte),.i_valid(flag_byte_valid),.i_error(flag_byte_error),
 .o_payload(enc_command),.o_valid(flag_command_valid),.o_crc_error(flag_crc_error));
KeyboardSampler #(.C_SETTLE_CYCLES(C_SETTLE_CYCLES),.C_HALF_CYCLES(C_HALF_CYCLES)) Scanner_Inst(
 .i_clk(i_clk),.i_rstn(flag_reset_n),.i_adc_dout(i_adc_dout),.i_ready(flag_sample_ready),.o_mux_sel(o_mux_sel),.o_mux_en(o_mux_en),
 .o_adc_cs_n(o_adc_cs_n),.o_adc_sclk(o_adc_sclk),.o_adc_din(o_adc_din),.o_key(enc_key),.o_raw(enc_raw),.o_valid(flag_sample_valid));
KeyController KeyState_Inst(.i_clk(i_clk),.i_rstn(flag_reset_n),.i_command(enc_command),.i_command_valid(flag_command_valid),.i_crc_error(flag_crc_error),
 .i_key(enc_key),.i_raw(enc_raw),.i_sample_valid(flag_sample_transfer),.o_ack(flag_ack),.o_ack_seq(enc_ack_seq),.o_ack_result(enc_ack_result),
 .o_configured(flag_configured),.o_generation(enc_generation),.o_mode(enc_mode),.o_direction(flag_direction),.o_pressed(reg_pressed),.o_press_pulse(reg_press),.o_clear_effect(flag_clear),
 .o_game_start(flag_game_start),.o_game_stop(flag_game_stop),.o_game_type(enc_game_type));
KeyboardTelemetry #(.C_UART_CYCLES(C_UART_CYCLES)) Telemetry_Inst(.i_clk(i_clk),.i_rstn(flag_reset_n),.i_key(enc_key),.i_raw(enc_raw),.i_valid(flag_sample_valid),.o_ready(flag_sample_ready),
 .i_ack(flag_ack),.i_ack_seq(enc_ack_seq),.i_ack_result(enc_ack_result),.i_configured(flag_configured),.i_generation(enc_generation),.i_mode(enc_mode),.i_direction(flag_direction),.i_pressed(reg_pressed),.i_game_status(enc_game_status),.o_tx(o_uart_tx));
KeyLightEffects Effects_Inst(.i_clk(i_clk),.i_rstn(flag_reset_n),.i_press(reg_press),.i_clear(flag_clear),.i_mode(enc_mode),.i_direction(flag_direction),
 .i_frame_tick(flag_frame_tick),.i_pixel(enc_pixel),.o_grb(enc_grb));
GameEngine Game_Inst(.i_clk(i_clk),.i_rstn(flag_reset_n),.i_start(flag_game_start),.i_stop(flag_game_stop),.i_game(enc_game_type),
 .i_frame_tick(flag_frame_tick),.i_press(reg_press),.i_pressed(reg_pressed),.o_pixels(enc_game_pixels),.o_status(enc_game_status));
GameDisplay GameDisplay_Inst(.i_clk(i_clk),.i_rstn(flag_reset_n),.i_enable(enc_mode==5),.i_frame_tick(flag_frame_tick),
 .i_pixels(enc_game_pixels),.i_pixel(enc_pixel),.o_active(flag_game_active),.o_grb(enc_game_grb));
LedFrameTx #(.C_FRAME_CYCLES(C_FRAME_CYCLES)) LedOutput_Inst(.i_clk(i_clk),.i_rstn(flag_reset_n),.i_grb(enc_output_grb),.o_pixel(enc_pixel),.o_frame_tick(flag_frame_tick),.o_data(o_rgb));
endmodule
