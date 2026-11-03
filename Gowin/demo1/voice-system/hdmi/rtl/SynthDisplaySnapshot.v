`timescale 1ns / 1ps
// Coherent status CDC / 帧间一致性状态快照。See companion contract.
module SynthDisplaySnapshot(
    input i_clk,input i_rstn,input i_pixel_clk,input i_pixel_rstn,input i_blank_start,
    input [31:0] i_keys,input [31:0] i_latency,input [31:0] i_underruns,
    input [31:0] i_errors,input [31:0] i_frames,input [2:0] i_page,
    output [159:0] o_fields,output [2:0] o_page
);
    reg flag_request,flag_ack;
    reg [1:0] reg_request_sync,reg_ack_sync;
    reg [159:0] reg_hold,reg_fields_o;
    reg [2:0] reg_hold_page,reg_page_o;
    reg [1:0] reg_state,dec_next_state;
    reg [5:0] cnt_bit;
    reg [31:0] reg_dividend,reg_quotient,reg_binary,reg_decimal;
    reg [5:0] reg_remainder;
    wire [6:0] wire_trial={reg_remainder,reg_dividend[31]};
    reg [31:0] dec_decimal;
    integer idx;
    assign o_fields=reg_fields_o;
    assign o_page=reg_page_o;
    always @(*) begin
        dec_decimal=reg_decimal;
        for(idx=0;idx<8;idx=idx+1)
            if(reg_decimal[idx*4+:4]>=5) dec_decimal[idx*4+:4]=reg_decimal[idx*4+:4]+4'd3;
    end
    always @(posedge i_pixel_clk or negedge i_pixel_rstn) begin
        if(!i_pixel_rstn) begin flag_request<=0;reg_ack_sync<=0;reg_fields_o<=0;reg_page_o<=0;end
        else begin
            reg_ack_sync<={reg_ack_sync[0],flag_ack};
            if(i_blank_start && reg_ack_sync[1]==flag_request) flag_request<=~flag_request;
            // The held bus has settled for two destination clocks after ACK.
            if(reg_ack_sync[1]==flag_request) begin reg_fields_o<=reg_hold;reg_page_o<=reg_hold_page;end
        end
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin reg_request_sync<=0;reg_state<=0;end
        else begin reg_request_sync<={reg_request_sync[0],flag_request};reg_state<=dec_next_state;end
    end
    always @(*) begin
        dec_next_state=reg_state;
        case(reg_state)
            0: if(reg_request_sync[1]!=flag_ack) dec_next_state=1;
            1: if(cnt_bit==31) dec_next_state=2;
            2: if(cnt_bit==31) dec_next_state=3;
            3: dec_next_state=0;
            default: dec_next_state=0;
        endcase
    end
    // Restoring division by 50 and double-dabble are iterative, avoiding a
    // wide combinational decimal formatter in the timing-critical core clock.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            flag_ack<=0;reg_hold<=0;reg_hold_page<=0;cnt_bit<=0;reg_dividend<=0;
            reg_quotient<=0;reg_binary<=0;reg_decimal<=0;reg_remainder<=0;
        end else case(reg_state)
            0: if(reg_request_sync[1]!=flag_ack) begin
                reg_hold<={i_frames,i_errors,i_underruns,32'd0,i_keys};reg_hold_page<=i_page;
                reg_dividend<=i_latency;reg_quotient<=0;reg_remainder<=0;cnt_bit<=0;reg_decimal<=0;
            end
            1: begin
                reg_dividend<=reg_dividend<<1;cnt_bit<=cnt_bit+1'b1;
                if(wire_trial>=50) begin reg_remainder<=wire_trial-7'd50;reg_quotient<={reg_quotient[30:0],1'b1};end
                else begin reg_remainder<=wire_trial[5:0];reg_quotient<={reg_quotient[30:0],1'b0};end
                if(cnt_bit==31) begin reg_binary<={reg_quotient[30:0],wire_trial>=50};cnt_bit<=0;end
            end
            2: begin
                reg_decimal<={dec_decimal[30:0],reg_binary[31]};reg_binary<=reg_binary<<1;cnt_bit<=cnt_bit+1'b1;
            end
            3: begin reg_hold[63:32]<=reg_decimal;flag_ack<=reg_request_sync[1];end
            default: begin end
        endcase
    end
endmodule
