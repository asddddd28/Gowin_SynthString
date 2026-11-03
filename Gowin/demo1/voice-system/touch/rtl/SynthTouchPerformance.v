`timescale 1ns / 1ps
// Hardware performance sources / 触摸实时调制、四弦门控与本地配置。
module SynthTouchPerformance #(parameter C_MS=50000)(
    input i_clk,input i_rstn,input i_next_mode,input i_silent,
    input [1:0] i_update,input [1:0] i_touch,input [19:0] i_x,input [19:0] i_y,input [15:0] i_error,
    input [31:0] i_pressed,input [31:0] i_delivered,input i_keys_idle,
    output [31:0] o_pressed,output [1:0] o_mode,
    output [17:0] o_gain,output [31:0] o_pitch,output [19:0] o_cutoff,output o_cutoff_active,
    input i_request,input [7:0] i_opcode,input [7:0] i_argument,input [63:0] i_words,
    output o_response_valid,output [135:0] o_response
);
    localparam IDLE=0,DIAGONAL=1,MULTIPLY=2,INDEX=3,LOOKUP=4,TARGET=5;
    reg [2:0] reg_state,next_state;
    reg [15:0] cnt_millisecond;
    wire flag_millisecond=cnt_millisecond==C_MS-1;
    reg [1:0] reg_mode,reg_previous_mode;
    reg [2:0] reg_orientation,reg_previous_orientation;
    reg [7:0] reg_gain_range,reg_pitch_range,reg_cutoff_range;
    reg [5:0] reg_age [0:1];
    reg [9:0] reg_x [0:1],reg_y [0:1];
    reg [1:0] reg_contact;
    reg [3:0] reg_known [0:1],reg_side [0:1],reg_hit [0:1];
    reg [3:0] reg_cooldown [0:3];
    reg [31:0] reg_guitar_keys,reg_inhibit;
    reg [3:0] reg_pending;
    reg [4:0] reg_target_key [0:3];
    reg [4:0] dec_key [0:3];
    reg [3:0] dec_have_key;
    reg [15:0] cnt_strums,cnt_coalesced;
    wire [3:0] wire_hits=reg_hit[0]|reg_hit[1];
    wire flag_changed=reg_mode!=reg_previous_mode || reg_orientation!=reg_previous_orientation;
    wire [1:0] wire_live={reg_contact[1] && reg_age[1]<40 && i_error[15:8]==0,reg_contact[0] && reg_age[0]<40 && i_error[7:0]==0};
    wire flag_side=!wire_live[0] && wire_live[1];
    wire flag_touch=|wire_live;
    wire [9:0] wire_x=reg_x[flag_side],wire_y=reg_y[flag_side];
    wire [9:0] wire_raw_x [0:1],wire_raw_y [0:1],wire_map_x [0:1],wire_map_y [0:1];
    reg signed [10:0] reg_diagonal;
    reg [7:0] reg_range;
    reg signed [19:0] reg_position_product;
    reg signed [30:0] reg_cutoff_product;
    reg signed [10:0] reg_pitch_index;
    reg [17:0] reg_pitch_factor;
    (* syn_romstyle="block_rom" *) reg [17:0] mem_pitch [0:255];
    reg signed [31:0] reg_target_gain,reg_target_pitch,reg_target_cutoff;
    reg signed [31:0] reg_gain_o,reg_pitch_o,reg_cutoff_o;
    reg [1:0] reg_compute_mode;
    reg flag_compute_touch;
    reg flag_response_o;
    reg [135:0] reg_response_o;
    wire [31:0] wire_config={27'd0,reg_orientation,reg_mode};
    wire [31:0] wire_ranges={8'd0,reg_cutoff_range,reg_pitch_range,reg_gain_range};
    wire signed [32:0] wire_gain_error=$signed(reg_target_gain)-$signed(reg_gain_o);
    wire signed [32:0] wire_pitch_error=$signed(reg_target_pitch)-$signed(reg_pitch_o);
    wire signed [32:0] wire_cutoff_error=$signed(reg_target_cutoff)-$signed(reg_cutoff_o);
    integer pad,string_index,key_index;
    genvar side;
    initial $readmemh("rom/touch_pitch.hex",mem_pitch);
    assign o_mode=reg_mode;
    assign o_pressed=i_silent ? 32'd0 : reg_mode==3 ? reg_guitar_keys : i_pressed & ~reg_inhibit;
    assign o_gain=reg_gain_o[17:0];assign o_pitch=reg_pitch_o;assign o_cutoff=reg_cutoff_o[19:0];
    assign o_cutoff_active=flag_touch && reg_mode==2 && !i_silent;
    assign o_response_valid=flag_response_o;assign o_response=reg_response_o;
    generate for(side=0;side<2;side=side+1)begin:gen_orientation
        assign wire_raw_x[side]=reg_orientation[0] ? i_y[side*10+:10] : i_x[side*10+:10];
        assign wire_raw_y[side]=reg_orientation[0] ? i_x[side*10+:10] : i_y[side*10+:10];
        assign wire_map_x[side]=reg_orientation[1] ? 10'd1023-wire_raw_x[side] : wire_raw_x[side];
        assign wire_map_y[side]=reg_orientation[2] ? 10'd1023-wire_raw_y[side] : wire_raw_y[side];
    end endgenerate
    // Eight-column priority is local to each physical row; empty rows never pluck.
    always @(*)begin
        dec_have_key=0;
        for(string_index=0;string_index<4;string_index=string_index+1)begin
            dec_key[string_index]=string_index*8;
            for(key_index=0;key_index<8;key_index=key_index+1)begin
                if(i_pressed[string_index*8+key_index])begin dec_key[string_index]=string_index*8+key_index;dec_have_key[string_index]=1;end
            end
        end
    end
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin cnt_millisecond<=0;reg_previous_mode<=0;reg_previous_orientation<=0;end
        else begin reg_previous_mode<=reg_mode;reg_previous_orientation<=reg_orientation;if(flag_millisecond)cnt_millisecond<=0;else cnt_millisecond<=cnt_millisecond+1'b1;end
    end
    // Configuration is atomic; UART owns duplicate detection before this interface.
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin
            reg_mode<=0;reg_orientation<=0;reg_gain_range<=32;reg_pitch_range<=21;reg_cutoff_range<=64;
            flag_response_o<=0;reg_response_o<=0;
        end else begin
            flag_response_o<=0;
            if(i_next_mode)reg_mode<=reg_mode+1'b1;
            if(i_request)begin
                flag_response_o<=1;reg_response_o<=0;
                if(i_argument!=0)reg_response_o[135:128]<=5;
                else case(i_opcode)
                    8'h30:if(i_words!=0)reg_response_o[135:128]<=5;else reg_response_o<={8'd0,32'd40,32'd4,32'd1,32'h544f5531};
                    8'h31:if(i_words[31:5]!=0 || i_words[63:56]!=0 || i_words[39:32]>128 || i_words[47:40]>128 || i_words[55:48]>192)reg_response_o[135:128]<=5;
                        else begin reg_mode<=i_words[1:0];reg_orientation<=i_words[4:2];reg_gain_range<=i_words[39:32];reg_pitch_range<=i_words[47:40];reg_cutoff_range<=i_words[55:48];reg_response_o[63:0]<=i_words;end
                    8'h32:if(i_words!=0)reg_response_o[135:128]<=5;else begin
                        reg_response_o[31:0]<={8'd0,i_error,2'd0,flag_side,flag_touch,wire_live,reg_mode};
                        reg_response_o[63:32]<={12'd0,wire_y,wire_x};reg_response_o[95:64]<={cnt_coalesced,cnt_strums};reg_response_o[127:96]<=reg_pitch_o;
                    end
                    8'h33:if(i_words!=0)reg_response_o[135:128]<=5;else reg_response_o<={8'd0,reg_cutoff_o,reg_gain_o,wire_ranges,wire_config};
                    default:reg_response_o[135:128]<=5;
                endcase
            end
        end
    end
    // Only fresh continuous samples can cross a string. Stale/error paths clear history.
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin
            reg_contact<=0;
            for(pad=0;pad<2;pad=pad+1)begin reg_age[pad]<=40;reg_x[pad]<=0;reg_y[pad]<=0;reg_known[pad]<=0;reg_side[pad]<=0;reg_hit[pad]<=0;end
            for(string_index=0;string_index<4;string_index=string_index+1)reg_cooldown[string_index]<=0;
        end else begin
            for(string_index=0;string_index<4;string_index=string_index+1)begin
                if(flag_millisecond && reg_cooldown[string_index]!=0)reg_cooldown[string_index]<=reg_cooldown[string_index]-1'b1;
                if(wire_hits[string_index])reg_cooldown[string_index]<=12;
            end
            for(pad=0;pad<2;pad=pad+1)begin
                reg_hit[pad]<=0;
                if(flag_millisecond && reg_age[pad]<40)reg_age[pad]<=reg_age[pad]+1'b1;
                if(flag_changed || i_silent || i_error[pad*8+:8]!=0 || reg_age[pad]>=40)reg_known[pad]<=0;
                if(i_update[pad])begin
                    reg_age[pad]<=0;reg_contact[pad]<=i_touch[pad];reg_x[pad]<=wire_map_x[pad];reg_y[pad]<=wire_map_y[pad];
                    if(!i_touch[pad] || flag_changed || i_silent || i_error[pad*8+:8]!=0)reg_known[pad]<=0;
                    else for(string_index=0;string_index<4;string_index=string_index+1)begin
                        if(wire_map_y[pad]>128+256*string_index+20)begin
                            reg_known[pad][string_index]<=1;reg_side[pad][string_index]<=1;
                            if(reg_mode==3 && wire_live[pad] && reg_known[pad][string_index] && !reg_side[pad][string_index] && reg_cooldown[string_index]==0)reg_hit[pad][string_index]<=1;
                        end else if(wire_map_y[pad]<128+256*string_index-20)begin
                            reg_known[pad][string_index]<=1;reg_side[pad][string_index]<=0;
                            if(reg_mode==3 && wire_live[pad] && reg_known[pad][string_index] && reg_side[pad][string_index] && reg_cooldown[string_index]==0)reg_hit[pad][string_index]<=1;
                        end
                    end
                end
            end
        end
    end
    // Per-row pending targets wait for every outstanding keyboard command to retire.
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin
            reg_guitar_keys<=0;reg_inhibit<=0;reg_pending<=0;cnt_strums<=0;cnt_coalesced<=0;
            for(string_index=0;string_index<4;string_index=string_index+1)reg_target_key[string_index]<=0;
        end else begin
            reg_inhibit<=reg_inhibit & i_pressed;
            reg_guitar_keys<=reg_guitar_keys & i_pressed;
            if(flag_changed || i_silent)begin reg_guitar_keys<=0;reg_pending<=0;if(i_silent || reg_mode==3 || reg_previous_mode==3)reg_inhibit<=i_pressed;end
            else if(reg_mode!=3)begin reg_guitar_keys<=0;reg_pending<=0;end
            else begin
                if(|wire_hits)begin cnt_strums<=cnt_strums+1'b1;if(|(wire_hits & reg_pending))cnt_coalesced<=cnt_coalesced+1'b1;end
                for(string_index=0;string_index<4;string_index=string_index+1)begin
                    if(wire_hits[string_index])begin
                        reg_guitar_keys[string_index*8+:8]<=0;reg_target_key[string_index]<=dec_key[string_index];reg_pending[string_index]<=dec_have_key[string_index];
                    end else if(reg_pending[string_index] && i_keys_idle && i_delivered==reg_guitar_keys)begin
                        if(i_pressed[reg_target_key[string_index]])reg_guitar_keys[reg_target_key[string_index]]<=1;
                        reg_pending[string_index]<=0;
                    end
                end
            end
        end
    end
    always @(posedge i_clk or negedge i_rstn)begin if(!i_rstn)reg_state<=IDLE;else reg_state<=next_state;end
    always @(*)begin
        next_state=reg_state;
        case(reg_state)
            IDLE:if(flag_millisecond)next_state=DIAGONAL;
            DIAGONAL:next_state=MULTIPLY;MULTIPLY:next_state=INDEX;INDEX:next_state=LOOKUP;LOOKUP:next_state=TARGET;TARGET:next_state=IDLE;
            default:next_state=IDLE;
        endcase
    end
    always @(posedge i_clk)if(reg_state==LOOKUP)reg_pitch_factor<=mem_pitch[reg_pitch_index<0 ? 8'd0 : reg_pitch_index>255 ? 8'd255 : reg_pitch_index[7:0]];
    // One control multiply is shared across the mutually exclusive modes.
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin
            reg_diagonal<=0;reg_range<=0;reg_position_product<=0;reg_cutoff_product<=0;reg_pitch_index<=128;
            reg_target_gain<=65536;reg_target_pitch<=0;reg_target_cutoff<=0;reg_gain_o<=65536;reg_pitch_o<=0;reg_cutoff_o<=0;
            reg_compute_mode<=0;flag_compute_touch<=0;
        end else begin
            if(flag_millisecond)begin
                reg_gain_o<=wire_gain_error<8 && wire_gain_error>-8 ? reg_target_gain : reg_gain_o+(wire_gain_error>>>3);
                reg_pitch_o<=wire_pitch_error<8 && wire_pitch_error>-8 ? reg_target_pitch : reg_pitch_o+(wire_pitch_error>>>3);
                reg_cutoff_o<=wire_cutoff_error<8 && wire_cutoff_error>-8 ? reg_target_cutoff : reg_cutoff_o+(wire_cutoff_error>>>3);
            end
            case(reg_state)
                IDLE:if(flag_millisecond)begin reg_compute_mode<=reg_mode;flag_compute_touch<=flag_touch && !i_silent;end
                DIAGONAL:begin reg_diagonal<=$signed({1'b0,wire_x})-$signed({1'b0,wire_y});reg_range<=reg_compute_mode==0 ? reg_gain_range : reg_compute_mode==1 ? reg_pitch_range : reg_cutoff_range;end
                MULTIPLY:reg_position_product<=reg_diagonal*$signed({1'b0,reg_range});
                INDEX:begin reg_pitch_index<=11'sd128+(reg_position_product>>>10);reg_cutoff_product<=reg_position_product*11'sd834;end
                TARGET:begin
                    reg_target_gain<=65536;reg_target_pitch<=0;reg_target_cutoff<=0;
                    if(flag_compute_touch && reg_compute_mode==reg_mode)case(reg_compute_mode)
                        0:reg_target_gain<=32'sd65536+(reg_position_product>>>1);
                        1:reg_target_pitch<=($signed({1'b0,reg_pitch_factor})-32'sd65536)<<<10;
                        2:reg_target_cutoff<=reg_cutoff_product>>>10;
                        default:begin end
                    endcase
                end
                default:begin end
            endcase
        end
    end
endmodule
