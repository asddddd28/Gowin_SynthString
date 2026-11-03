`timescale 1ns / 1ps
// Global stereo lowpass / 全局双声道低通与Cutoff LFO。
// Contract: voice-system/filter/CONTRACT.md; spec/AxisMasterLowpass_spec.md.
module AxisMasterLowpass #(parameter C_TOUCH_ENABLE=0)(
    input [19:0] i_touch_cutoff,input i_touch_cutoff_active,
    input i_clk,
    input i_rstn,
    input [383:0] i_command,
    input [31:0] i_tag,
    input [7:0] i_opcode,
    input i_command_valid,
    output o_command_ready,
    output [127:0] o_result,
    output [31:0] o_tag,
    output [7:0] o_opcode,
    output o_result_valid,
    input i_result_ready,
    input [63:0] i_audio,
    input [31:0] i_frame,
    input i_audio_valid,
    output o_audio_ready,
    output [63:0] o_audio,
    output [31:0] o_frame,
    output o_audio_valid,
    input i_audio_ready
);
    localparam COMMAND_IDLE=0,COMMAND_CHECK=1,COMMAND_APPLY=2,COMMAND_REPLY=3;
    localparam AUDIO_IDLE=0,AUDIO_WAVE=1,AUDIO_DEPTH=2,AUDIO_TARGET=3,AUDIO_CLAMP=4;
    localparam AUDIO_SMOOTH=5,AUDIO_LOOKUP=6,AUDIO_SELECT=7,AUDIO_MULTIPLY=8;
    localparam AUDIO_ACCUMULATE=9,AUDIO_COMMIT=10,AUDIO_REPLY=11;
    reg [1:0] reg_command_state,next_command_state;
    reg [3:0] reg_audio_state,next_audio_state;
    reg [159:0] reg_command;
    reg [31:0] reg_tag,reg_revision;
    reg [7:0] reg_opcode;
    reg flag_address_bad,flag_command_good;
    reg [127:0] reg_result;
    reg [2:0] reg_flags;
    reg [17:0] reg_base,reg_depth;
    reg [31:0] reg_increment;
    reg [2:0] reg_frame_flags;
    reg [17:0] reg_frame_base,reg_frame_depth;
    reg signed [19:0] reg_frame_touch;
    reg signed [31:0] reg_adjusted_base;
    reg [31:0] reg_phase,reg_frame;
    reg signed [31:0] reg_left,reg_right,reg_output_left,reg_output_right;
    reg signed [31:0] reg_left_first,reg_left_second,reg_right_first,reg_right_second;
    (* syn_romstyle="block_rom" *) reg signed [15:0] mem_sine[0:255];
    (* syn_romstyle="block_rom" *) reg [17:0] mem_alpha[0:1023];
    reg signed [15:0] reg_sine;
    reg [17:0] reg_alpha;
    reg signed [34:0] reg_depth_product;
    reg signed [31:0] reg_target_sum;
    reg [17:0] reg_target,reg_cutoff;
    reg [18:0] reg_mix,reg_coefficient;
    reg [2:0] reg_operation;
    reg signed [32:0] reg_difference;
    reg signed [31:0] reg_origin,reg_value;
    reg signed [52:0] reg_product;
    wire signed [16:0] wire_triangle=reg_phase[31] ? 17'sd32767-$signed({1'b0,reg_phase[30:16],1'b0}) : -17'sd32767+$signed({1'b0,reg_phase[30:16],1'b0});
    wire signed [15:0] wire_wave=reg_frame_flags[2] ? wire_triangle[15:0] : reg_sine;
    wire [17:0] wire_distance=reg_target>reg_cutoff ? reg_target-reg_cutoff : reg_cutoff-reg_target;
    wire [17:0] wire_step=wire_distance<256 ? 18'd1 : {8'd0,wire_distance[17:8]};
    initial begin
        $readmemh("rom/lowpass_sine.hex",mem_sine);
        $readmemh("rom/lowpass_alpha.hex",mem_alpha);
    end
    assign o_command_ready=reg_command_state==COMMAND_IDLE;
    assign o_result_valid=reg_command_state==COMMAND_REPLY;
    assign o_result=reg_result;
    assign o_tag=reg_tag;
    assign o_opcode=reg_opcode;
    assign o_audio_ready=reg_audio_state==AUDIO_IDLE;
    assign o_audio_valid=reg_audio_state==AUDIO_REPLY;
    assign o_audio={reg_output_right,reg_output_left};
    assign o_frame=reg_frame;
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin reg_command_state<=COMMAND_IDLE;reg_audio_state<=AUDIO_IDLE;end
        else begin reg_command_state<=next_command_state;reg_audio_state<=next_audio_state;end
    end
    always @(*) begin
        next_command_state=reg_command_state;
        case(reg_command_state)
            COMMAND_IDLE:if(i_command_valid)next_command_state=COMMAND_CHECK;
            COMMAND_CHECK:next_command_state=COMMAND_APPLY;
            COMMAND_APPLY:next_command_state=COMMAND_REPLY;
            COMMAND_REPLY:if(i_result_ready)next_command_state=COMMAND_IDLE;
            default:next_command_state=COMMAND_IDLE;
        endcase
    end
    // Configuration ACK and audio processing have independent state machines.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            reg_command<=0;reg_tag<=0;reg_opcode<=0;flag_address_bad<=0;flag_command_good<=0;reg_result<=0;
            reg_flags<=0;reg_base<=177296;reg_depth<=0;reg_increment<=87961;reg_revision<=0;
        end else case(reg_command_state)
            COMMAND_IDLE:if(i_command_valid)begin
                reg_command<=i_command[159:0];reg_tag<=i_tag;reg_opcode<=i_opcode;flag_address_bad<=i_command[327:320]!=0;
            end
            COMMAND_CHECK:begin
                flag_command_good<=!flag_address_bad && reg_command[31:3]==0 && reg_command[63:32]<=261888 &&
                    reg_command[95:64]>=4398 && reg_command[95:64]<=1759219 && reg_command[127:96]<=160114 && reg_command[159:128]!=0;
            end
            COMMAND_APPLY:begin
                reg_result<=0;
                if(reg_opcode==8'hd0 && flag_command_good)begin
                    reg_flags<=reg_command[2:0];reg_base<=reg_command[49:32];reg_increment<=reg_command[95:64];
                    reg_depth<=reg_command[113:96];reg_revision<=reg_command[159:128];
                    reg_result[31:0]<=reg_command[31:0];reg_result[63:32]<=reg_command[159:128];reg_result[127:96]<={14'd0,reg_cutoff};
                end else if(reg_opcode==8'hd1 && !flag_address_bad)begin
                    reg_result[31:0]<={29'd0,reg_flags};reg_result[63:32]<=reg_revision;reg_result[127:96]<={14'd0,reg_cutoff};
                end else reg_result[71:64]<=1;
            end
            default:begin end
        endcase
    end
    always @(*) begin
        next_audio_state=reg_audio_state;
        case(reg_audio_state)
            AUDIO_IDLE:if(i_audio_valid)next_audio_state=AUDIO_WAVE;
            AUDIO_WAVE:next_audio_state=AUDIO_DEPTH;
            AUDIO_DEPTH:next_audio_state=AUDIO_TARGET;
            AUDIO_TARGET:next_audio_state=AUDIO_CLAMP;
            AUDIO_CLAMP:next_audio_state=AUDIO_SMOOTH;
            AUDIO_SMOOTH:next_audio_state=AUDIO_LOOKUP;
            AUDIO_LOOKUP:next_audio_state=AUDIO_SELECT;
            AUDIO_SELECT:next_audio_state=AUDIO_MULTIPLY;
            AUDIO_MULTIPLY:next_audio_state=AUDIO_ACCUMULATE;
            AUDIO_ACCUMULATE:next_audio_state=AUDIO_COMMIT;
            AUDIO_COMMIT:next_audio_state=reg_operation==5 ? AUDIO_REPLY : AUDIO_SELECT;
            AUDIO_REPLY:if(i_audio_ready)next_audio_state=AUDIO_IDLE;
            default:next_audio_state=AUDIO_IDLE;
        endcase
    end
    always @(posedge i_clk) begin
        if(reg_audio_state==AUDIO_WAVE)reg_sine<=mem_sine[reg_phase[31:24]];
        if(reg_audio_state==AUDIO_LOOKUP)reg_alpha<=mem_alpha[reg_cutoff[17:8]];
    end
    // Two poles and two crossfades reuse a single registered audio multiplier.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn)begin
            reg_frame_touch<=0;reg_adjusted_base<=177296;reg_frame_flags<=0;reg_frame_base<=177296;reg_frame_depth<=0;reg_phase<=0;reg_frame<=0;
            reg_left<=0;reg_right<=0;reg_output_left<=0;reg_output_right<=0;
            reg_left_first<=0;reg_left_second<=0;reg_right_first<=0;reg_right_second<=0;
            reg_depth_product<=0;reg_target_sum<=177296;reg_target<=177296;reg_cutoff<=177296;
            reg_mix<=0;reg_coefficient<=0;reg_operation<=0;reg_difference<=0;reg_origin<=0;reg_value<=0;reg_product<=0;
        end else case(reg_audio_state)
            AUDIO_IDLE:if(i_audio_valid)begin
                reg_frame_touch<=C_TOUCH_ENABLE ? i_touch_cutoff : 20'd0;reg_frame_flags<=reg_flags | ((C_TOUCH_ENABLE && i_touch_cutoff_active) ? 3'd1 : 3'd0);reg_frame_base<=reg_base;reg_frame_depth<=reg_depth;
                reg_phase<=reg_phase+reg_increment;reg_frame<=i_frame;reg_left<=i_audio[31:0];reg_right<=i_audio[63:32];reg_operation<=0;
            end
            AUDIO_WAVE:reg_adjusted_base<=$signed({14'd0,reg_frame_base})+reg_frame_touch;
            AUDIO_DEPTH:reg_depth_product<=wire_wave*$signed({1'b0,reg_frame_depth});
            AUDIO_TARGET:reg_target_sum<=reg_adjusted_base+(reg_frame_flags[1] ? (reg_depth_product>>>15) : 35'sd0);
            AUDIO_CLAMP:begin
                if(reg_target_sum<0)reg_target<=0;
                else if(reg_target_sum>261888)reg_target<=261888;
                else reg_target<=reg_target_sum[17:0];
            end
            AUDIO_SMOOTH:begin
                if(reg_target>reg_cutoff)reg_cutoff<=reg_cutoff+wire_step;
                else if(reg_target<reg_cutoff)reg_cutoff<=reg_cutoff-wire_step;
                if(reg_frame_flags[0])begin if(reg_mix<262144)reg_mix<=reg_mix+19'd1024;end
                else if(reg_mix!=0)reg_mix<=reg_mix-19'd1024;
            end
            AUDIO_SELECT:begin
                reg_coefficient<=reg_operation<4 ? {1'b0,reg_alpha} : reg_mix;
                case(reg_operation)
                    0:begin reg_difference<=$signed({reg_left[31],reg_left})-$signed({reg_left_first[31],reg_left_first});reg_origin<=reg_left_first;end
                    1:begin reg_difference<=$signed({reg_left_first[31],reg_left_first})-$signed({reg_left_second[31],reg_left_second});reg_origin<=reg_left_second;end
                    2:begin reg_difference<=$signed({reg_right[31],reg_right})-$signed({reg_right_first[31],reg_right_first});reg_origin<=reg_right_first;end
                    3:begin reg_difference<=$signed({reg_right_first[31],reg_right_first})-$signed({reg_right_second[31],reg_right_second});reg_origin<=reg_right_second;end
                    4:begin reg_difference<=$signed({reg_left_second[31],reg_left_second})-$signed({reg_left[31],reg_left});reg_origin<=reg_left;end
                    default:begin reg_difference<=$signed({reg_right_second[31],reg_right_second})-$signed({reg_right[31],reg_right});reg_origin<=reg_right;end
                endcase
            end
            AUDIO_MULTIPLY:reg_product<=reg_difference*$signed({1'b0,reg_coefficient});
            AUDIO_ACCUMULATE:reg_value<=reg_origin+(reg_product>>>18);
            AUDIO_COMMIT:begin
                reg_operation<=reg_operation+1'b1;
                case(reg_operation)
                    0:reg_left_first<=reg_value;
                    1:reg_left_second<=reg_value;
                    2:reg_right_first<=reg_value;
                    3:reg_right_second<=reg_value;
                    4:reg_output_left<=reg_value;
                    default:reg_output_right<=reg_value;
                endcase
            end
            default:begin end
        endcase
    end
endmodule
