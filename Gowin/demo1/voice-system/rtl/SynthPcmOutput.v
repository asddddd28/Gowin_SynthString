`timescale 1ns / 1ps
// Fixed-rate PT8211 sink / 固定帧率音频输出. Contract: spec/SynthPcmOutput_spec.md.
module SynthPcmOutput(
    input i_clk,input i_rstn,input i_valid,input [63:0] i_data,output o_ready,
    output o_bclk,output o_ws,output o_data,output [31:0] o_frames,output [31:0] o_underruns
);
    reg [9:0] cnt_frame;
    reg [15:0] reg_left,reg_right;
    reg flag_started,reg_serial;
    reg [31:0] cnt_frames,cnt_underruns;
    wire signed [31:0] wire_left=i_data[31:0];
    wire signed [31:0] wire_right=i_data[63:32];
    wire [32:0] wire_abs_left=wire_left<0 ? -$signed({wire_left[31],wire_left}) : {1'b0,wire_left};
    wire [32:0] wire_abs_right=wire_right<0 ? -$signed({wire_right[31],wire_right}) : {1'b0,wire_right};
    wire [32:0] wire_round_left=(wire_abs_left+33'd1024)>>11;
    wire [32:0] wire_round_right=(wire_abs_right+33'd1024)>>11;
    wire [15:0] wire_pcm_left=wire_left<0 ? (wire_round_left>=32768 ? 16'h8000 : -wire_round_left[15:0]) : (wire_round_left>32767 ? 16'h7fff : wire_round_left[15:0]);
    wire [15:0] wire_pcm_right=wire_right<0 ? (wire_round_right>=32768 ? 16'h8000 : -wire_round_right[15:0]) : (wire_round_right>32767 ? 16'h7fff : wire_round_right[15:0]);
    assign o_ready=cnt_frame==0;
    assign o_bclk=cnt_frame[4];
    assign o_ws=!cnt_frame[9];
    assign o_data=reg_serial;
    assign o_frames=cnt_frames;
    assign o_underruns=cnt_underruns;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            cnt_frame<=0;reg_left<=0;reg_right<=0;flag_started<=0;reg_serial<=0;cnt_frames<=0;cnt_underruns<=0;
        end else begin
            cnt_frame<=cnt_frame+1'b1;
            if (cnt_frame==0) begin
                if (i_valid) begin
                    reg_left<=wire_pcm_left;reg_right<=wire_pcm_right;flag_started<=1;cnt_frames<=cnt_frames+1'b1;
                end else begin
                    reg_left<=0;reg_right<=0;
                    if (flag_started) cnt_underruns<=cnt_underruns+1'b1;
                end
            end
            if (cnt_frame[4:0]==1) reg_serial<=cnt_frame[9] ? reg_right[15-cnt_frame[8:5]] : reg_left[15-cnt_frame[8:5]];
        end
    end
endmodule
