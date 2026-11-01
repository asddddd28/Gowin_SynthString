`timescale 1ns / 1ps
// HardwareIdentity：固定能力声明，首次立即发送，此后每250ms刷新。
module HardwareIdentity #(parameter integer C_REPORT_CYCLES=12500000)(
    input i_clk,
    input i_rstn,
    input i_ready,
    output o_valid,
    output [7:0] o_data
);
reg [31:0] count;
reg [3:0] index;
reg active;
reg [7:0] data_o;
assign o_valid=active;
assign o_data=data_o;
always @(*) begin
    case(index)
        0:data_o="H";1:data_o="1";2:data_o="0";3:data_o="0";4:data_o="7";5:data_o="F";
        6:data_o="0";7:data_o="1";8:data_o="0";9:data_o="0";10:data_o="*";
        11:data_o="6";12:data_o="6";13:data_o=13;default:data_o=10;
    endcase
end
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin count<=0;index<=0;active<=1;end
    else begin
        if(count<C_REPORT_CYCLES) count<=count+1'b1;
        if(active && i_ready) begin
            if(index==14) begin active<=0;index<=0;end
            else index<=index+1'b1;
        end else if(!active && count==C_REPORT_CYCLES) begin count<=0;active<=1;end
    end
end
endmodule
