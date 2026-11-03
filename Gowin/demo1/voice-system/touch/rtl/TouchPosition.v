`timescale 1ns / 1ps
// Weighted single-touch position / 单簇电极重心；接口见同名spec。
module TouchPosition(
    input i_clk,input i_rstn,input [335:0] i_raw,input [15:0] i_sequence,input [7:0] i_error,
    output o_update,output o_touch,output [9:0] o_x,output [9:0] o_y
);
    localparam IDLE=0,EXTRACT=1,WEIGHT=2,PRODUCT=3,SUM=4,PREPARE=5,DIVIDE=6,COMMIT=7;
    reg [2:0] reg_state,next_state;
    wire [335:0] wire_snapshot=i_raw;
    reg [15:0] reg_seen;
    reg [11:0] reg_mask;
    reg [3:0] reg_electrode,reg_bit;
    reg [9:0] reg_filtered,reg_baseline,reg_center,reg_row_quotient,reg_column_quotient;
    reg [10:0] reg_weight;
    reg [20:0] reg_product;
    reg [13:0] reg_row_total,reg_column_total;
    reg [23:0] reg_row_sum,reg_column_sum,reg_row_remainder,reg_column_remainder;
    reg flag_selected,flag_bad,flag_gap,flag_row_seen,flag_row_closed,flag_column_seen,flag_column_closed;
    reg flag_update_o,flag_touch_o;
    reg [9:0] reg_x_o,reg_y_o;
    reg [23:0] reg_row_trial,reg_column_trial;
    assign o_update=flag_update_o;assign o_touch=flag_touch_o;assign o_x=reg_x_o;assign o_y=reg_y_o;
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)reg_state<=IDLE;else if(i_error!=0 || (reg_state!=IDLE && i_sequence!=reg_seen))reg_state<=IDLE;else reg_state<=next_state;
    end
    always @(*)begin
        next_state=reg_state;
        case(reg_state)
            IDLE:if(i_sequence!=reg_seen)next_state=EXTRACT;
            EXTRACT:next_state=WEIGHT;WEIGHT:next_state=PRODUCT;PRODUCT:next_state=SUM;
            SUM:next_state=reg_electrode==11 ? PREPARE : EXTRACT;
            PREPARE:next_state=DIVIDE;DIVIDE:if(reg_bit==0)next_state=COMMIT;
            COMMIT:next_state=IDLE;default:next_state=IDLE;
        endcase
    end
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin
            reg_seen<=0;reg_mask<=0;reg_electrode<=0;reg_bit<=0;reg_row_trial<=0;reg_column_trial<=0;
            reg_filtered<=0;reg_baseline<=0;reg_center<=0;reg_weight<=0;reg_product<=0;
            reg_row_total<=0;reg_column_total<=0;reg_row_sum<=0;reg_column_sum<=0;
            reg_row_remainder<=0;reg_column_remainder<=0;reg_row_quotient<=0;reg_column_quotient<=0;
            flag_selected<=0;flag_bad<=0;flag_gap<=0;flag_row_seen<=0;flag_row_closed<=0;flag_column_seen<=0;flag_column_closed<=0;
            flag_update_o<=0;flag_touch_o<=0;reg_x_o<=0;reg_y_o<=0;
        end else begin
            flag_update_o<=0;
            if(i_error!=0)begin flag_touch_o<=0;reg_seen<=i_sequence;end
            else case(reg_state)
                IDLE:if(i_sequence!=reg_seen)begin
                    reg_seen<=i_sequence;reg_mask<={i_raw[323:320],i_raw[335:328]};
                    reg_electrode<=0;reg_row_total<=0;reg_column_total<=0;reg_row_sum<=0;reg_column_sum<=0;
                    flag_row_seen<=0;flag_column_seen<=0;flag_row_closed<=0;flag_column_closed<=0;flag_gap<=0;
                    flag_bad<=i_raw[327] || i_raw[319:312]!=0 || (i_raw[311:304]&8'hcf)!=0;
                end
                EXTRACT:begin
                    reg_filtered<={wire_snapshot[289-reg_electrode*16 -:2],wire_snapshot[303-reg_electrode*16 -:8]};
                    reg_baseline<={wire_snapshot[95-reg_electrode*8 -:8],2'b0};flag_selected<=reg_mask[reg_electrode];
                    if(wire_snapshot[295-reg_electrode*16 -:8]>3)flag_bad<=1;
                    case(reg_electrode)
                        0:reg_center<=0;1:reg_center<=256;2:reg_center<=512;3:reg_center<=768;4:reg_center<=1023;
                        5:reg_center<=0;6:reg_center<=171;7:reg_center<=341;8:reg_center<=512;9:reg_center<=682;10:reg_center<=853;default:reg_center<=1023;
                    endcase
                end
                WEIGHT:reg_weight<=reg_baseline>reg_filtered ? {1'b0,reg_baseline}-{1'b0,reg_filtered} : 11'd1;
                PRODUCT:reg_product<=reg_weight*reg_center;
                SUM:begin
                    if(reg_electrode<5)begin
                        if(flag_selected)begin reg_row_total<=reg_row_total+reg_weight;reg_row_sum<=reg_row_sum+reg_product;flag_row_seen<=1;if(flag_row_closed)flag_gap<=1;end
                        else if(flag_row_seen)flag_row_closed<=1;
                    end else begin
                        if(flag_selected)begin reg_column_total<=reg_column_total+reg_weight;reg_column_sum<=reg_column_sum+reg_product;flag_column_seen<=1;if(flag_column_closed)flag_gap<=1;end
                        else if(flag_column_seen)flag_column_closed<=1;
                    end
                    reg_electrode<=reg_electrode+1'b1;
                end
                PREPARE:begin reg_row_remainder<=reg_row_sum;reg_column_remainder<=reg_column_sum;reg_row_quotient<=0;reg_column_quotient<=0;reg_bit<=9;reg_row_trial<={1'b0,reg_row_total,9'd0};reg_column_trial<={1'b0,reg_column_total,9'd0};end
                DIVIDE:begin
                    if(reg_row_remainder>=reg_row_trial)begin reg_row_remainder<=reg_row_remainder-reg_row_trial;reg_row_quotient[reg_bit]<=1;end
                    if(reg_column_remainder>=reg_column_trial)begin reg_column_remainder<=reg_column_remainder-reg_column_trial;reg_column_quotient[reg_bit]<=1;end
                    reg_row_trial<=reg_row_trial>>1;reg_column_trial<=reg_column_trial>>1;
                    if(reg_bit!=0)reg_bit<=reg_bit-1'b1;
                end
                COMMIT:if(i_sequence==reg_seen)begin reg_x_o<=reg_row_quotient;reg_y_o<=reg_column_quotient;flag_touch_o<=!flag_bad && !flag_gap && reg_row_total!=0 && reg_column_total!=0;flag_update_o<=1;end
                default:begin end
            endcase
        end
    end
endmodule
