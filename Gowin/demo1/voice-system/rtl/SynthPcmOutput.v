`timescale 1ns / 1ps
// Fixed-rate PT8211 sink / 固定帧率音频输出. Contract: spec/SynthPcmOutput_spec.md.
module SynthPcmOutput #(parameter C_METRONOME_ENABLE=0)(
    input [15:0] i_click,
    input i_clk,input i_rstn,input i_valid,input [63:0] i_data,output o_ready,
    output o_bclk,output o_ws,output o_data,output [31:0] o_frames,output [31:0] o_underruns,
    output o_sample_valid,output [15:0] o_sample
);
    reg [9:0] cnt_frame;
    reg [15:0] reg_left,reg_right;
    reg flag_started,reg_serial;
    reg [31:0] cnt_frames,cnt_underruns;
    wire signed [31:0] wire_left=i_data[31:0];
    wire signed [31:0] wire_right=i_data[63:32];
    // Round signed Q26 to signed16, ties away from zero. Adding one to the
    // signed upper21 bits avoids absolute-value and sign-restore carry chains.
    // Negative exact half steps stay at floor; negative values above half add1.
    wire flag_round_left=wire_left[10] && (!wire_left[31] || |wire_left[9:0]);
    wire flag_round_right=wire_right[10] && (!wire_right[31] || |wire_right[9:0]);
    wire signed [21:0] wire_round_left=$signed({wire_left[31],wire_left[31:11]})+$signed({21'd0,flag_round_left});
    wire signed [21:0] wire_round_right=$signed({wire_right[31],wire_right[31:11]})+$signed({21'd0,flag_round_right});
    wire [15:0] wire_pcm_left=wire_round_left>22'sd32767 ? 16'h7fff : wire_round_left< -22'sd32768 ? 16'h8000 : wire_round_left[15:0];
    wire [15:0] wire_pcm_right=wire_round_right>22'sd32767 ? 16'h7fff : wire_round_right< -22'sd32768 ? 16'h8000 : wire_round_right[15:0];
    wire signed [16:0] wire_mix_left=$signed({wire_pcm_left[15],wire_pcm_left})+$signed({i_click[15],i_click});
    wire signed [16:0] wire_mix_right=$signed({wire_pcm_right[15],wire_pcm_right})+$signed({i_click[15],i_click});
    wire [15:0] wire_output_left=C_METRONOME_ENABLE ? (wire_mix_left>32767 ? 16'h7fff : wire_mix_left< -32768 ? 16'h8000 : wire_mix_left[15:0]) : wire_pcm_left;
    wire [15:0] wire_output_right=C_METRONOME_ENABLE ? (wire_mix_right>32767 ? 16'h7fff : wire_mix_right< -32768 ? 16'h8000 : wire_mix_right[15:0]) : wire_pcm_right;
    assign o_ready=cnt_frame==0;
    assign o_sample_valid=o_ready && i_valid;
    assign o_sample=wire_output_left;
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
                    reg_left<=wire_output_left;reg_right<=wire_output_right;flag_started<=1;cnt_frames<=cnt_frames+1'b1;
                end else begin
                    reg_left<=0;reg_right<=0;
                    if (flag_started) cnt_underruns<=cnt_underruns+1'b1;
                end
            end
            if (cnt_frame[4:0]==1) reg_serial<=cnt_frame[9] ? reg_right[15-cnt_frame[8:5]] : reg_left[15-cnt_frame[8:5]];
        end
    end
endmodule
