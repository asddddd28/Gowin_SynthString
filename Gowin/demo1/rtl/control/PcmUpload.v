`timescale 1ns/1ps
// PcmUpload: bounded single-buffer sample upload with metadata and CRC validation.
// 单缓冲：开始接收前等待空闲并失效旧采样；失败后保持不可用，避免播放半包。
module PcmUpload(
 input i_clk,input i_rstn,input i_packet,input [55:0] i_event,input i_frame_idle,
 output o_write,output [13:0] o_address,output [15:0] o_data,
 output o_available,output [14:0] o_loop_start,output [14:0] o_loop_end,output [6:0] o_root,
 output [103:0] o_status
);
 reg flag_write,flag_available;
 reg [7:0] reg_result;
 reg [15:0] reg_token,reg_crc,reg_crc_bits,cnt_generation,cnt_samples;
 reg [4:0] cnt_crc;
 reg [2:0] cnt_metadata;
 reg [15:0] reg_length,reg_start,reg_end,reg_root;
 reg [14:0] reg_loop_start,reg_loop_end;
 reg [6:0] reg_root_note;
 reg [13:0] reg_address;
 reg [15:0] reg_data;
 wire [7:0] opcode=i_event[55:48];
 wire [15:0] value=i_event[23:8];
 wire [15:0] address={i_event[39:32],i_event[47:40]};
 wire valid_metadata=(reg_length>=512)&&(reg_length<=16384)&&(reg_start<reg_end)&&
     (reg_end<=reg_length)&&((reg_end-reg_start)>=512)&&(reg_root<=127);
 assign o_write=flag_write;assign o_address=reg_address;assign o_data=reg_data;
 assign o_available=flag_available;assign o_loop_start=reg_loop_start;assign o_loop_end=reg_loop_end;assign o_root=reg_root_note;
 assign o_status={21'd0,cnt_metadata,cnt_generation,reg_token,reg_crc,cnt_samples,7'd0,flag_available,reg_result};
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn) begin
   flag_write<=0;flag_available<=0;reg_result<=0;reg_token<=0;reg_crc<=16'hffff;reg_crc_bits<=0;
   cnt_generation<=0;cnt_samples<=0;cnt_crc<=0;cnt_metadata<=0;
   reg_length<=0;reg_start<=0;reg_end<=0;reg_root<=60;reg_address<=0;reg_data<=0;
   reg_loop_start<=0;reg_loop_end<=512;reg_root_note<=60;
  end else begin
   flag_write<=0;
   if(cnt_crc!=0) begin
    reg_crc<={reg_crc[14:0],1'b0}^((reg_crc[15]^reg_crc_bits[15])?16'h1021:16'd0);
    reg_crc_bits<={reg_crc_bits[14:0],1'b0};cnt_crc<=cnt_crc-1'b1;
   end
   if(reg_result==2&&i_frame_idle) begin
    flag_available<=0;reg_result<=1;cnt_samples<=0;cnt_metadata<=0;reg_crc<=16'hffff;cnt_crc<=0;
   end
   if(reg_result==5&&i_frame_idle) begin
    flag_available<=1;reg_result<=3;cnt_generation<=cnt_generation+1'b1;
    reg_loop_start<=reg_start[14:0];reg_loop_end<=reg_end[14:0];reg_root_note<=reg_root[6:0];
   end
   if(i_packet&&opcode==8'h30) begin reg_token<=value;reg_result<=2;cnt_crc<=0;end
   else if(i_packet&&opcode==8'h33) begin reg_result<=0;cnt_crc<=0;end
   else if(i_packet&&opcode==8'h34) begin
    if(reg_result==1&&cnt_metadata<4&&i_event[47:40]==cnt_metadata&&cnt_samples==0&&cnt_crc==0) begin
     case(cnt_metadata)
      0:reg_length<=value;1:reg_start<=value;2:reg_end<=value;3:reg_root<=value;
      default:begin end
     endcase
     cnt_metadata<=cnt_metadata+1'b1;reg_crc_bits<={value[7:0],value[15:8]};cnt_crc<=16;
    end else reg_result<=4;
   end else if(i_packet&&opcode==8'h31) begin
    if(reg_result==1&&cnt_metadata==4&&valid_metadata&&address==cnt_samples&&cnt_samples<reg_length&&cnt_crc==0) begin
     flag_write<=1;reg_address<=cnt_samples[13:0];reg_data<=value;cnt_samples<=cnt_samples+1'b1;
     reg_crc_bits<={value[7:0],value[15:8]};cnt_crc<=16;
    end else reg_result<=4;
   end else if(i_packet&&opcode==8'h32) begin
    if(reg_result==1&&cnt_metadata==4&&valid_metadata&&cnt_samples==reg_length&&cnt_crc==0&&address==reg_token&&value==reg_crc)
     reg_result<=5;
    else reg_result<=4;
   end
  end
 end
endmodule
