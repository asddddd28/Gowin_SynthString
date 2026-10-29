`timescale 1ns / 1ps
// Palette image and ownership are captured only at the LED frame boundary.
// 整帧锁存游戏画面，防止中途按键造成半帧撕裂。
module GameDisplay (
    input i_clk,
    input i_rstn,
    input i_enable,
    input i_frame_tick,
    input [63:0] i_pixels,
    input [4:0] i_pixel,
    output o_active,
    output [23:0] o_grb
);
reg flag_active_o;
reg [63:0] reg_snapshot;
reg [23:0] reg_grb_o;
assign o_active=flag_active_o;
assign o_grb=reg_grb_o;
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin flag_active_o<=0; reg_snapshot<=0; end
    else if(i_frame_tick) begin flag_active_o<=i_enable; reg_snapshot<=i_pixels; end
end
always @(*) begin
    case(reg_snapshot[i_pixel*2+:2])
        1:reg_grb_o=24'h200000;
        2:reg_grb_o=24'h002000;
        3:reg_grb_o=24'h200020;
        default:reg_grb_o=24'h000000;
    endcase
end
endmodule
