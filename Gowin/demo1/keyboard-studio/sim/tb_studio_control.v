`timescale 1ns/1ps
module tb_studio_control;
 reg clk=0,rstn=0,valid=0,error=0,patch_ready=0,wave_ready=1;
 reg [7:0] data=0;
 always #10 clk=~clk;
 wire ascii,patch,wave,frame,volume_valid;
 wire [7:0] ascii_data,seq,op,status,key;
 wire [4:0] patch_key;wire [511:0] patch_data;
 wire [10:0] address;wire [15:0] wave_data,crc;
 wire [31:0] remote,commits;wire [223:0] velocities;wire [3:0] volume;
 reg [7:0] packets[0:4772];
 integer i,j,ascii_count=0,wave_count=0;
 StudioControl #(.C_TIMEOUT(40),.C_HOST_TIMEOUT(200000)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_rx_valid(valid),.i_rx_error(error),.i_rx_data(data),
 .o_ascii_valid(ascii),.o_ascii_data(ascii_data),.o_patch_valid(patch),.i_patch_ready(patch_ready),.o_patch_key(patch_key),.o_patch_data(patch_data),
 .o_wave_valid(wave),.i_wave_ready(wave_ready),.o_wave_frame(frame),.o_wave_address(address),.o_wave_data(wave_data),
 .o_remote(remote),.o_velocity(velocities),.o_volume(volume),.o_volume_valid(volume_valid),
 .o_ack_seq(seq),.o_ack_op(op),.o_ack_status(status),.o_ack_key(key),.o_ack_crc(crc),.o_commits(commits));
 always @(posedge clk)begin
  if(ascii)ascii_count=ascii_count+1;
  if(wave&&wave_ready)wave_count=wave_count+1;
 end
 task byte_send;
  input [7:0] value;
  begin @(negedge clk);data=value;valid=1;@(negedge clk);valid=0;repeat(4)@(negedge clk);end
 endtask
 task send;
  input integer first,count;
  integer n;
  begin for(n=0;n<count;n=n+1)byte_send(packets[first+n]);repeat(40)@(negedge clk);end
 endtask
 initial begin
  $readmemh("control_packets.hex",packets);repeat(4)@(negedge clk);rstn=1;
  send(0,71);
  if(!patch||seq!=0||commits!=0)$fatal(1,"ACK before profile handshake");
  repeat(20)@(negedge clk);if(!patch)$fatal(1,"profile not held");
  patch_ready=1;repeat(3)@(negedge clk);
  if(commits!=1||status!=0||seq!=1)$fatal(1,"profile commit ACK");
  send(71,8);if(remote!=32'h1000||velocities[12*7+:7]!=100)$fatal(1,"short note on");
  send(79,8);if(remote!=0)$fatal(1,"short note off");
  send(87,71);if(status!=1||commits!=1||ascii_count!=0)$fatal(1,"bad CRC or ASCII payload leakage");
  byte_send(8'ha5);byte_send(8'hc3);repeat(50)@(negedge clk);byte_send(8'h54);
  if(ascii_count!=1)$fatal(1,"partial packet timeout recovery");
  send(158,71);if(status!=2||commits!=1)$fatal(1,"unloaded wavetable accepted");
  for(j=0;j<64;j=j+1)send(229+j*71,71);
  if(wave_count!=2048||dut.reg_wave_blocks!==64'hffffffffffffffff)$fatal(1,"wave block accounting");
  send(158,71);if(status!=0||commits!=2)$fatal(1,"loaded wave profile rejected");
  send(71,8);repeat(200010)@(negedge clk);if(remote!=0)$fatal(1,"host lease stuck notes");
  $display("PASS Studio control: CRC, short notes, backpressure, timeout, 2048 wave writes, lease");$finish;
 end
 initial #10000000 $fatal(1,"control watchdog");
endmodule
