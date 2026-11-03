`timescale 1ns / 1ps
// Existing scanner with parallel independent buses / 复用原有双MPR采集。
module SynthTouchInput(
    input i_clk,input i_rstn,inout [1:0] io_scl,inout [1:0] io_sda,
    output [1:0] o_update,output [1:0] o_touch,output [19:0] o_x,output [19:0] o_y,output [15:0] o_error
);
    genvar side;
    generate for(side=0;side<2;side=side+1)begin:gen_pad
        wire [335:0] wire_raw;wire [15:0] wire_sequence;
        MprScanner Scanner_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.io_scl(io_scl[side]),.io_sda(io_sda[side]),
            .o_raw(wire_raw),.o_sequence(wire_sequence),.o_address(),.o_error(o_error[side*8+:8]));
        TouchPosition Position_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_raw(wire_raw),.i_sequence(wire_sequence),.i_error(o_error[side*8+:8]),
            .o_update(o_update[side]),.o_touch(o_touch[side]),.o_x(o_x[side*10+:10]),.o_y(o_y[side*10+:10]));
    end endgenerate
endmodule
