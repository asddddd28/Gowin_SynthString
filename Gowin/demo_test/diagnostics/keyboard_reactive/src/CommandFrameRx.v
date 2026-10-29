`timescale 1ns / 1ps
// Printable ASCII framing, CRC-8/07, and bounded partial-frame timeout.
// 可打印命令帧解析；半帧超时丢弃，校验失败仍返回带序号的错误事件。
module CommandFrameRx #(parameter integer C_TIMEOUT = 5000000)(
 input i_clk, input i_rstn, input [7:0] i_byte, input i_valid, input i_error,
 output [79:0] o_payload, output o_valid, output o_crc_error
);
reg [79:0] reg_payload, reg_payload_o;
reg [7:0] reg_crc, reg_received_crc;
reg [4:0] cnt_char;
reg [31:0] cnt_timeout;
reg flag_active, flag_valid_o, flag_crc_error_o;
wire flag_hex;
wire [3:0] enc_nibble;
assign flag_hex = (i_byte >= 8'h30 && i_byte <= 8'h39) || (i_byte >= 8'h41 && i_byte <= 8'h46);
assign enc_nibble = i_byte <= 8'h39 ? i_byte[3:0] : i_byte[3:0] + 4'd9;
assign o_payload = reg_payload_o;
assign o_valid = flag_valid_o;
assign o_crc_error = flag_crc_error_o;
function [7:0] crc_byte;
 input [7:0] crc, value;
 reg [7:0] work;
 integer bit_index;
 begin
  work = crc ^ value;
  for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
   work = work[7] ? (work << 1) ^ 8'h07 : work << 1;
  end
  crc_byte = work;
 end
endfunction
always @(posedge i_clk or negedge i_rstn)begin
 if(!i_rstn)begin
  reg_payload<=0;reg_payload_o<=0;reg_crc<=0;reg_received_crc<=0;
  cnt_char<=0;cnt_timeout<=0;flag_active<=0;flag_valid_o<=0;flag_crc_error_o<=0;
 end else begin
  flag_valid_o<=0;
  if(flag_active)begin
   if(cnt_timeout == C_TIMEOUT-1)begin flag_active<=0; end
   else begin cnt_timeout<=cnt_timeout+1'b1; end
  end
  if(i_error)begin flag_active<=0; end
  else if(i_valid)begin
   cnt_timeout<=0;
   if(i_byte==8'h21)begin
    flag_active<=1;cnt_char<=0;reg_payload<=0;reg_crc<=0;reg_received_crc<=0;
   end else if(flag_active)begin
    if(cnt_char<20)begin
     if(flag_hex)begin
      reg_payload<={reg_payload[75:0],enc_nibble};cnt_char<=cnt_char+1'b1;
      if(cnt_char[0])begin reg_crc<=crc_byte(reg_crc,{reg_payload[3:0],enc_nibble}); end
     end else begin flag_active<=0; end
    end else if(cnt_char==20)begin
     if(i_byte==8'h2a)begin cnt_char<=21; end else begin flag_active<=0; end
    end else if(cnt_char<23)begin
     if(flag_hex)begin reg_received_crc<={reg_received_crc[3:0],enc_nibble};cnt_char<=cnt_char+1'b1; end
     else begin flag_active<=0; end
    end else begin
     flag_active<=0;
     if(i_byte==8'h0a)begin
      reg_payload_o<=reg_payload;flag_valid_o<=1;flag_crc_error_o<=reg_crc!=reg_received_crc;
     end
    end
   end
  end
 end
end
endmodule
