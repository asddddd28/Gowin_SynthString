`timescale 1ns / 1ps
// HardwareLab：综合外围调试，所有传感器持续并行运行。
module HardwareLab #(
    parameter integer C_UART_CYCLES=434,C_SETTLE_CYCLES=10000,C_FRAME_CYCLES=1000000,
    parameter integer C_KEY_REPORT=5000000,C_ENCODER_REPORT=5000000,C_JOY_REPORT=2500000,
    parameter integer C_TOUCH_REPORT=2500000,C_ID_REPORT=12500000,C_BUTTON_REPORT=5000000,
    parameter integer C_BUTTON_FILTER=250000,
    parameter integer C_ENCODER_FILTER=2500,C_JOY_FILTER=250000,
    parameter integer C_I2C_DIVIDER=99,C_TOUCH_BOOT=2500000,C_TOUCH_RETRY=50000000,
    parameter integer C_TOUCH_RESET=250000,C_TOUCH_TIMEOUT=2000000
)(
    input i_clk,
    input i_rstn,
    input i_adc_dout,
    input i_uart_rx,
    input [4:0] i_encoder_a,
    input [4:0] i_encoder_b,
    input [4:0] i_joystick,
    input [1:0] i_irq,
    input [5:0] i_buttons,
    inout [1:0] io_scl,
    inout [1:0] io_sda,
    output [2:0] o_mux_sel,
    output o_mux_en,
    output o_adc_cs_n,
    output o_adc_sclk,
    output o_adc_din,
    output o_rgb,
    output o_uart_tx
);
reg [1:0] reset_sync=0;
reg [15:0] power_count=0;
wire resetn=reset_sync[1] && power_count[15];
wire [5:0] valid,ready,priority;
wire [47:0] data;
assign priority[2:1]=0;
assign priority[5:4]=0;
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin reset_sync<=0;power_count<=0;end
    else begin
        reset_sync<={reset_sync[0],1'b1};
        if(!power_count[15]) power_count<=power_count+1'b1;
    end
end
HardwareKeyboard #(.C_SETTLE_CYCLES(C_SETTLE_CYCLES),.C_UART_CYCLES(C_UART_CYCLES),
 .C_FRAME_CYCLES(C_FRAME_CYCLES),.C_REPORT_CYCLES(C_KEY_REPORT)) keyboard(
 .i_clk(i_clk),.i_rstn(resetn),.i_adc_dout(i_adc_dout),.i_uart_rx(i_uart_rx),
 .o_mux_sel(o_mux_sel),.o_mux_en(o_mux_en),.o_adc_cs_n(o_adc_cs_n),.o_adc_sclk(o_adc_sclk),.o_adc_din(o_adc_din),.o_rgb(o_rgb),
 .i_tx_ready(ready[0]),.o_tx_valid(valid[0]),.o_tx_data(data[7:0]),.o_priority(priority[0]));
HardwareEncoders #(.C_FILTER_CYCLES(C_ENCODER_FILTER),.C_REPORT_CYCLES(C_ENCODER_REPORT)) encoders(
 .i_clk(i_clk),.i_rstn(resetn),.i_encoder_a(i_encoder_a),.i_encoder_b(i_encoder_b),
 .i_tx_ready(ready[1]),.o_tx_valid(valid[1]),.o_tx_data(data[15:8]));
HardwareJoystick #(.C_FILTER_CYCLES(C_JOY_FILTER),.C_REPORT_CYCLES(C_JOY_REPORT)) joystick(
 .i_clk(i_clk),.i_rstn(resetn),.i_joystick(i_joystick),
 .i_tx_ready(ready[2]),.o_tx_valid(valid[2]),.o_tx_data(data[23:16]));
HardwareTouchpad #(.C_DIVIDER(C_I2C_DIVIDER),.C_REPORT(C_TOUCH_REPORT),.C_BOOT(C_TOUCH_BOOT),
 .C_RETRY(C_TOUCH_RETRY),.C_RESET_WAIT(C_TOUCH_RESET),.C_TIMEOUT(C_TOUCH_TIMEOUT)) touchpad(
 .i_clk(i_clk),.i_rstn(resetn),.i_irq(i_irq),.io_scl(io_scl),.io_sda(io_sda),
 .i_tx_ready(ready[3]),.o_tx_valid(valid[3]),.o_tx_data(data[31:24]),.o_priority(priority[3]));
HardwareIdentity #(.C_REPORT_CYCLES(C_ID_REPORT)) identity(
 .i_clk(i_clk),.i_rstn(resetn),.i_ready(ready[4]),.o_valid(valid[4]),.o_data(data[39:32]));
HardwareButtons #(.C_STABLE_CYCLES(C_BUTTON_FILTER),.C_REPORT_CYCLES(C_BUTTON_REPORT)) buttons(
 .i_clk(i_clk),.i_rstn(resetn),.i_buttons(i_buttons),
 .i_tx_ready(ready[5]),.o_tx_valid(valid[5]),.o_tx_data(data[47:40]));
TelemetryMux #(.C_BAUD(C_UART_CYCLES),.C_CHANNELS(6)) output_mux(
 .i_clk(i_clk),.i_rstn(resetn),.i_valid(valid),.i_data(data),.i_priority(priority),.o_ready(ready),.o_tx(o_uart_tx));
endmodule
