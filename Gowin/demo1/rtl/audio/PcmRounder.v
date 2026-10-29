`timescale 1ns / 1ps
// PcmRounder: symmetric half-away-from-zero rounding and signed saturation.
// 二十四位音频转换到十六位，正负半值对称处理，满幅正端饱和。
module PcmRounder (
    input signed [23:0] i_sample,
    output signed [15:0] o_sample
);
    wire signed [24:0] enc_extended;
    wire [24:0] enc_magnitude;
    wire [24:0] enc_biased;
    wire signed [16:0] enc_rounded;
    reg signed [15:0] dec_sample;
    assign enc_extended = {i_sample[23], i_sample};
    assign enc_magnitude = i_sample[23] ? -enc_extended : enc_extended;
    assign enc_biased = enc_magnitude + 25'd128;
    assign enc_rounded = i_sample[23] ? -$signed(enc_biased[24:8]) : $signed(enc_biased[24:8]);
    assign o_sample = dec_sample;
    always @(*) begin
        if (enc_rounded > 17'sd32767) dec_sample = 16'sh7fff;
        else if (enc_rounded < -17'sd32768) dec_sample = 16'sh8000;
        else dec_sample = enc_rounded[15:0];
    end
endmodule
