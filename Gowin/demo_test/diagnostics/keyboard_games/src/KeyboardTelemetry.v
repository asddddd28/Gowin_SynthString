`timescale 1ns / 1ps
// Raw key lines share one UART with CRC-protected acknowledgements and state.
// ACK优先、逐行仲裁，采样握手保证原始键序列不丢失。
module KeyboardTelemetry #(parameter integer C_UART_CYCLES=434)(
 input i_clk,input i_rstn,input [4:0] i_key,input [11:0] i_raw,input i_valid,output o_ready,
 input i_ack,input [7:0] i_ack_seq,input [7:0] i_ack_result,
 input i_configured,input [7:0] i_generation,input [3:0] i_mode,input i_direction,input [31:0] i_pressed,
 input [127:0] i_game_status,
 output o_tx
);
localparam [2:0] ST_IDLE=0,ST_CRC=1,ST_LOAD=2,ST_SEND=3;
reg [2:0] state_current,state_next;
reg flag_ack_pending,flag_status_pending,flag_response,flag_game_pending,flag_game_response;
reg [71:0] reg_ack_payload;
reg [127:0] reg_payload,reg_crc_shift;
reg [7:0] reg_crc;
reg [4:0] cnt_crc;
reg [3:0] cnt_bit;
reg [5:0] cnt_char;
reg [15:0] cnt_baud;
reg [9:0] reg_shift;
reg [5:0] reg_key;
reg [11:0] reg_raw;
reg [7:0] enc_char;
wire flag_last_char;
assign o_ready=state_current==ST_IDLE && !flag_ack_pending && !flag_status_pending && !flag_game_pending;
assign o_tx=state_current==ST_SEND ? reg_shift[0] : 1'b1;
assign flag_last_char=flag_response ? (flag_game_response ? cnt_char==36 : cnt_char==22) : cnt_char==8;
function [7:0] hexchar;
 input [3:0] value;
 begin hexchar=value<10 ? 8'h30+{4'b0,value} : 8'h37+{4'b0,value}; end
endfunction
function [7:0] crc_byte;
 input [7:0] crc,value;
 reg [7:0] work;
 integer bit_index;
 begin
  work=crc^value;
  for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin work=work[7] ? (work<<1)^8'h07 : work<<1; end
  crc_byte=work;
 end
endfunction
always @(*)begin
 enc_char=8'h0a;
 if(flag_response)begin
  if(cnt_char==0)begin enc_char=flag_game_response ? 8'h23 : 8'h40; end
  else if(cnt_char<=(flag_game_response ? 32 : 18))begin enc_char=hexchar(reg_payload[127:124]); end
  else if(cnt_char==(flag_game_response ? 33 : 19))begin enc_char=8'h2a; end
  else if(cnt_char==(flag_game_response ? 34 : 20))begin enc_char=hexchar(reg_crc[7:4]); end
  else if(cnt_char==(flag_game_response ? 35 : 21))begin enc_char=hexchar(reg_crc[3:0]); end
 end else begin
  case(cnt_char)
   0:enc_char=8'h4b;1:enc_char=8'h30+reg_key/10;2:enc_char=8'h30+reg_key%10;
   3:enc_char=8'h3a;4:enc_char=hexchar(reg_raw[11:8]);5:enc_char=hexchar(reg_raw[7:4]);
   6:enc_char=hexchar(reg_raw[3:0]);7:enc_char=8'h0d;default:enc_char=8'h0a;
  endcase
 end
end
always @(*)begin
 state_next=state_current;
 case(state_current)
  ST_IDLE:begin
   if(flag_ack_pending || flag_status_pending || flag_game_pending)begin state_next=ST_CRC; end
   else if(i_valid)begin state_next=ST_LOAD; end
  end
  ST_CRC:begin if(cnt_crc==(flag_game_response ? 15 : 8))begin state_next=ST_LOAD; end end
  ST_LOAD:begin state_next=ST_SEND; end
  ST_SEND:begin if(cnt_baud==C_UART_CYCLES-1 && cnt_bit==9)begin
   if(flag_last_char)begin state_next=ST_IDLE; end else begin state_next=ST_LOAD; end
  end end
  default:begin state_next=ST_IDLE; end
 endcase
end
always @(posedge i_clk or negedge i_rstn)begin
 if(!i_rstn)begin state_current<=ST_IDLE; end else begin state_current<=state_next; end
end
always @(posedge i_clk or negedge i_rstn)begin
 if(!i_rstn)begin
  flag_ack_pending<=0;flag_status_pending<=0;flag_response<=0;
  flag_game_pending<=0;flag_game_response<=0;
  reg_ack_payload<=0;reg_payload<=0;reg_crc_shift<=0;reg_crc<=0;cnt_crc<=0;
  cnt_char<=0;cnt_bit<=0;cnt_baud<=0;reg_shift<=10'h3ff;reg_key<=0;reg_raw<=0;
 end else begin
  case(state_current)
   ST_IDLE:begin
    cnt_char<=0;cnt_crc<=0;reg_crc<=0;
    if(flag_ack_pending)begin
     flag_ack_pending<=0;flag_response<=1;flag_game_response<=0;
     reg_payload<={reg_ack_payload,56'b0};reg_crc_shift<={reg_ack_payload,56'b0};
    end else if(flag_status_pending)begin
     flag_status_pending<=0;flag_response<=1;flag_game_response<=0;
     reg_payload<={8'hff,8'h80,7'b0,i_configured,i_mode,3'b0,i_direction,i_generation,i_pressed,56'b0};
     reg_crc_shift<={8'hff,8'h80,7'b0,i_configured,i_mode,3'b0,i_direction,i_generation,i_pressed,56'b0};
    end else if(flag_game_pending)begin
     flag_game_pending<=0;flag_response<=1;flag_game_response<=1;
     reg_payload<=i_game_status;reg_crc_shift<=i_game_status;
    end else if(i_valid)begin
     flag_response<=0;reg_key<={1'b0,i_key}+6'd1;reg_raw<=i_raw;
     if(i_key==31)begin flag_status_pending<=1;flag_game_pending<=1; end
    end
   end
   ST_CRC:begin reg_crc<=crc_byte(reg_crc,reg_crc_shift[127:120]);reg_crc_shift<=reg_crc_shift<<8;cnt_crc<=cnt_crc+1'b1; end
   ST_LOAD:begin
    reg_shift<={1'b1,enc_char,1'b0};cnt_baud<=0;cnt_bit<=0;
    if(flag_response && cnt_char>=1 && cnt_char<=(flag_game_response ? 32 : 18))begin reg_payload<=reg_payload<<4; end
   end
   ST_SEND:begin
    if(cnt_baud==C_UART_CYCLES-1)begin
     cnt_baud<=0;reg_shift<={1'b1,reg_shift[9:1]};
     if(cnt_bit==9)begin cnt_char<=cnt_char+1'b1; end else begin cnt_bit<=cnt_bit+1'b1; end
    end else begin cnt_baud<=cnt_baud+1'b1; end
   end
   default:begin end
  endcase
  if(i_ack)begin
   flag_ack_pending<=1;
   reg_ack_payload<={i_ack_seq,i_ack_result,7'b0,i_configured,i_mode,3'b0,i_direction,i_generation,i_pressed};
  end
 end
end
endmodule
