`timescale 1ns / 1ps
// TelemetryByte：将旧发送器的start/busy接口变为有反压的一字节保持寄存器。
module TelemetryByte (
    input i_clk,
    input i_rstn,
    input i_start,
    input [7:0] i_data,
    input i_ready,
    output o_busy,
    output o_valid,
    output [7:0] o_data
);
reg valid_o;
reg [7:0] data_o;
assign o_busy=valid_o;
assign o_valid=valid_o;
assign o_data=data_o;
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin valid_o<=0; data_o<=0; end
    else if(valid_o) begin
        if(i_ready) valid_o<=0;
    end else if(i_start) begin
        valid_o<=1; data_o<=i_data;
    end
end
endmodule
