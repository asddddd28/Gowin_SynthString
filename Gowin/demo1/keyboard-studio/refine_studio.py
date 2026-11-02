"""After first evidence: fast note packets and registered RAM writeback."""
from pathlib import Path
ROOT=Path(__file__).resolve().parent
p=ROOT/'src/StudioControl.v';s=p.read_text()
s=s.replace(' reg flag_pending,flag_ascii,flag_volume;',' reg flag_pending,flag_ascii,flag_volume,flag_short;\n reg [63:0] reg_wave_blocks;')
s=s.replace('assign flag_profile_safe=reg_key<32','assign flag_profile_safe=!flag_short && reg_key<32')
s=s.replace('reg_payload[195:193]==0','(reg_payload[195:193]==0 || (reg_payload[195:193]==6 && (&reg_wave_blocks)))')
s=s.replace('reg_payload[360:358]>=1 && reg_payload[360:358]<=3','(reg_payload[360:358]==1 || reg_payload[360:358]==4 || reg_payload[360:358]==6)')
s=s.replace('flag_pending&&reg_op==5&&reg_key<64','flag_pending&&reg_op==5&&!flag_short&&reg_key<64')
s=s.replace('(reg_key>=64||(i_wave_ready','(flag_short||reg_key>=64||(i_wave_ready')
s=s.replace('flag_ascii<=0;reg_ascii<=0;flag_volume<=0;reg_volume<=6;', 'flag_ascii<=0;reg_ascii<=0;flag_volume<=0;reg_volume<=6;flag_short<=0;reg_wave_blocks<=0;')
s=s.replace("if(i_rx_data==8'ha5)begin cnt_byte<=1;", "if(i_rx_data==8'ha5)begin flag_short<=0;cnt_byte<=1;")
s=s.replace("cnt_byte==1&&i_rx_data!=8'hc3","cnt_byte==1&&i_rx_data!=8'hc3&&i_rx_data!=8'hc4")
s=s.replace('if(cnt_byte<=68)reg_crc<=enc_crc;',"if(cnt_byte==1)flag_short<=i_rx_data==8'hc4;\n     if(cnt_byte<=(flag_short?5:68))reg_crc<=enc_crc;")
start=s.index('     case(cnt_byte)');end=s.index('\n    end\n   end',start)
s=s[:start]+'''     if(cnt_byte==(flag_short?6:69))reg_received_crc[7:0]<=i_rx_data;
     else if(cnt_byte==(flag_short?7:70))begin
      cnt_byte<=0;reg_packet_crc<={i_rx_data,reg_received_crc[7:0]};cnt_wave<=0;
      if({i_rx_data,reg_received_crc[7:0]}==reg_crc)begin flag_pending<=1;cnt_host<=0;end
      else begin reg_ack_seq<=reg_seq;reg_ack_op<=reg_op;reg_ack_key<=reg_key;reg_ack_status<=1;reg_ack_crc<=reg_crc;end
     end else case(cnt_byte)
      2:reg_op<=i_rx_data;
      3:reg_seq<=i_rx_data;
      4:reg_key<=i_rx_data;
      default:if(cnt_byte>=5&&cnt_byte<=68)reg_payload[(cnt_byte-5)*8+:8]<=i_rx_data;
     endcase'''+s[end:]
s=s.replace("if(o_wave_valid&&i_wave_ready)cnt_wave<=cnt_wave+1'b1;", "if(o_wave_valid&&i_wave_ready)begin\n    cnt_wave<=cnt_wave+1'b1;\n    if(reg_key==0&&cnt_wave==0)reg_wave_blocks<=0;\n    if(cnt_wave==31)reg_wave_blocks[reg_key[5:0]]<=1;\n   end")
s=s.replace('5:if(reg_key>=64)','5:if(flag_short||reg_key>=64)')
p.write_text(s)
# Insert a writeback register boundary; next-stage prefetch waits two full clocks.
p=ROOT/'src/StudioVoiceStore.v';s=p.read_text()
insert=''' reg flag_write;
 reg [4:0] reg_write_voice;
 reg [2:0] reg_write_stage;
 reg [191:0] reg_write_data;
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin flag_write<=0;reg_write_voice<=0;reg_write_stage<=0;reg_write_data<=0;end
  else begin flag_write<=i_write;reg_write_voice<=i_write_voice;reg_write_stage<=i_write_stage;reg_write_data<=i_write_data;end
 end
'''
s=s.replace(' reg [511:0] mem_profile',insert+' reg [511:0] mem_profile')
s=s.replace('else if(i_write&&i_write_stage', 'else if(flag_write&&reg_write_stage')
s=s.replace('[i_write_voice]<=i_write_data','[reg_write_voice]<=reg_write_data')
p.write_text(s)
print('Added short commands, complete-table guard and registered RAM writes')
