"""连接独立协议、键位配置存储和可确认遥测。"""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parent
OLD=ROOT.parent/'keyboard-performance'
top=(OLD/'src/KeyboardAxisTop.v').read_text().replace('[375:0]','[511:0]')
top=top.replace(' reg [3:0] reg_volume;', ''' reg [3:0] reg_volume;
 wire flag_ascii,flag_patch,flag_patch_ready,flag_wave,flag_wave_ready,flag_wave_frame,flag_volume;
 wire [7:0] enc_ascii,ack_seq,ack_op,ack_status,ack_key;
 wire [15:0] ack_crc,enc_wave_data;wire [31:0] enc_remote,enc_commits;
 wire [223:0] enc_velocity;wire [3:0] enc_volume;
 wire [511:0] enc_patch;wire [4:0] enc_patch_key;wire [10:0] enc_wave_address;
 StudioControl Control_Inst(.i_clk(i_clk),.i_rstn(flag_rstn),.i_rx_valid(flag_rx_valid),.i_rx_error(flag_rx_error),.i_rx_data(enc_rx),
 .o_ascii_valid(flag_ascii),.o_ascii_data(enc_ascii),.o_patch_valid(flag_patch),.i_patch_ready(flag_patch_ready),.o_patch_key(enc_patch_key),.o_patch_data(enc_patch),
 .o_wave_valid(flag_wave),.i_wave_ready(flag_wave_ready),.o_wave_frame(flag_wave_frame),.o_wave_address(enc_wave_address),.o_wave_data(enc_wave_data),
 .o_remote(enc_remote),.o_velocity(enc_velocity),.o_volume(enc_volume),.o_volume_valid(flag_volume),
 .o_ack_seq(ack_seq),.o_ack_op(ack_op),.o_ack_status(ack_status),.o_ack_key(ack_key),.o_ack_crc(ack_crc),.o_commits(enc_commits));''')
top=top.replace("else if(flag_rx_valid&&!flag_rx_error&&enc_rx>=8'h30&&enc_rx<=8'h38)reg_volume<=enc_rx[3:0];","else if(flag_volume)reg_volume<=enc_volume;\n  else if(flag_ascii&&enc_ascii>=8'h30&&enc_ascii<=8'h38)reg_volume<=enc_ascii[3:0];")
top=top.replace("flag_rx_valid&&!flag_rx_error&&enc_rx==", "flag_ascii&&enc_ascii==")
top=top.replace('enc_effective=enc_pressed |','enc_effective=enc_pressed | enc_remote |')
top=top.replace('.i_pressed(enc_effective),.i_frame_done(flag_pcm),','.i_pressed(enc_effective),.i_frame_done(flag_pcm),\n .i_patch_valid(flag_patch),.o_patch_ready(flag_patch_ready),.i_patch_key(enc_patch_key),.i_patch_data(enc_patch),.i_velocity(enc_velocity),')
top=top.replace(".i_wave_valid(1'b0),.o_wave_ready(),.i_wave_frame(1'b0),.i_wave_address(11'd0),.i_wave_data(16'd0)",'.i_wave_valid(flag_wave),.o_wave_ready(flag_wave_ready),.i_wave_frame(flag_wave_frame),.i_wave_address(enc_wave_address),.i_wave_data(enc_wave_data)')
top=top.replace('.i_nonzero(cnt_nonzero),','.i_ack_seq(ack_seq),.i_ack_op(ack_op),.i_ack_status(ack_status),.i_ack_key(ack_key),.i_ack_crc(ack_crc),.i_commits(enc_commits),\n .i_nonzero(cnt_nonzero),')
(ROOT/'src/KeyboardAxisTop.v').write_text(top)
tele=(OLD/'src/KeyboardSynthTelemetry.v').read_text()
tele=tele.replace(' output o_uart_tx',' input [7:0] i_ack_seq,i_ack_op,i_ack_status,i_ack_key,input [15:0] i_ack_crc,input [31:0] i_commits,\n output o_uart_tx')
tele=tele.replace('[511:0]','[639:0]').replace('[5:0] cnt_byte','[6:0] cnt_byte')
tele=tele.replace('cnt_byte==61','cnt_byte==77').replace('cnt_byte==63','cnt_byte==79')
tele=tele.replace('[503:496]','[631:624]').replace('[495:488]','[623:616]').replace('[511:8]','[639:8]')
tele=tele.replace("reg_packet<={8'h0d,8'd0,", "reg_packet<={8'h0d,8'd0,16'd0,32'h0000001f,i_commits,i_ack_crc,i_ack_key,i_ack_status,i_ack_op,i_ack_seq,")
tele=tele.replace("32'h40025aa5","32'h50035aa5")
(ROOT/'src/KeyboardSynthTelemetry.v').write_text(tele)
print('Connected Studio UART and 80-byte telemetry')
