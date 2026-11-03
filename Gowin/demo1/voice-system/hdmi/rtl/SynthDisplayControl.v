`timescale 1ns / 1ps
// Display state and local control / 显示状态及本地控制。See companion contract.
module SynthDisplayControl #(parameter C_LONG_CYCLES=40000000)(
    input i_clk,
    input i_rstn,
    input [4:0] i_joystick,
    input [4:0] i_encoder_a,
    input [4:0] i_encoder_b,
    input i_request,
    input [7:0] i_opcode,
    input [7:0] i_argument,
    input [63:0] i_words,
    output o_response_valid,
    output [135:0] o_response,
    output o_text_write,
    output [9:0] o_text_address,
    output [7:0] o_text_data,
    output [2:0] o_page,
    output [7:0] o_focus,
    output [15:0] o_confirm,
    output o_touch_next,output o_host_live
);
    reg [4:0] reg_joy_meta,reg_joy_sync,reg_joy_filter;
    reg [17:0] cnt_joy_startup;
    reg [2:0] flag_joy_armed;
    wire flag_joy_ready=cnt_joy_startup==18'd250015;
    wire flag_left=flag_joy_armed[0] && reg_joy_filter[1:0]==2'b00;
    wire flag_right=flag_joy_armed[0] && reg_joy_filter[1:0]==2'b11;
    wire flag_up=flag_joy_armed[1] && reg_joy_filter[3:2]==2'b11;
    wire flag_down=flag_joy_armed[1] && reg_joy_filter[3:2]==2'b00;
    reg flag_switch_tracking,flag_switch_long;
    reg [25:0] cnt_switch;
    reg flag_confirm,flag_touch_next_o;
    assign o_touch_next=flag_touch_next_o;
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin flag_switch_tracking<=0;flag_switch_long<=0;cnt_switch<=0;flag_confirm<=0;flag_touch_next_o<=0;end
        else begin
            flag_confirm<=0;flag_touch_next_o<=0;
            if(flag_joy_armed[2] && !reg_joy_filter[4])begin flag_switch_tracking<=1;flag_switch_long<=0;cnt_switch<=0;end
            else if(flag_switch_tracking)begin
                if(reg_joy_filter[4])begin flag_confirm<=!flag_switch_long;flag_switch_tracking<=0;cnt_switch<=0;end
                else if(!flag_switch_long)begin
                    if(cnt_switch==C_LONG_CYCLES-1)begin flag_switch_long<=1;flag_touch_next_o<=1;end
                    else cnt_switch<=cnt_switch+1'b1;
                end
            end
        end
    end
    reg [9:0] reg_encoder_meta,reg_encoder_sync;
    reg [17:0] cnt_debounce [0:4];
    reg [4:0] flag_armed;
    reg [1:0] reg_phase [0:4];
    reg [11:0] cnt_encoder [0:4];
    reg [15:0] reg_position [0:4];
    reg [2:0] reg_page_o;
    reg [7:0] reg_focus_o;
    reg [15:0] reg_confirm_o;
    reg [3:0] reg_write_remaining;
    reg [9:0] reg_write_address;
    reg [63:0] reg_write_words;
    reg flag_response_o;
    reg [135:0] reg_response_o;
    reg [26:0] cnt_host_age;
    genvar idx;
    assign o_page=reg_page_o;
    assign o_focus=reg_focus_o;
    assign o_confirm=reg_confirm_o;
    assign o_response_valid=flag_response_o;
    assign o_response=reg_response_o;
    assign o_text_write=reg_write_remaining!=0;
    assign o_text_address=reg_write_address;
    assign o_text_data=reg_write_words[7:0];
    assign o_host_live=cnt_host_age<27'd100000000;
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) cnt_host_age<=27'd100000000;
        else if(i_request && i_opcode==8'h13) cnt_host_age<=0;
        else if(cnt_host_age<27'd100000000) cnt_host_age<=cnt_host_age+1'b1;
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin reg_joy_meta<=21;reg_joy_sync<=21;reg_encoder_meta<=0;reg_encoder_sync<=0;end
        else begin
            reg_joy_meta<=i_joystick;reg_joy_sync<=reg_joy_meta;
            reg_encoder_meta<={i_encoder_a,i_encoder_b};reg_encoder_sync<=reg_encoder_meta;
        end
    end
    generate for(idx=0;idx<5;idx=idx+1) begin: gen_input
        // Debounce comparator levels before decoding the two axis regions.
        always @(posedge i_clk or negedge i_rstn) begin
            if(!i_rstn) begin cnt_debounce[idx]<=0;reg_joy_filter[idx]<=(idx==4 || idx==2 || idx==0);end
            else if(reg_joy_sync[idx]==reg_joy_filter[idx]) cnt_debounce[idx]<=0;
            else if(cnt_debounce[idx]==249999) begin reg_joy_filter[idx]<=reg_joy_sync[idx];cnt_debounce[idx]<=0;end
            else cnt_debounce[idx]<=cnt_debounce[idx]+1'b1;
        end
        // Quadrature transitions accumulate absolute signed counts. A host
        // compares counts, so polling/replay never consumes an event twice.
        always @(posedge i_clk or negedge i_rstn) begin
            if(!i_rstn) begin cnt_encoder[idx]<=0;reg_phase[idx]<=0;reg_position[idx]<=0;flag_armed[idx]<=0;end
            else if(!flag_armed[idx]) begin
                if({reg_encoder_sync[idx+5],reg_encoder_sync[idx]}!=reg_phase[idx]) begin
                    reg_phase[idx]<={reg_encoder_sync[idx+5],reg_encoder_sync[idx]};cnt_encoder[idx]<=0;
                end else if(cnt_encoder[idx]==2499) begin flag_armed[idx]<=1;cnt_encoder[idx]<=0;end
                else cnt_encoder[idx]<=cnt_encoder[idx]+1'b1;
            end
            else if({reg_encoder_sync[idx+5],reg_encoder_sync[idx]}==reg_phase[idx]) cnt_encoder[idx]<=0;
            else if(cnt_encoder[idx]==2499) begin
                cnt_encoder[idx]<=0;reg_phase[idx]<={reg_encoder_sync[idx+5],reg_encoder_sync[idx]};flag_armed[idx]<=1;
                if(flag_armed[idx]) case({reg_phase[idx],reg_encoder_sync[idx+5],reg_encoder_sync[idx]})
                    4'b0001,4'b0111,4'b1110,4'b1000: reg_position[idx]<=reg_position[idx]+1'b1;
                    4'b0010,4'b1011,4'b1101,4'b0100: reg_position[idx]<=reg_position[idx]-1'b1;
                    default: begin end
                endcase
            end else cnt_encoder[idx]<=cnt_encoder[idx]+1'b1;
        end
    end endgenerate
    // Each axis is H/L comparators: packed01 is centre,00 low,11 high,
    // and10 invalid. Require centre after startup and after every excursion;
    // returning to centre or holding a direction never emits a second action.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin cnt_joy_startup<=0;flag_joy_armed<=0;end
        else if(!flag_joy_ready) begin cnt_joy_startup<=cnt_joy_startup+1'b1;flag_joy_armed<=0;end
        else begin
            flag_joy_armed[0]<=reg_joy_filter[1:0]==2'b01;
            flag_joy_armed[1]<=reg_joy_filter[3:2]==2'b01;
            flag_joy_armed[2]<=reg_joy_filter[4];
        end
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            reg_page_o<=0;reg_focus_o<=0;reg_confirm_o<=0;
            reg_write_remaining<=0;reg_write_address<=0;reg_write_words<=0;
            flag_response_o<=0;reg_response_o<=0;
        end else begin
            flag_response_o<=0;
            if(flag_right) reg_page_o<=reg_page_o+1'b1;
            else if(flag_left) reg_page_o<=reg_page_o-1'b1;
            else if(flag_up) reg_focus_o<=reg_focus_o-1'b1;
            else if(flag_down) reg_focus_o<=reg_focus_o+1'b1;
            if(flag_confirm) reg_confirm_o<=reg_confirm_o+1'b1;
            if(reg_write_remaining!=0) begin
                reg_write_remaining<=reg_write_remaining-1'b1;
                reg_write_address<=reg_write_address+1'b1;reg_write_words<=reg_write_words>>8;
                if(reg_write_remaining==1) flag_response_o<=1;
            end
            if(i_request) begin
                flag_response_o<=1;reg_response_o<=0;
                case(i_opcode)
                    8'h10: if(i_argument!=0 || i_words!=0) reg_response_o[135:128]<=5;
                        else reg_response_o<={8'd0,32'd1024,32'd73333333,32'h00010001,32'h48444d31};
                    8'h11: if(i_argument>7 || i_words!=0) reg_response_o[135:128]<=5;
                        else reg_page_o<=i_argument[2:0];
                    8'h12: if(i_argument>127) reg_response_o[135:128]<=5;
                        else begin
                            flag_response_o<=0;reg_write_remaining<=8;reg_write_address<={i_argument[6:0],3'd0};reg_write_words<=i_words;
                        end
                    8'h13: if(i_argument!=0 || i_words!=0) reg_response_o[135:128]<=5;
                        else reg_response_o<={8'd0,16'd0,reg_confirm_o,reg_focus_o,5'd0,reg_page_o,reg_position[4],reg_position[3],reg_position[2],reg_position[1],reg_position[0]};
                    default: reg_response_o[135:128]<=5;
                endcase
            end
        end
    end
endmodule
