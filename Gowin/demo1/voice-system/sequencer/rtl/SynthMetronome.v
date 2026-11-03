`timescale 1ns / 1ps
// Quiet monitor click / 独立节拍监听音，固定采样消费，不占合成声部。
module SynthMetronome(
    input i_clk,
    input i_rstn,
    input i_sample,
    input i_running,
    input i_click,
    input i_accent,
    output [15:0] o_sample
);
    reg [23:0] reg_phase,reg_increment;
    reg [10:0] reg_envelope;
    reg signed [15:0] reg_sample_o;
    wire signed [15:0] wire_target=reg_phase[23] ? -$signed({5'd0,reg_envelope}) : $signed({5'd0,reg_envelope});
    wire signed [16:0] wire_error=$signed(wire_target)-$signed(reg_sample_o);
    assign o_sample=reg_sample_o;
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin reg_phase<=0;reg_increment<=0;reg_envelope<=0;reg_sample_o<=0;end
        else if(!i_running)begin reg_envelope<=0;reg_sample_o<=0;reg_phase<=0;end
        else if(i_click)begin
            reg_phase<=0;reg_increment<=i_accent ? 24'd453548 : 24'd302366;
            reg_envelope<=i_accent ? 11'd1536 : 11'd1024;
        end else if(i_sample)begin
            reg_phase<=reg_phase+reg_increment;
            if(reg_envelope!=0)reg_envelope<=reg_envelope-1'b1;
            reg_sample_o<=reg_sample_o+(wire_error>>>3);
        end
    end
endmodule
