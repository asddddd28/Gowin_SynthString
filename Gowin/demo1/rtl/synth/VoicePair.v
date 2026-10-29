`timescale 1ns / 1ps
// VoicePair: two local 16-voice engines avoid the global 32-way register mux.
// 按音符 ID 位 4 分组；参数广播，等待两组同帧结果后才提交混音。
module VoicePair #(parameter C_VOICES=32)(
    input i_clk, input i_rstn, input i_tick, input i_panic,
    input i_table_write, input [10:0] i_table_address, input [15:0] i_table_data,
    input i_table_bank, input i_table_available,
    input i_table_frame,input i_table_two,
    input i_position_write,input [4:0] i_position_address,input [15:0] i_position_data,
    input [4:0] i_position_query,output [15:0] o_position_status,
    input i_pcm_write,input [13:0] i_pcm_address,input [15:0] i_pcm_data,
    input i_pcm_available,input [14:0] i_pcm_loop_start,input [14:0] i_pcm_loop_end,input [6:0] i_pcm_root,
    input i_profile_write,input [4:0] i_profile_address,input [287:0] i_profile_data,
    input i_event_valid, input [55:0] i_event, output o_event_ready,
    output signed [23:0] o_sample, output o_sample_valid, output o_busy,
    output o_overrun, output [7:0] o_active_voices, output [7:0] o_active_oscillators,
    output [15:0] o_max_cycles, output [31:0] o_clip_count,
    output [31:0] o_sample_count, output o_status_request
);
    generate if(C_VOICES!=32) begin: Single_Inst
        VoiceBank #(.C_VOICES(C_VOICES)) Core_Inst(
            .i_table_frame(i_table_frame),.i_table_two(i_table_two),
            .i_position_write(i_position_write&&!i_position_address[4]),.i_position_address(i_position_address[3:0]),.i_position_data(i_position_data),
            .i_position_query(i_position_query[3:0]),.o_position_status(o_position_status),
            .i_pcm_write(i_pcm_write),.i_pcm_address(i_pcm_address),.i_pcm_data(i_pcm_data),
            .i_pcm_available(i_pcm_available),.i_pcm_loop_start(i_pcm_loop_start),.i_pcm_loop_end(i_pcm_loop_end),.i_pcm_root(i_pcm_root),
            .i_profile_write(i_profile_write&&!i_profile_address[4]),.i_profile_address(i_profile_address[3:0]),.i_profile_data(i_profile_data),
            .i_table_write(i_table_write),.i_table_address(i_table_address),.i_table_data(i_table_data),
            .i_table_bank(i_table_bank),.i_table_available(i_table_available),
            .i_clk(i_clk),.i_rstn(i_rstn),.i_tick(i_tick),.i_panic(i_panic),
            .i_event_valid(i_event_valid),.i_event(i_event),.o_event_ready(o_event_ready),
            .o_sample(o_sample),.o_sample_valid(o_sample_valid),.o_busy(o_busy),.o_overrun(o_overrun),
            .o_active_voices(o_active_voices),.o_active_oscillators(o_active_oscillators),
            .o_max_cycles(o_max_cycles),.o_clip_count(o_clip_count),.o_sample_count(o_sample_count),
            .o_status_request(o_status_request));
    end else begin: Pair_Inst
        wire signed [23:0] sample_low, sample_high;
        wire valid_low,valid_high,ready_low,ready_high,busy_low,busy_high,overrun_low,overrun_high;
        wire status_low,status_high;
        wire [7:0] voices_low,voices_high,osc_low,osc_high;
        wire [15:0] cycles_low,cycles_high;
        wire [31:0] clips_low,clips_high;
        wire [15:0] position_low,position_high;
        assign o_position_status=i_position_query[4] ? position_high : position_low;
        wire broadcast_event=(i_event[55:48]!=1)&&(i_event[55:48]!=2);
        reg signed [23:0] reg_low,reg_high,reg_sample_o;
        reg flag_low,flag_high,flag_valid_o,flag_overrun_o;
        reg [31:0] cnt_clips;
        wire signed [24:0] mixed_sample=$signed({reg_low[23],reg_low})+$signed({reg_high[23],reg_high});
        VoiceBank #(.C_VOICES(16)) Low_Inst(
            .i_table_frame(i_table_frame),.i_table_two(i_table_two),
            .i_position_write(i_position_write&&!i_position_address[4]),.i_position_address(i_position_address[3:0]),.i_position_data(i_position_data),
            .i_position_query(i_position_query[3:0]),.o_position_status(position_low),
            .i_pcm_write(i_pcm_write),.i_pcm_address(i_pcm_address),.i_pcm_data(i_pcm_data),
            .i_pcm_available(i_pcm_available),.i_pcm_loop_start(i_pcm_loop_start),.i_pcm_loop_end(i_pcm_loop_end),.i_pcm_root(i_pcm_root),
            .i_profile_write(i_profile_write&&!i_profile_address[4]),.i_profile_address(i_profile_address[3:0]),.i_profile_data(i_profile_data),
            .i_table_write(i_table_write),.i_table_address(i_table_address),.i_table_data(i_table_data),
            .i_table_bank(i_table_bank),.i_table_available(i_table_available),
            .i_clk(i_clk),.i_rstn(i_rstn),.i_tick(i_tick),.i_panic(i_panic),
            .i_event_valid(i_event_valid&&(broadcast_event||!i_event[44])),.i_event(i_event),.o_event_ready(ready_low),
            .o_sample(sample_low),.o_sample_valid(valid_low),.o_busy(busy_low),.o_overrun(overrun_low),
            .o_active_voices(voices_low),.o_active_oscillators(osc_low),.o_max_cycles(cycles_low),
            .o_clip_count(clips_low),.o_sample_count(o_sample_count),.o_status_request(status_low));
        VoiceBank #(.C_VOICES(16)) High_Inst(
            .i_table_frame(i_table_frame),.i_table_two(i_table_two),
            .i_position_write(i_position_write&&i_position_address[4]),.i_position_address(i_position_address[3:0]),.i_position_data(i_position_data),
            .i_position_query(i_position_query[3:0]),.o_position_status(position_high),
            .i_pcm_write(i_pcm_write),.i_pcm_address(i_pcm_address),.i_pcm_data(i_pcm_data),
            .i_pcm_available(i_pcm_available),.i_pcm_loop_start(i_pcm_loop_start),.i_pcm_loop_end(i_pcm_loop_end),.i_pcm_root(i_pcm_root),
            .i_profile_write(i_profile_write&&i_profile_address[4]),.i_profile_address(i_profile_address[3:0]),.i_profile_data(i_profile_data),
            .i_table_write(i_table_write),.i_table_address(i_table_address),.i_table_data(i_table_data),
            .i_table_bank(i_table_bank),.i_table_available(i_table_available),
            .i_clk(i_clk),.i_rstn(i_rstn),.i_tick(i_tick),.i_panic(i_panic),
            .i_event_valid(i_event_valid&&(broadcast_event||i_event[44])),.i_event(i_event),.o_event_ready(ready_high),
            .o_sample(sample_high),.o_sample_valid(valid_high),.o_busy(busy_high),.o_overrun(overrun_high),
            .o_active_voices(voices_high),.o_active_oscillators(osc_high),.o_max_cycles(cycles_high),
            .o_clip_count(clips_high),.o_sample_count(),.o_status_request(status_high));
        // 两组计算可能因单边音符事件相差若干拍；用独立完成位防止串帧。
        always @(posedge i_clk or negedge i_rstn) begin
            if(!i_rstn) begin
                reg_low<=0;reg_high<=0;reg_sample_o<=0;
                flag_low<=0;flag_high<=0;flag_valid_o<=0;flag_overrun_o<=0;cnt_clips<=0;
            end else if(i_panic) begin
                reg_low<=0;reg_high<=0;reg_sample_o<=0;
                flag_low<=0;flag_high<=0;flag_valid_o<=1;
            end else begin
                flag_valid_o<=0;
                if(valid_low) begin reg_low<=sample_low;flag_low<=1;end
                if(valid_high) begin reg_high<=sample_high;flag_high<=1;end
                if(i_tick&&(flag_low||flag_high)) flag_overrun_o<=1;
                if(flag_low&&flag_high) begin
                    flag_low<=0;flag_high<=0;flag_valid_o<=1;
                    if(mixed_sample>25'sd8388607) begin reg_sample_o<=24'sh7fffff;cnt_clips<=cnt_clips+1'b1;end
                    else if(mixed_sample< -25'sd8388608) begin reg_sample_o<=24'sh800000;cnt_clips<=cnt_clips+1'b1;end
                    else reg_sample_o<=mixed_sample[23:0];
                end
            end
        end
        assign o_event_ready=ready_low&&ready_high;
        assign o_sample=reg_sample_o;
        assign o_sample_valid=flag_valid_o;
        assign o_busy=busy_low||busy_high||flag_low||flag_high;
        assign o_overrun=overrun_low||overrun_high||flag_overrun_o;
        assign o_active_voices=voices_low+voices_high;
        assign o_active_oscillators=osc_low+osc_high;
        assign o_max_cycles=((cycles_low>cycles_high)?cycles_low:cycles_high)+16'd2;
        assign o_clip_count=clips_low+clips_high+cnt_clips;
        assign o_status_request=status_low||status_high;
    end endgenerate
endmodule
