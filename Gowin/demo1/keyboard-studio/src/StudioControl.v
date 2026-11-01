`timescale 1ns/1ps
// CRC16 protected fixed packets. No payload byte is interpreted as an ASCII command.
module StudioControl #(parameter C_TIMEOUT=1000000,parameter C_HOST_TIMEOUT=75000000)(
 input i_clk,input i_rstn,input i_rx_valid,input i_rx_error,input [7:0] i_rx_data,
 output o_ascii_valid,output [7:0] o_ascii_data,
 output o_patch_valid,input i_patch_ready,output [4:0] o_patch_key,output [511:0] o_patch_data,
 output o_wave_valid,input i_wave_ready,output o_wave_frame,output [10:0] o_wave_address,output [15:0] o_wave_data,
 output [31:0] o_remote,output [223:0] o_velocity,output [3:0] o_volume,output o_volume_valid,
 output [7:0] o_ack_seq,output [7:0] o_ack_op,output [7:0] o_ack_status,output [7:0] o_ack_key,
 output [15:0] o_ack_crc,output [31:0] o_commits
);
 reg [6:0] cnt_byte;
 reg [31:0] cnt_timeout,cnt_host,cnt_commits;
 reg [15:0] reg_crc,reg_received_crc,reg_packet_crc,reg_ack_crc;
 reg [7:0] reg_op,reg_seq,reg_key,reg_ack_seq,reg_ack_op,reg_ack_status,reg_ack_key;
 reg [511:0] reg_payload;
 reg flag_pending,flag_ascii,flag_volume,flag_short;
 reg [63:0] reg_wave_blocks;
 reg [7:0] reg_ascii;
 reg [3:0] reg_volume;
 reg [31:0] reg_remote;
 reg [223:0] reg_velocity;
 reg [4:0] cnt_wave;
 wire flag_profile_safe;
 wire flag_finish;
 reg [15:0] enc_crc;
 integer bit_index;
 always @(*)begin
  enc_crc=reg_crc^{i_rx_data,8'd0};
  for(bit_index=0;bit_index<8;bit_index=bit_index+1)
   enc_crc=enc_crc[15]?(enc_crc<<1)^16'h1021:enc_crc<<1;
 end
 // Host cannot inject events, reset flags, invalid wave IDs or unstable SVF coefficients.
 assign flag_profile_safe=!flag_short && reg_key<32 && reg_payload[511:482]==0 && reg_payload[170:169]==0 &&
  reg_payload[173:171]<=4 && reg_payload[176:174]<=4 && (reg_payload[195:193]==0 || (reg_payload[195:193]==6 && (&reg_wave_blocks))) &&
  reg_payload[229:228]<=2 && reg_payload[227:196]<=32'd67108864 &&
  reg_payload[261:230]>=32'd10000 && reg_payload[261:230]<=32'd180000000 &&
  reg_payload[293:262]>=32'd53687091 && reg_payload[293:262]<=32'd536870912 &&
  reg_payload[325:294]==32'h0051eb85 && reg_payload[357:326]==32'h10000000 &&
  (reg_payload[360:358]==1 || reg_payload[360:358]==4 || reg_payload[360:358]==6) && reg_payload[368];
 assign o_patch_valid=flag_pending&&reg_op==1&&flag_profile_safe;
 assign o_patch_key=reg_key[4:0];assign o_patch_data=reg_payload;
 assign o_wave_valid=flag_pending&&reg_op==5&&!flag_short&&reg_key<64;
 assign o_wave_frame=reg_key[5];assign o_wave_address={1'b0,reg_key[4:0],cnt_wave};
 assign o_wave_data=reg_payload[cnt_wave*16+:16];
 assign flag_finish=flag_pending&&((reg_op==1?(!flag_profile_safe||i_patch_ready):
  (reg_op==5?(flag_short||reg_key>=64||(i_wave_ready&&cnt_wave==31)):1'b1)));
 assign o_remote=reg_remote;assign o_velocity=reg_velocity;
 assign o_ascii_valid=flag_ascii;assign o_ascii_data=reg_ascii;
 assign o_volume=reg_volume;assign o_volume_valid=flag_volume;
 assign o_ack_seq=reg_ack_seq;assign o_ack_op=reg_ack_op;assign o_ack_key=reg_ack_key;
 assign o_ack_status=reg_ack_status;assign o_ack_crc=reg_ack_crc;assign o_commits=cnt_commits;
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin
   cnt_byte<=0;cnt_timeout<=0;cnt_host<=0;cnt_commits<=0;reg_crc<=16'hffff;reg_received_crc<=0;reg_packet_crc<=0;
   reg_op<=0;reg_seq<=0;reg_key<=0;reg_payload<=0;flag_pending<=0;cnt_wave<=0;
   reg_ack_seq<=0;reg_ack_op<=0;reg_ack_status<=0;reg_ack_key<=0;reg_ack_crc<=0;
   flag_ascii<=0;reg_ascii<=0;flag_volume<=0;reg_volume<=6;flag_short<=0;reg_wave_blocks<=0;reg_remote<=0;reg_velocity<={32{7'd96}};
  end else begin
   flag_ascii<=0;flag_volume<=0;
   if(cnt_host<C_HOST_TIMEOUT)cnt_host<=cnt_host+1'b1;
   else reg_remote<=0;
   if(cnt_byte!=0)begin
    if(cnt_timeout==C_TIMEOUT-1)begin cnt_byte<=0;cnt_timeout<=0;end
    else cnt_timeout<=cnt_timeout+1'b1;
   end
   if(i_rx_error)begin cnt_byte<=0;cnt_timeout<=0;end
   else if(i_rx_valid&&!flag_pending)begin
    cnt_timeout<=0;
    if(cnt_byte==0)begin
     reg_crc<=16'hffff;
     if(i_rx_data==8'ha5)begin flag_short<=0;cnt_byte<=1;reg_crc<=16'h04bf;end
     else begin flag_ascii<=1;reg_ascii<=i_rx_data;end
    end else if(cnt_byte==1&&i_rx_data!=8'hc3&&i_rx_data!=8'hc4)begin cnt_byte<=0;end
    else begin
     cnt_byte<=cnt_byte+1'b1;
     if(cnt_byte==1)flag_short<=i_rx_data==8'hc4;
     if(cnt_byte<=(flag_short?5:68))reg_crc<=enc_crc;
     if(cnt_byte==(flag_short?6:69))reg_received_crc[7:0]<=i_rx_data;
     else if(cnt_byte==(flag_short?7:70))begin
      cnt_byte<=0;reg_packet_crc<={i_rx_data,reg_received_crc[7:0]};cnt_wave<=0;
      if({i_rx_data,reg_received_crc[7:0]}==reg_crc)begin flag_pending<=1;cnt_host<=0;end
      else begin reg_ack_seq<=reg_seq;reg_ack_op<=reg_op;reg_ack_key<=reg_key;reg_ack_status<=1;reg_ack_crc<=reg_crc;end
     end else case(cnt_byte)
      2:reg_op<=i_rx_data;
      3:reg_seq<=i_rx_data;
      4:reg_key<=i_rx_data;
      default:if(cnt_byte>=5&&cnt_byte<=68)reg_payload[(cnt_byte-5)*8+:8]<=i_rx_data;
     endcase
    end
   end
   if(o_wave_valid&&i_wave_ready)begin
    cnt_wave<=cnt_wave+1'b1;
    if(reg_key==0&&cnt_wave==0)reg_wave_blocks<=0;
    if(cnt_wave==31)reg_wave_blocks[reg_key[5:0]]<=1;
   end
   if(flag_finish)begin
    flag_pending<=0;reg_ack_seq<=reg_seq;reg_ack_op<=reg_op;reg_ack_key<=reg_key;reg_ack_crc<=reg_packet_crc;
    reg_ack_status<=0;
    case(reg_op)
     1:if(flag_profile_safe)cnt_commits<=cnt_commits+1'b1;else reg_ack_status<=2;
     2:if(reg_key<32&&reg_payload[7:0]>0&&reg_payload[7:0]<128)begin reg_remote[reg_key[4:0]]<=1;reg_velocity[reg_key[4:0]*7+:7]<=reg_payload[6:0];end else reg_ack_status<=2;
     3:if(reg_key<32)begin reg_remote[reg_key[4:0]]<=0;reg_velocity[reg_key[4:0]*7+:7]<=96;end else reg_ack_status<=2;
     4:begin reg_remote<=0;reg_velocity<={32{7'd96}};end
     5:if(flag_short||reg_key>=64)reg_ack_status<=2;
     6:if(reg_payload[7:0]<=8)begin reg_volume<=reg_payload[3:0];flag_volume<=1;end else reg_ack_status<=2;
     7:begin end
     default:reg_ack_status<=3;
    endcase
   end
  end
 end
endmodule
