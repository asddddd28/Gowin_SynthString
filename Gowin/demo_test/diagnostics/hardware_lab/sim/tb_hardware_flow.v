`timescale 1ns / 1ps
module tb_hardware_flow;
reg clk=0,rstn=0,command_valid=0,tick=0;
reg [79:0] command=0;
reg [4:0] pixel=0;
wire ack,clear;
wire [7:0] result;
wire [3:0] mode;
wire direction;
wire [23:0] grb;
reg [23:0] initial_color;
integer frames,row;
always #10 clk=~clk;
HardwareKeyController controller(.i_clk(clk),.i_rstn(rstn),.i_command(command),.i_command_valid(command_valid),
 .i_crc_error(1'b0),.i_key(5'd0),.i_raw(12'd0),.i_sample_valid(1'b0),.o_ack(ack),.o_ack_result(result),
 .o_mode(mode),.o_direction(direction),.o_clear_effect(clear));
HardwareKeyLightEffects effects(.i_clk(clk),.i_rstn(rstn),.i_press(32'd0),.i_clear(clear),.i_mode(mode),
 .i_direction(direction),.i_frame_tick(tick),.i_pixel(pixel),.o_grb(grb));
initial begin
    #100;rstn=1;
    @(negedge clk);command=80'h01200000000000000060;command_valid=1;
    @(negedge clk);command_valid=0;
    if(!ack || result!=0 || mode!=6)$fatal(1,"Flow command rejected");
    repeat(3)@(negedge clk);tick=1;@(negedge clk);tick=0;#1;
    initial_color=grb;
    if(initial_color==0)$fatal(1,"Flow starts black");
    for(row=1;row<4;row=row+1)begin pixel=row*8;#40;if(grb!==initial_color)$fatal(1,"Rows do not match");end
    pixel=0;
    for(frames=0;frames<20;frames=frames+1)begin @(negedge clk);tick=1;@(negedge clk);tick=0;end
    #1;if(grb==initial_color)$fatal(1,"Flow did not move/change color");
    @(negedge clk);command=80'h02200000000000000050;command_valid=1;
    @(negedge clk);command_valid=0;
    if(result!=3 || mode!=6)$fatal(1,"Reserved game mode accepted as effect");
    $display("PASS mode6 ACK, animated matching four-row flow, reserved mode5 rejection");$finish;
end
endmodule
