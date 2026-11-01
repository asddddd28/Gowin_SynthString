`timescale 1ns / 1ps
// GuitarTracker：原始电极数据到两轴跨弦事件；50 MHz 单时钟。
// 两轴均检测，显示方向由接收端映射，不在电脑重新判定轨迹。
module GuitarTracker (
    input i_clk,
    input i_rstn,
    input [31:0] i_milliseconds,
    input [335:0] i_raw,
    input [15:0] i_sequence,
    input [7:0] i_error,
    output o_event,
    output [5:0] o_mask,
    output [3:0] o_flags,
    output [9:0] o_x,
    output [9:0] o_y,
    output [15:0] o_sequence,
    output [31:0] o_time
);
localparam [3:0] S_IDLE=0, S_EXTRACT=1, S_WEIGHT=2, S_SUM=3,
    S_PREPARE=4, S_DIVIDE=5, S_POSITION=6, S_CROSS=7, S_EMIT=8;
reg [3:0] state,next_state;
reg [335:0] snapshot;
reg [11:0] touch_mask;
reg [3:0] electrode;
reg [9:0] filtered,baseline,center;
reg selected,bad_data,cluster_gap,row_seen,row_closed,column_seen,column_closed;
reg [10:0] weight;
reg [13:0] row_total,column_total;
reg [23:0] row_sum,column_sum,row_remainder,column_remainder;
reg [9:0] row_quotient,column_quotient;
reg [3:0] division_bit;
reg [15:0] seen_sequence,sequence_o;
reg [31:0] time_o,last_sample;
reg [9:0] x_o,y_o,previous_x,previous_y;
reg [5:0] mask_o,side_known,side_positive;
reg [3:0] flags_o;
reg event_o,tracking;
reg [31:0] last_hit [0:5];
reg [5:0] hit_known;
wire continuity = tracking && i_milliseconds-last_sample<=32'd40;
wire [23:0] row_trial = {10'b0,row_total} << division_bit;
wire [23:0] column_trial = {10'b0,column_total} << division_bit;
integer string_index;
assign o_event=event_o;
assign o_mask=mask_o;
assign o_flags=flags_o;
assign o_x=x_o;
assign o_y=y_o;
assign o_sequence=sequence_o;
assign o_time=time_o;

// 三进程状态机；一次计算约50拍，远小于一轮 I2C 读取时间。
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) state<=S_IDLE;
    else if(i_error!=0) state<=S_IDLE;
    else state<=next_state;
end
always @(*) begin
    next_state=state;
    case(state)
        S_IDLE: if(i_sequence!=seen_sequence) next_state=S_EXTRACT;
        S_EXTRACT: next_state=S_WEIGHT;
        S_WEIGHT: next_state=S_SUM;
        S_SUM: next_state=electrode==11 ? S_PREPARE : S_EXTRACT;
        S_PREPARE: next_state=S_DIVIDE;
        S_DIVIDE: if(division_bit==0) next_state=S_POSITION;
        S_POSITION: next_state=S_CROSS;
        S_CROSS: next_state=S_EMIT;
        S_EMIT: next_state=S_IDLE;
        default: next_state=S_IDLE;
    endcase
end

// 顺序积累差值权重，十拍二进制除法避免大组合除法器。
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin
        snapshot<=0; touch_mask<=0; electrode<=0; filtered<=0; baseline<=0; center<=0;
        selected<=0; bad_data<=0; cluster_gap<=0;
        row_seen<=0; row_closed<=0; column_seen<=0; column_closed<=0;
        weight<=0; row_total<=0; column_total<=0; row_sum<=0; column_sum<=0;
        row_remainder<=0; column_remainder<=0; row_quotient<=0; column_quotient<=0;
        division_bit<=0; seen_sequence<=0; sequence_o<=0; time_o<=0; last_sample<=0;
        x_o<=0; y_o<=0; previous_x<=0; previous_y<=0; mask_o<=0;
        flags_o<=0; event_o<=0; tracking<=0; side_known<=0; side_positive<=0; hit_known<=0;
        for(string_index=0;string_index<6;string_index=string_index+1) last_hit[string_index]<=0;
    end else begin
        event_o<=0;
        if(i_error!=0) begin
            tracking<=0; side_known<=0; flags_o<=0; mask_o<=0; seen_sequence<=i_sequence;
        end else case(state)
            S_IDLE: begin
                if(!continuity) begin tracking<=0; side_known<=0; flags_o[0]<=0; end
                if(i_sequence!=seen_sequence) begin
                    snapshot<=i_raw; touch_mask<={i_raw[323:320],i_raw[335:328]};
                    seen_sequence<=i_sequence; sequence_o<=i_sequence; time_o<=i_milliseconds;
                    electrode<=0; row_total<=0; column_total<=0; row_sum<=0; column_sum<=0;
                    row_seen<=0; row_closed<=0; column_seen<=0; column_closed<=0; cluster_gap<=0;
                    bad_data<=i_raw[327] || i_raw[319:312]!=0 || (i_raw[311:304]&8'hcf)!=0;
                end
            end
            S_EXTRACT: begin
                filtered<={snapshot[289-electrode*16 -: 2],snapshot[303-electrode*16 -: 8]};
                baseline<={snapshot[95-electrode*8 -: 8],2'b0};
                selected<=touch_mask[electrode];
                if(snapshot[295-electrode*16 -: 8]>3) bad_data<=1;
                case(electrode)
                    0: center<=102; 1: center<=307; 2: center<=512; 3: center<=717; 4: center<=922;
                    5: center<=73; 6: center<=219; 7: center<=366; 8: center<=512;
                    9: center<=658; 10: center<=805; default: center<=951;
                endcase
            end
            S_WEIGHT: weight<=baseline>filtered ? {1'b0,baseline}-{1'b0,filtered} : 11'd1;
            S_SUM: begin
                if(electrode<5) begin
                    if(selected) begin
                        row_total<=row_total+weight; row_sum<=row_sum+weight*center;
                        row_seen<=1; if(row_closed) cluster_gap<=1;
                    end else if(row_seen) row_closed<=1;
                end else begin
                    if(selected) begin
                        column_total<=column_total+weight; column_sum<=column_sum+weight*center;
                        column_seen<=1; if(column_closed) cluster_gap<=1;
                    end else if(column_seen) column_closed<=1;
                end
                electrode<=electrode+1'b1;
            end
            S_PREPARE: begin
                row_remainder<=row_sum; column_remainder<=column_sum;
                row_quotient<=0; column_quotient<=0; division_bit<=9;
            end
            S_DIVIDE: begin
                if(row_remainder>=row_trial) begin
                    row_remainder<=row_remainder-row_trial; row_quotient[division_bit]<=1;
                end
                if(column_remainder>=column_trial) begin
                    column_remainder<=column_remainder-column_trial; column_quotient[division_bit]<=1;
                end
                if(division_bit!=0) division_bit<=division_bit-1'b1;
            end
            S_POSITION: begin
                x_o<=row_quotient; y_o<=column_quotient; mask_o<=0;
                flags_o<={column_quotient>previous_y,row_quotient>previous_x,1'b1,1'b0};
            end
            S_CROSS: begin
                last_sample<=time_o; previous_x<=x_o; previous_y<=y_o;
                if(bad_data || cluster_gap || row_total==0 || column_total==0) begin
                    tracking<=0; side_known<=0; flags_o[0]<=0;
                end else begin
                    tracking<=1; flags_o[0]<=1;
                    for(string_index=0;string_index<6;string_index=string_index+1) begin
                        if((string_index<3 ? x_o : y_o)>256*(string_index%3+1)+20) begin
                            side_known[string_index]<=1; side_positive[string_index]<=1;
                            if(continuity && side_known[string_index] && !side_positive[string_index] &&
                                (!hit_known[string_index] || time_o-last_hit[string_index]>=12)) begin
                                mask_o[string_index]<=1; last_hit[string_index]<=time_o; hit_known[string_index]<=1;
                            end
                        end else if((string_index<3 ? x_o : y_o)<256*(string_index%3+1)-20) begin
                            side_known[string_index]<=1; side_positive[string_index]<=0;
                            if(continuity && side_known[string_index] && side_positive[string_index] &&
                                (!hit_known[string_index] || time_o-last_hit[string_index]>=12)) begin
                                mask_o[string_index]<=1; last_hit[string_index]<=time_o; hit_known[string_index]<=1;
                            end
                        end else if(!continuity) side_known[string_index]<=0;
                    end
                end
            end
            S_EMIT: event_o<=mask_o!=0;
            default: begin end
        endcase
    end
end
endmodule
