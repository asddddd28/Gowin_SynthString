`timescale 1ns/1ps
// Standalone SD text renderer. One small ROM replaces wide string multiplexers;
// characters/address/valid are pipelined together into the existing text RAM.
module SynthStorageDisplay(
    input wire i_clk,input wire i_rstn,input wire [2:0] i_page,input wire [1:0] i_slot,input wire i_delete_mode,
    input wire [31:0] i_status,input wire i_ready,input wire i_busy,input wire i_dirty,input wire [7:0] i_error,
    input wire [7:0] i_sequence,input wire [7:0] i_preset,input wire [7:0] i_sequence_count,input wire [7:0] i_preset_count,
    input wire [31:0] i_sequence_status,input wire [8:0] i_bpm,
    output wire [5:0] o_title_address,input wire [7:0] i_title,
    output wire o_write,output wire [9:0] o_address,output wire [7:0] o_data
);
    (* syn_romstyle="block_rom" *) reg [7:0] mem_text[0:1023];
    initial $readmemh("hdmi/storage-lines.hex",mem_text);
    reg [19:0] cnt_refresh;
    reg [8:0] cnt_character;
    wire [3:0] wire_row=cnt_character[8:5];
    wire [4:0] wire_column=cnt_character[4:0];
    wire flag_active=i_page==6 || i_page==7;
    reg [4:0] dec_line;
    reg [8:0] dec_number;
    reg flag_dynamic,reg_dynamic,reg_valid;
    reg [7:0] dec_character,reg_character,reg_rom;
    reg [9:0] reg_address;
    wire [8:0] wire_hundreds=dec_number/9'd100;
    wire [8:0] wire_remainder=dec_number%9'd100;
    wire [8:0] wire_tens=wire_remainder/9'd10;
    wire [8:0] wire_ones=wire_remainder%9'd10;
    assign o_write=reg_valid;
    assign o_address=reg_address;
    assign o_data=reg_dynamic ? reg_character : reg_rom;
    assign o_title_address=wire_row==3 ? {1'b0,wire_column} : 6'd32+{1'b0,wire_column};
    function [7:0] hexchar;
        input [3:0] value;
        begin hexchar=value<10 ? 48+value : 55+value;end
    endfunction
    always @(*)begin
        dec_line=0;dec_number=0;flag_dynamic=0;dec_character=32;
        case(wire_row)
            0:dec_line=i_busy ? 1 : i_error!=0 ? 2 : !i_status[0] ? 3 : !i_status[1] ? 4 : !i_ready ? 5 : 6;
            1:begin dec_line=i_page==6 ? 7 : 8;dec_number={1'b0,i_page==6 ? i_sequence : i_preset};end
            2:begin dec_line=9;dec_number={1'b0,i_page==6 ? i_sequence_count : i_preset_count};end
            3:if(i_page==6)dec_line=i_sequence_status[0] ? 10 : i_sequence_status[1] ? 11 : 12;
            4:if(i_page==6)begin dec_line=13;dec_number=i_bpm;end
            5:dec_line=i_dirty ? 14 : 15;
            6:dec_line=16;
            7:dec_line=i_error==8'hb6 ? 17 : i_error==8'hb0 ? 18 : 19;
            8:dec_line=i_page==6 ? 20 : 21;
            9:dec_line=22;
            10:dec_line=23;
            11:dec_line=i_page==6 ? (i_delete_mode ? 24 : 25) : 26;
            12:dec_line=27;
            default:begin end
        endcase
        if((wire_row==1 && wire_column>=14 && wire_column<=16) ||
           (wire_row==2 && wire_column>=6 && wire_column<=8) ||
           (wire_row==4 && i_page==6 && wire_column>=4 && wire_column<=6))begin
            flag_dynamic=1;
            if((wire_row==1 && wire_column==14) || (wire_row==2 && wire_column==6) || (wire_row==4 && wire_column==4))dec_character=48+wire_hundreds[7:0];
            else if((wire_row==1 && wire_column==15) || (wire_row==2 && wire_column==7) || (wire_row==4 && wire_column==5))dec_character=48+wire_tens[7:0];
            else dec_character=48+wire_ones[7:0];
        end
        if((wire_row==2 && wire_column==20) || (wire_row==12 && wire_column==5))begin flag_dynamic=1;dec_character=8'd49+{6'd0,i_slot};end
        if(i_page==7 && (wire_row==3 || (wire_row==4 && wire_column<16)))begin flag_dynamic=1;dec_character=i_title;end
        if(wire_row==7 && dec_line==19 && (wire_column==8 || wire_column==9))begin flag_dynamic=1;dec_character=hexchar(wire_column==8 ? i_error[7:4] : i_error[3:0]);end
    end
    always @(posedge i_clk)reg_rom<=mem_text[{dec_line,wire_column}];
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin cnt_refresh<=0;cnt_character<=0;reg_dynamic<=0;reg_character<=32;reg_address<=0;reg_valid<=0;end
        else begin
            cnt_refresh<=cnt_refresh+1'b1;
            if(cnt_refresh<416)cnt_character<=cnt_character+1'b1;else cnt_character<=0;
            reg_valid<=flag_active && cnt_refresh<416;
            reg_dynamic<=flag_dynamic;reg_character<=dec_character;
            reg_address<=wire_row<8 ? 10'd128+cnt_character : wire_row<12 ? 10'd512+{3'd0,cnt_character[6:0]} : 10'd832+{5'd0,wire_column};
        end
    end
endmodule
