`timescale 1ns / 1ps
// OutputGain: explicit output headroom gain, smooth control and saturation telemetry.
// 输出增益不随声部数量自动变化；每采样平滑调整，削波会计数。
module OutputGain (
    input i_clk, input i_rstn, input i_panic,
    input i_gain_write, input [2:0] i_shift,
    input i_sample_valid, input signed [23:0] i_sample,
    output o_sample_valid, output signed [23:0] o_sample,
    output [31:0] o_clips
);
    reg [20:0] reg_gain, reg_target;
    reg signed [45:0] reg_product;
    reg flag_product_valid, flag_valid_o;
    reg signed [23:0] reg_sample_o;
    reg [31:0] cnt_clips;
    wire [46:0] enc_magnitude;
    wire [46:0] enc_biased;
    wire signed [30:0] enc_rounded;
    assign enc_magnitude = reg_product[45] ? -$signed({reg_product[45], reg_product}) : {reg_product[45], reg_product};
    assign enc_biased = enc_magnitude + 47'd32768;
    assign enc_rounded = reg_product[45] ? -$signed(enc_biased[46:16]) : $signed(enc_biased[46:16]);
    assign o_sample = reg_sample_o;
    assign o_sample_valid = flag_valid_o;
    assign o_clips = cnt_clips;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            reg_gain <= 21'd65536;
            reg_target <= 21'd65536;
        end else begin
            if (i_gain_write && i_shift <= 4) reg_target <= 21'd65536 << i_shift;
            if (i_sample_valid && !i_panic) begin
                if (reg_gain < reg_target) begin
                    if (reg_target-reg_gain <= 256) reg_gain <= reg_target;
                    else reg_gain <= reg_gain + 21'd256;
                end else if (reg_gain > reg_target) begin
                    if (reg_gain-reg_target <= 256) reg_gain <= reg_target;
                    else reg_gain <= reg_gain - 21'd256;
                end
            end
        end
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            reg_product <= 0;
            flag_product_valid <= 0;
            flag_valid_o <= 0;
            reg_sample_o <= 0;
            cnt_clips <= 0;
        end else if (i_panic) begin
            flag_product_valid <= 0;
            flag_valid_o <= 1;
            reg_sample_o <= 0;
        end else begin
            flag_product_valid <= i_sample_valid;
            flag_valid_o <= flag_product_valid;
            if (i_sample_valid) reg_product <= i_sample * $signed({1'b0, reg_gain});
            if (flag_product_valid) begin
                if (enc_rounded > 31'sd8388607) begin
                    reg_sample_o <= 24'sh7fffff;
                    cnt_clips <= cnt_clips + 1'b1;
                end else if (enc_rounded < -31'sd8388608) begin
                    reg_sample_o <= 24'sh800000;
                    cnt_clips <= cnt_clips + 1'b1;
                end else reg_sample_o <= enc_rounded[23:0];
            end
        end
    end
endmodule
