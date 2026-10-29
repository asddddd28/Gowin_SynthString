`timescale 1ns / 1ps
// WavetableUpload: ordered inactive-bank upload, CRC16-CCITT, idle-frame commit.
// RAM data are not reset; validity prevents uninitialized samples reaching audio.
module WavetableUpload(
 input i_clk,input i_rstn,input i_packet,input [55:0] i_event,
 input i_frame_idle,output o_write,output [10:0] o_address,
 output [15:0] o_data,output o_bank,output o_available,
 output o_frame,output o_two,input [15:0] i_position_status,output [4:0] o_query_key,
 output [103:0] o_status
);
 reg flag_bank,flag_available,flag_write;
 reg flag_frame,flag_two,flag_upload_two;
 reg [4:0] reg_query_key;
 reg [10:0] reg_address;
 reg [11:0] cnt_samples;
 reg [15:0] reg_data,reg_crc,reg_token,cnt_generation,reg_crc_bits;
 reg [4:0] cnt_crc_bits;
 reg [7:0] reg_result;
 wire [7:0] opcode=i_event[55:48];
 wire [15:0] value=i_event[23:8];
 wire [15:0] token={i_event[39:32],i_event[47:40]};
 wire [9:0] address={i_event[33:32],i_event[47:40]};
 wire [10:0] pair_address={i_event[34:32],i_event[47:40]};
 wire crc_feedback=reg_crc[15]^reg_crc_bits[15];
 assign o_write=flag_write;assign o_address=reg_address;assign o_data=reg_data;
 assign o_bank=flag_bank;assign o_available=flag_available;
 assign o_frame=flag_frame;assign o_two=flag_two;assign o_query_key=reg_query_key;
 // [result,available,count LE,crc LE,token LE,generation LE,reserved] on wire.
 assign o_status={i_position_status,3'b100,reg_query_key,cnt_generation,reg_token,reg_crc,4'd0,cnt_samples[11:8],cnt_samples[7:0],6'd0,flag_two,flag_available,reg_result};
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn) begin
   flag_bank<=0;flag_available<=0;flag_write<=0;reg_address<=0;reg_data<=0;
   cnt_samples<=0;reg_crc<=16'hffff;reg_token<=0;cnt_generation<=0;
   reg_crc_bits<=0;cnt_crc_bits<=0;reg_result<=0;
   flag_frame<=0;flag_two<=0;flag_upload_two<=0;reg_query_key<=0;
  end else begin
   flag_write<=0;
   if(cnt_crc_bits!=0) begin
    reg_crc<={reg_crc[14:0],1'b0}^(crc_feedback ? 16'h1021 : 16'd0);
    reg_crc_bits<={reg_crc_bits[14:0],1'b0};cnt_crc_bits<=cnt_crc_bits-1'b1;
   end
   // Protocol commands have priority over a pending commit on the same edge.
   if(i_packet&&opcode==8'h46&&i_event[47:45]==3'b001) reg_query_key<=i_event[44:40];
   if(i_packet&&(opcode==8'h10||opcode==8'h40)) begin
    reg_token<=value;cnt_samples<=0;reg_crc<=16'hffff;cnt_crc_bits<=0;reg_result<=1;
    flag_upload_two<=(opcode==8'h40);
   end else if(i_packet&&(opcode==8'h13||opcode==8'h43)) begin
    reg_result<=0;cnt_crc_bits<=0;cnt_samples<=0;
   end else if(i_packet&&(opcode==8'h11||opcode==8'h41)) begin
    if(reg_result==1&&cnt_crc_bits==0&&
       ((!flag_upload_two&&opcode==8'h11&&cnt_samples<1024&&address==cnt_samples[9:0]&&i_event[39:34]==0)||
        (flag_upload_two&&opcode==8'h41&&cnt_samples<2048&&pair_address==cnt_samples[10:0]&&i_event[39:35]==0))&&i_event[31:24]==0) begin
     reg_address<={!flag_bank,address};reg_data<=value;flag_write<=1;
     flag_frame<=flag_upload_two&&cnt_samples[10];
     cnt_samples<=cnt_samples+1'b1;
     // CRC processes the transmitted low byte followed by the high byte.
     reg_crc_bits<={value[7:0],value[15:8]};cnt_crc_bits<=16;
    end else reg_result<=4;
   end else if(i_packet&&(opcode==8'h12||opcode==8'h42)) begin
    if(reg_result==1&&cnt_crc_bits==0&&value==reg_crc&&token==reg_token&&
       ((!flag_upload_two&&opcode==8'h12&&cnt_samples==1024)||(flag_upload_two&&opcode==8'h42&&cnt_samples==2048)))
     reg_result<=2;
    else reg_result<=4;
   end else if(reg_result==2&&i_frame_idle) begin
    flag_bank<=!flag_bank;flag_available<=1;flag_two<=flag_upload_two;cnt_generation<=cnt_generation+1'b1;reg_result<=3;
   end
  end
 end
endmodule
