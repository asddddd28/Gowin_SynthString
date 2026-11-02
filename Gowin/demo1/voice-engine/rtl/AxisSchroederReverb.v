`timescale 1ns / 1ps
// Shared reverberator / 共享混响器. Contract: spec/AxisSchroederReverb_spec.md.
// Four lowpass combs feed two true allpasses per channel; mono excitation, stereo tail.
module AxisSchroederReverb(
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
    input [127:0] i_config,
    input i_clear,
    output o_clipped
);
    localparam signed [31:0] UNITY=32'sd67108864;
    localparam signed [31:0] HALF=32'sd33554432;
    localparam IDLE=0, READ=1, FETCH=2, PRODUCT=3, FILTER=4, FEEDBACK=5;
    localparam SUM=6, WRITE=7, PREPARE=8, MIX=9, OUTPUT_SAMPLE=10, HOLD=11, MIX_RIGHT=12;
    reg [3:0] reg_state;
    reg [3:0] next_state;
    reg signed [17:0] mem_tank [0:10239];
    reg signed [17:0] reg_read;
    reg [10:0] reg_pointer [0:7];
    reg signed [31:0] reg_lowpass [0:3];
    reg [11:0] cnt_age;
    reg [2:0] reg_line;
    reg [10:0] reg_length;
    reg [13:0] reg_base;
    reg signed [31:0] reg_feedback;
    reg signed [31:0] reg_damping;
    reg signed [31:0] reg_wet;
    reg signed [31:0] reg_dry_coefficient;
    reg signed [31:0] reg_damping_complement;
    reg signed [31:0] reg_feedback_complement;
    reg signed [31:0] dec_factor_first, dec_factor_second;
    reg signed [31:0] dec_sample_first, dec_sample_second;
    reg signed [31:0] reg_dry_left;
    reg signed [31:0] reg_dry_right;
    reg signed [31:0] reg_mono;
    reg signed [31:0] reg_delayed;
    reg signed [31:0] reg_lp;
    reg signed [31:0] reg_signal;
    reg signed [31:0] reg_feed;
    reg signed [31:0] reg_allpass;
    reg signed [31:0] reg_tail_left;
    reg signed [31:0] reg_tail_right;
    reg signed [34:0] reg_comb_sum;
    reg signed [63:0] reg_product_a;
    reg signed [63:0] reg_product_b;
    reg signed [64:0] reg_sum;
    reg signed [64:0] reg_mix_left;
    reg signed [64:0] reg_mix_right;
    reg [63:0] reg_result;
    reg [31:0] reg_tag;
    reg flag_clip;
    integer index;
    wire [13:0] wire_address=reg_base+reg_pointer[reg_line];
    wire signed [32:0] wire_input_sum=$signed({i_s_axis_tdata[31],i_s_axis_tdata[31:0]})+$signed({i_s_axis_tdata[63],i_s_axis_tdata[63:32]});
    wire signed [64:0] wire_filter_sum=$signed({reg_product_a[63],reg_product_a})+$signed({reg_product_b[63],reg_product_b});
    wire signed [64:0] wire_lp=wire_filter_sum<0 ? -((-wire_filter_sum)>>>26) : wire_filter_sum>>>26;
    wire signed [64:0] wire_allpass=reg_sum<0 ? -((-reg_sum)>>>26) : reg_sum>>>26;
    wire signed [64:0] wire_quant=reg_sum<0 ? -((-reg_sum)>>>36) : reg_sum>>>36;
    wire signed [17:0] wire_store=wire_quant>131071 ? 18'sd131071 : wire_quant< -131072 ? -18'sd131072 : wire_quant[17:0];
    wire signed [64:0] wire_mix_left=reg_mix_left>>>26;
    wire signed [64:0] wire_mix_right=reg_mix_right>>>26;
    wire signed [63:0] wire_allpass_delayed=reg_delayed*UNITY;
    wire signed [63:0] wire_allpass_signal=reg_signal*HALF;
    wire signed [63:0] wire_write_signal=reg_signal*UNITY;
    wire signed [63:0] wire_write_allpass=reg_allpass*HALF;
    wire signed [63:0] wire_shared_product_first=dec_factor_first*dec_sample_first;
    wire signed [63:0] wire_shared_product_second=dec_factor_second*dec_sample_second;
    wire signed [64:0] wire_shared_sum=$signed({wire_shared_product_first[63],wire_shared_product_first})+
        $signed({wire_shared_product_second[63],wire_shared_product_second});
    assign o_s_axis_tready=reg_state==IDLE && !i_clear;
    assign o_m_axis_tvalid=reg_state==HOLD;
    assign o_m_axis_tdata=reg_result;
    assign o_m_axis_tuser=reg_tag;
    assign o_clipped=flag_clip;

    // All phases use the same two physical multiplier lanes. Explicit operand
    // widths avoid expression-context widening of (UNITY-coefficient)*sample.
    always @(*) begin
        dec_factor_first=0;dec_factor_second=0;dec_sample_first=0;dec_sample_second=0;
        case (reg_state)
            PRODUCT: begin
                dec_factor_first=reg_damping_complement;dec_sample_first=reg_delayed;
                dec_factor_second=reg_damping;dec_sample_second=reg_lowpass[reg_line[1:0]];
            end
            FEEDBACK: begin
                dec_factor_first=reg_feedback_complement;dec_sample_first=reg_mono;
                dec_factor_second=reg_feedback;dec_sample_second=reg_lp;
            end
            MIX: begin
                dec_factor_first=reg_dry_coefficient;dec_sample_first=reg_dry_left;
                dec_factor_second=reg_wet;dec_sample_second=reg_tail_left;
            end
            MIX_RIGHT: begin
                dec_factor_first=reg_dry_coefficient;dec_sample_first=reg_dry_right;
                dec_factor_second=reg_wet;dec_sample_second=reg_tail_right;
            end
            default: begin end
        endcase
    end

    // The selected line has a private pointer but shares one physical memory port.
    always @(*) begin
        case (reg_line)
            0: begin reg_base=0; reg_length=1493; end
            1: begin reg_base=2048; reg_length=1601; end
            2: begin reg_base=4096; reg_length=1747; end
            3: begin reg_base=6144; reg_length=1999; end
            4: begin reg_base=8192; reg_length=211; end
            5: begin reg_base=8704; reg_length=431; end
            6: begin reg_base=9216; reg_length=263; end
            default: begin reg_base=9728; reg_length=487; end
        endcase
    end
    always @(posedge i_axis_aclk) begin
        if (reg_state==READ) reg_read<=mem_tank[wire_address];
        if (reg_state==WRITE) mem_tank[wire_address]<=wire_store;
    end
    always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
        if (!i_axis_arstn) reg_state<=IDLE;
        else reg_state<=next_state;
    end
    always @(*) begin
        next_state=reg_state;
        case (reg_state)
            IDLE: if (i_s_axis_tvalid && o_s_axis_tready) next_state=READ;
            READ: next_state=FETCH;
            FETCH: next_state=PRODUCT;
            PRODUCT: next_state=FILTER;
            FILTER: next_state=FEEDBACK;
            FEEDBACK: next_state=SUM;
            SUM: next_state=WRITE;
            WRITE: if (reg_line==7) next_state=MIX;
                else if (reg_line==3) next_state=PREPARE;
                else next_state=READ;
            PREPARE: next_state=READ;
            MIX: next_state=MIX_RIGHT;
            MIX_RIGHT: next_state=OUTPUT_SAMPLE;
            OUTPUT_SAMPLE: next_state=HOLD;
            HOLD: if (i_m_axis_tready) next_state=IDLE;
            default: next_state=IDLE;
        endcase
    end
    always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
        if (!i_axis_arstn) begin
            for (index=0; index<8; index=index+1) reg_pointer[index]<=0;
            for (index=0; index<4; index=index+1) reg_lowpass[index]<=0;
            cnt_age<=0;
            reg_line<=0;
            reg_feedback<=0;
            reg_damping<=0;
            reg_wet<=0;reg_dry_coefficient<=UNITY;reg_damping_complement<=UNITY;reg_feedback_complement<=UNITY;
            reg_dry_left<=0;
            reg_dry_right<=0;
            reg_mono<=0;
            reg_delayed<=0;
            reg_lp<=0;
            reg_signal<=0;
            reg_feed<=0;
            reg_allpass<=0;
            reg_tail_left<=0;
            reg_tail_right<=0;
            reg_comb_sum<=0;
            reg_product_a<=0;
            reg_product_b<=0;
            reg_sum<=0;
            reg_mix_left<=0;
            reg_mix_right<=0;
            reg_result<=0;
            reg_tag<=0;
            flag_clip<=0;
        end else begin
            if (i_clear && reg_state==IDLE) begin
                cnt_age<=0;
                for (index=0; index<8; index=index+1) reg_pointer[index]<=0;
                for (index=0; index<4; index=index+1) reg_lowpass[index]<=0;
            end
            case (reg_state)
                IDLE: if (i_s_axis_tvalid && o_s_axis_tready) begin
                    reg_dry_left<=i_s_axis_tdata[31:0];
                    reg_dry_right<=i_s_axis_tdata[63:32];
                    reg_mono<=i_config[96] ? wire_input_sum[32:1] : 32'd0;
                    reg_feedback<=i_config[31:0];
                    reg_damping<=i_config[63:32];
                    reg_wet<=i_config[96] ? i_config[95:64] : 32'd0;
                    reg_dry_coefficient<=i_config[96] ? UNITY-$signed(i_config[95:64]) : UNITY;
                    reg_damping_complement<=UNITY-$signed(i_config[63:32]);
                    reg_feedback_complement<=UNITY-$signed(i_config[31:0]);
                    reg_tag<=i_s_axis_tuser;
                    reg_line<=0;
                    reg_comb_sum<=0;
                    flag_clip<=0;
                end
                FETCH: reg_delayed<=cnt_age>=reg_length ? $signed({reg_read,10'd0}) : 32'sd0;
                PRODUCT: if (reg_line<4) begin
                    reg_product_a<=wire_shared_product_first;
                    reg_product_b<=wire_shared_product_second;
                end else reg_sum<=$signed({wire_allpass_delayed[63],wire_allpass_delayed})-$signed({wire_allpass_signal[63],wire_allpass_signal});
                FILTER: if (reg_line<4) reg_lp<=wire_lp[31:0];
                    else reg_allpass<=wire_allpass[31:0];
                FEEDBACK: if (reg_line<4) begin
                    reg_product_a<=wire_shared_product_first;
                    reg_product_b<=wire_shared_product_second;
                end else reg_sum<=$signed({wire_write_signal[63],wire_write_signal})+$signed({wire_write_allpass[63],wire_write_allpass});
                SUM: if (reg_line<4) reg_sum<=wire_filter_sum;
                WRITE: begin
                    flag_clip<=flag_clip || wire_quant>131071 || wire_quant< -131072;
                    reg_pointer[reg_line]<=reg_pointer[reg_line]==reg_length-1'b1 ? 11'd0 : reg_pointer[reg_line]+1'b1;
                    if (reg_line<4) begin
                        reg_lowpass[reg_line[1:0]]<=reg_lp;
                        reg_comb_sum<=reg_comb_sum+reg_delayed;
                    end else if (reg_line==5) begin
                        reg_tail_left<=reg_allpass;
                        reg_signal<=reg_feed;
                    end else if (reg_line==7) reg_tail_right<=reg_allpass;
                    else reg_signal<=reg_allpass;
                    reg_line<=reg_line+1'b1;
                end
                PREPARE: begin
                    reg_feed<=reg_comb_sum[33:2];
                    reg_signal<=reg_comb_sum[33:2];
                end
                MIX: begin
                    reg_mix_left<=wire_shared_sum;
                    if (cnt_age<2048) cnt_age<=cnt_age+1'b1;
                end
                MIX_RIGHT: reg_mix_right<=wire_shared_sum;
                OUTPUT_SAMPLE: begin
                    reg_result[31:0]<=wire_mix_left>UNITY ? UNITY : wire_mix_left< -UNITY ? -UNITY : wire_mix_left[31:0];
                    reg_result[63:32]<=wire_mix_right>UNITY ? UNITY : wire_mix_right< -UNITY ? -UNITY : wire_mix_right[31:0];
                    flag_clip<=flag_clip || wire_mix_left>UNITY || wire_mix_left< -UNITY || wire_mix_right>UNITY || wire_mix_right< -UNITY;
                end
                default: flag_clip<=flag_clip;
            endcase
        end
    end
endmodule
