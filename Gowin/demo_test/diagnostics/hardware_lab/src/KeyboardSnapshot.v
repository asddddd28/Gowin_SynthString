`timescale 1ns / 1ps
// KeyboardSnapshot：采样继续运行；只在完整扫描边界捕获要上报的32键。
module KeyboardSnapshot #(
    parameter integer C_REPORT_CYCLES=5000000
)(
    input i_clk,
    input i_rstn,
    input [4:0] i_key,
    input [11:0] i_raw,
    input i_valid,
    input i_ready,
    output [4:0] o_key,
    output [11:0] o_raw,
    output o_valid
);
reg [11:0] latest [0:31];
reg [11:0] snapshot [0:31];
reg [31:0] seen;
reg [31:0] elapsed;
reg active;
reg [4:0] key_o;
integer key_index;
assign o_key=key_o;
assign o_raw=snapshot[key_o];
assign o_valid=active;
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin
        seen<=0; elapsed<=0; active<=0; key_o<=0;
        for(key_index=0;key_index<32;key_index=key_index+1) begin
            latest[key_index]<=0; snapshot[key_index]<=0;
        end
    end else begin
        if(elapsed<C_REPORT_CYCLES) elapsed<=elapsed+1'b1;
        if(i_valid) begin latest[i_key]<=i_raw; seen[i_key]<=1; end
        if(active && i_ready) begin
            if(key_o==31) active<=0;
            else key_o<=key_o+1'b1;
        end
        if(!active && elapsed==C_REPORT_CYCLES && i_valid && i_key==31 && (&seen[30:0])) begin
            for(key_index=0;key_index<31;key_index=key_index+1) snapshot[key_index]<=latest[key_index];
            snapshot[31]<=i_raw; active<=1; key_o<=0; elapsed<=0;
        end
    end
end
endmodule
