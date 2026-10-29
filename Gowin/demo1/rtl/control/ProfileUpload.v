`timescale 1ns/1ps
// ProfileUpload: verify one complete per-key patch before committing to configuration RAM.
module ProfileUpload(
 input i_clk,input i_rstn,input i_packet,input [55:0] i_event,
 output o_write,output [4:0] o_address,output [287:0] o_data,output [103:0] o_status
);
 reg [287:0] reg_patch;
 reg [7:0] reg_key,reg_result;
 reg [15:0] reg_token,reg_crc,reg_crc_bits,cnt_generation;
 reg [4:0] cnt_words,cnt_crc;
 reg flag_write;
 wire [7:0] opcode=i_event[55:48],key=i_event[47:40],field=i_event[39:32];
 wire [15:0] value=i_event[23:8];
 wire [5:0] enc_exponent_valid={reg_patch[207:203]<=22,reg_patch[175:171]<=22,reg_patch[159:155]<=22,
    reg_patch[143:139]<=22,reg_patch[111:107]<=22,reg_patch[95:91]<=22};
 wire [5:0] enc_mantissa_valid={(reg_patch[207:192]==0)||(reg_patch[202:192]!=0),
    (reg_patch[175:160]==0)||(reg_patch[170:160]!=0),(reg_patch[159:144]==0)||(reg_patch[154:144]!=0),
    (reg_patch[143:128]==0)||(reg_patch[138:128]!=0),(reg_patch[111:96]==0)||(reg_patch[106:96]!=0),
    (reg_patch[95:80]==0)||(reg_patch[90:80]!=0)};
 wire valid_patch=(reg_patch[14:3]==0)&&(reg_patch[2:0]<=4)&&(reg_patch[31:16]<=4)&&(reg_patch[47:32]<=4)&&
    (reg_patch[63:48]>=1)&&(reg_patch[63:48]<=2048)&&(reg_patch[79:64]<=8192)&&
    ((reg_patch[2:0]<2)||(reg_patch[2:0]==4)||(reg_patch[79:64]<=4096))&&
    (reg_patch[239:224]<=127)&&(reg_patch[255:240]<=16000)&&
    (!reg_patch[15]||((&enc_exponent_valid)&&(&enc_mantissa_valid)));
 assign o_write=flag_write;assign o_address=reg_key[4:0];assign o_data=reg_patch;
 assign o_status={24'd2,cnt_generation,reg_token,reg_crc,11'd0,cnt_words,reg_key,reg_result};
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn) begin reg_patch<=0;reg_key<=0;reg_result<=0;reg_token<=0;reg_crc<=16'hffff;
   reg_crc_bits<=0;cnt_generation<=0;cnt_words<=0;cnt_crc<=0;flag_write<=0;end
  else begin
   flag_write<=0;
   if(cnt_crc!=0) begin
    reg_crc<={reg_crc[14:0],1'b0}^((reg_crc[15]^reg_crc_bits[15])?16'h1021:16'd0);
    reg_crc_bits<={reg_crc_bits[14:0],1'b0};cnt_crc<=cnt_crc-1'b1;
   end
   if(i_packet&&opcode==8'h20) begin
    reg_key<=key;reg_token<=value;reg_crc<=16'hffff;cnt_words<=0;cnt_crc<=0;
    reg_result<=(key>=32&&key<64)?1:4;
   end else if(i_packet&&opcode==8'h23) begin reg_result<=0;cnt_crc<=0;end
   else if(i_packet&&opcode==8'h21) begin
    if(reg_result==1&&key==reg_key&&field==cnt_words&&cnt_words<18&&cnt_crc==0&&i_event[31:24]==0) begin
     reg_patch[cnt_words*16+:16]<=value;cnt_words<=cnt_words+1'b1;
     reg_crc_bits<={value[7:0],value[15:8]};cnt_crc<=16;
    end else reg_result<=4;
   end else if(i_packet&&opcode==8'h22) begin
    if(reg_result==1&&cnt_words==18&&cnt_crc==0&&key==reg_key&&
       {i_event[31:24],i_event[39:32]}==reg_token&&value==reg_crc&&valid_patch) begin
     flag_write<=1;reg_result<=3;cnt_generation<=cnt_generation+1'b1;
    end else reg_result<=4;
   end
  end
 end
endmodule
