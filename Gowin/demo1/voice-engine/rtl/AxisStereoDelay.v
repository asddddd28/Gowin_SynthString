`timescale 1ns / 1ps
// Stereo delay / 立体声延迟. Contract: spec/AxisStereoDelay_spec.md.
// Memory owns the feedback history; clear invalidates history without resetting RAM.
module AxisStereoDelay #(parameter C_DELAY_ADDR_BITS=15)(
    input i_axis_aclk,
    input i_axis_arstn,
    input [63:0] i_s_axis_tdata,
    input [31:0] i_s_axis_tuser,
    input i_s_axis_tvalid,
    output o_s_axis_tready,
    output [63:0] o_m_axis_tdata,
    output [31:0] o_m_axis_tuser,
    output o_m_axis_tvalid,
    input i_m_axis_tready,
    input [159:0] i_config,
    input i_clear,
    output o_clipped
);
    localparam signed [31:0] UNITY = 32'sd67108864;
    localparam IDLE=0, READ_A=1, CAPTURE_A=2, READ_B=3, CAPTURE_B=4;
    localparam INTERPOLATE=5, ECHO=6, FEEDBACK=7, SUM=8, WRITE=9, MIX=10, HOLD=11;
    reg [3:0] reg_state;
    reg [3:0] next_state;
    localparam C_DELAY_DEPTH=1<<C_DELAY_ADDR_BITS;
    reg signed [17:0] mem_left [0:C_DELAY_DEPTH-1];
    reg signed [17:0] mem_right [0:C_DELAY_DEPTH-1];
    reg signed [17:0] reg_read_left;
    reg signed [17:0] reg_read_right;
    reg [C_DELAY_ADDR_BITS-1:0] reg_pointer;
    reg [C_DELAY_ADDR_BITS:0] cnt_fill;
    reg [31:0] reg_time_left;
    reg [31:0] reg_time_right;
    reg signed [31:0] reg_feedback;
    reg signed [31:0] reg_wet;
    reg flag_enable;
    reg flag_pingpong;
    reg signed [31:0] reg_dry_left;
    reg signed [31:0] reg_dry_right;
    reg signed [31:0] reg_a_left;
    reg signed [31:0] reg_a_right;
    reg signed [31:0] reg_b_left;
    reg signed [31:0] reg_b_right;
    reg signed [49:0] reg_interpolate_left;
    reg signed [49:0] reg_interpolate_right;
    reg signed [31:0] reg_echo_left;
    reg signed [31:0] reg_echo_right;
    reg signed [63:0] reg_feedback_left;
    reg signed [63:0] reg_feedback_right;
    reg signed [64:0] reg_sum_left;
    reg signed [64:0] reg_sum_right;
    reg signed [64:0] reg_mix_left;
    reg signed [64:0] reg_mix_right;
    reg [63:0] reg_result;
    reg [31:0] reg_tag;
    reg flag_clip;
    wire [C_DELAY_ADDR_BITS-1:0] wire_read_left = reg_pointer-reg_time_left[C_DELAY_ADDR_BITS+15:16]-(reg_state==READ_B);
    wire [C_DELAY_ADDR_BITS-1:0] wire_read_right = reg_pointer-reg_time_right[C_DELAY_ADDR_BITS+15:16]-(reg_state==READ_B);
    wire signed [31:0] wire_inject_left = flag_enable ? reg_dry_left : 32'sd0;
    wire signed [31:0] wire_inject_right = flag_enable ? reg_dry_right : 32'sd0;
    wire signed [32:0] wire_difference_left = {reg_b_left[31],reg_b_left}-{reg_a_left[31],reg_a_left};
    wire signed [32:0] wire_difference_right = {reg_b_right[31],reg_b_right}-{reg_a_right[31],reg_a_right};
    wire signed [64:0] wire_quant_left = reg_sum_left<0 ? -((-reg_sum_left)>>>36) : reg_sum_left>>>36;
    wire signed [64:0] wire_quant_right = reg_sum_right<0 ? -((-reg_sum_right)>>>36) : reg_sum_right>>>36;
    wire signed [17:0] wire_store_left = wire_quant_left>131071 ? 18'sd131071 : wire_quant_left< -131072 ? -18'sd131072 : wire_quant_left[17:0];
    wire signed [17:0] wire_store_right = wire_quant_right>131071 ? 18'sd131071 : wire_quant_right< -131072 ? -18'sd131072 : wire_quant_right[17:0];
    wire signed [64:0] wire_mix_left = reg_mix_left>>>26;
    wire signed [64:0] wire_mix_right = reg_mix_right>>>26;
    wire signed [63:0] wire_dry_product_left=reg_dry_left*(UNITY-reg_wet);
    wire signed [63:0] wire_dry_product_right=reg_dry_right*(UNITY-reg_wet);
    wire signed [63:0] wire_wet_product_left=reg_echo_left*reg_wet;
    wire signed [63:0] wire_wet_product_right=reg_echo_right*reg_wet;
    wire signed [63:0] wire_inject_product_left=wire_inject_left*UNITY;
    wire signed [63:0] wire_inject_product_right=wire_inject_right*UNITY;
    wire signed [49:0] wire_echo_left=reg_a_left+(reg_interpolate_left>>>16);
    wire signed [49:0] wire_echo_right=reg_a_right+(reg_interpolate_right>>>16);
    assign o_s_axis_tready = reg_state==IDLE && !i_clear;
    assign o_m_axis_tvalid = reg_state==HOLD;
    assign o_m_axis_tdata = reg_result;
    assign o_m_axis_tuser = reg_tag;
    assign o_clipped = flag_clip;

    // True synchronous RAM ports. Writes occur once, before result backpressure.
    always @(posedge i_axis_aclk) begin
        if (reg_state==READ_A || reg_state==READ_B) begin
            reg_read_left<=mem_left[wire_read_left];
            reg_read_right<=mem_right[wire_read_right];
        end
        if (reg_state==WRITE) begin
            mem_left[reg_pointer]<=wire_store_left;
            mem_right[reg_pointer]<=wire_store_right;
        end
    end
    always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
        if (!i_axis_arstn) reg_state<=IDLE;
        else reg_state<=next_state;
    end
    always @(*) begin
        next_state=reg_state;
        case (reg_state)
            IDLE: if (i_s_axis_tvalid && o_s_axis_tready) next_state=READ_A;
            READ_A: next_state=CAPTURE_A;
            CAPTURE_A: next_state=READ_B;
            READ_B: next_state=CAPTURE_B;
            CAPTURE_B: next_state=INTERPOLATE;
            INTERPOLATE: next_state=ECHO;
            ECHO: next_state=FEEDBACK;
            FEEDBACK: next_state=SUM;
            SUM: next_state=WRITE;
            WRITE: next_state=MIX;
            MIX: next_state=HOLD;
            HOLD: if (i_m_axis_tready) next_state=IDLE;
            default: next_state=IDLE;
        endcase
    end
    always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
        if (!i_axis_arstn) begin
            reg_pointer<=0;
            cnt_fill<=0;
            reg_time_left<=65536;
            reg_time_right<=65536;
            reg_feedback<=0;
            reg_wet<=0;
            flag_enable<=0;
            flag_pingpong<=0;
            reg_dry_left<=0;
            reg_dry_right<=0;
            reg_a_left<=0;
            reg_a_right<=0;
            reg_b_left<=0;
            reg_b_right<=0;
            reg_interpolate_left<=0;
            reg_interpolate_right<=0;
            reg_echo_left<=0;
            reg_echo_right<=0;
            reg_feedback_left<=0;
            reg_feedback_right<=0;
            reg_sum_left<=0;
            reg_sum_right<=0;
            reg_mix_left<=0;
            reg_mix_right<=0;
            reg_result<=0;
            reg_tag<=0;
            flag_clip<=0;
        end else begin
            if (i_clear && reg_state==IDLE) begin
                reg_pointer<=0;
                cnt_fill<=0;
            end
            case (reg_state)
                IDLE: if (i_s_axis_tvalid && o_s_axis_tready) begin
                    reg_dry_left<=i_s_axis_tdata[31:0];
                    reg_dry_right<=i_s_axis_tdata[63:32];
                    reg_tag<=i_s_axis_tuser;
                    reg_time_left<=i_config[31:0];
                    reg_time_right<=i_config[63:32];
                    reg_feedback<=i_config[95:64];
                    reg_wet<=i_config[128] ? i_config[127:96] : 32'd0;
                    flag_enable<=i_config[128];
                    flag_pingpong<=i_config[129];
                    flag_clip<=0;
                end
                CAPTURE_A: begin
                    reg_a_left<=cnt_fill>=reg_time_left[31:16] ? $signed({reg_read_left,10'd0}) : 32'sd0;
                    reg_a_right<=cnt_fill>=reg_time_right[31:16] ? $signed({reg_read_right,10'd0}) : 32'sd0;
                end
                CAPTURE_B: begin
                    reg_b_left<=cnt_fill>reg_time_left[31:16] ? $signed({reg_read_left,10'd0}) : 32'sd0;
                    reg_b_right<=cnt_fill>reg_time_right[31:16] ? $signed({reg_read_right,10'd0}) : 32'sd0;
                end
                INTERPOLATE: begin
                    reg_interpolate_left<=wire_difference_left*$signed({1'b0,reg_time_left[15:0]});
                    reg_interpolate_right<=wire_difference_right*$signed({1'b0,reg_time_right[15:0]});
                end
                ECHO: begin
                    reg_echo_left<=wire_echo_left[31:0];
                    reg_echo_right<=wire_echo_right[31:0];
                end
                FEEDBACK: begin
                    reg_feedback_left<=reg_feedback*(flag_pingpong ? reg_echo_right : reg_echo_left);
                    reg_feedback_right<=reg_feedback*(flag_pingpong ? reg_echo_left : reg_echo_right);
                end
                SUM: begin
                    reg_sum_left<=$signed({wire_inject_product_left[63],wire_inject_product_left})+$signed({reg_feedback_left[63],reg_feedback_left});
                    reg_sum_right<=$signed({wire_inject_product_right[63],wire_inject_product_right})+$signed({reg_feedback_right[63],reg_feedback_right});
                end
                WRITE: begin
                    reg_pointer<=reg_pointer+1'b1;
                    if (cnt_fill<C_DELAY_DEPTH) cnt_fill<=cnt_fill+1'b1;
                    flag_clip<=wire_quant_left>131071 || wire_quant_left< -131072 || wire_quant_right>131071 || wire_quant_right< -131072;
                    reg_mix_left<=$signed({wire_dry_product_left[63],wire_dry_product_left})+$signed({wire_wet_product_left[63],wire_wet_product_left});
                    reg_mix_right<=$signed({wire_dry_product_right[63],wire_dry_product_right})+$signed({wire_wet_product_right[63],wire_wet_product_right});
                end
                MIX: begin
                    reg_result[31:0]<=wire_mix_left>UNITY ? UNITY : wire_mix_left< -UNITY ? -UNITY : wire_mix_left[31:0];
                    reg_result[63:32]<=wire_mix_right>UNITY ? UNITY : wire_mix_right< -UNITY ? -UNITY : wire_mix_right[31:0];
                    flag_clip<=flag_clip || wire_mix_left>UNITY || wire_mix_left< -UNITY || wire_mix_right>UNITY || wire_mix_right< -UNITY;
                end
                default: flag_clip<=flag_clip;
            endcase
        end
    end
endmodule
