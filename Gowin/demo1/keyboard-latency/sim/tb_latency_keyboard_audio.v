`timescale 1ns/1ps
// 真实 ADC SPI 与 UART 引脚输入、PT8211 串行输出的闭环测试。
module tb_latency_keyboard_audio(output o_done);
 reg flag_done=0;
 assign o_done=flag_done;
 reg clk=0,rstn=0,dout=0,rx=1;
 always #10 clk=~clk;
 wire [2:0] mux;
 wire en,cs,sclk,din,tx,bclk,ws,sdata,pa;
 reg [11:0] raw[0:31],rest[0:31],bottom[0:31];
 reg [1:0] selected=0;
 reg [15:0] response=0,command=0;
 integer edges=0,col=0,conversions=0,k=0,cycles=0;
 integer pcm_count=0,serial_count=0,serial_slot=0,serial_nonzero=0;
 integer sample_value,rounded_value,old_nonzero;
 reg [15:0] expected[0:39999];
 reg [15:0] serial_left=0,serial_right=0;
 reg previous_ws=1;
 integer uart_byte=0,uart_bit=0,uart_packets=0,packet_index=0;
 reg [7:0] packet[0:191],received,checksum;
 LatencyAxisTop #(.C_SETTLE_CYCLES(30),.C_UART_CYCLES(16),.C_REPORT_CYCLES(30000),
 .C_POWERUP_CYCLES(16),.C_TEST_CYCLES(200000)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_adc_dout(dout),.i_uart_rx(rx),
 .o_mux_sel(mux),.o_mux_en(en),.o_adc_cs_n(cs),.o_adc_sclk(sclk),.o_adc_din(din),.o_uart_tx(tx),
 .HP_BCK(bclk),.HP_WS(ws),.HP_DIN(sdata),.PA_EN(pa));
 always @(negedge cs)begin
  case(mux)4:col=0;5:col=1;6:col=2;7:col=3;3:col=4;2:col=5;1:col=6;default:col=7;endcase
  edges=0;command=0;response={4'd0,raw[selected*8+col]};dout=0;
 end
 always @(posedge sclk)if(!cs)begin command={command[14:0],din};edges=edges+1;end
 always @(negedge sclk)if(!cs&&edges<16)begin response={response[14:0],1'b0};dout<=#30 response[15];end
 always @(posedge cs)if(rstn&&edges!=0)begin
  if(edges!=16)$fatal(1,"ADC transfer length");
  selected=command[12:11];conversions=conversions+1;
 end
 always @(posedge clk)if(dut.flag_rstn)begin
  cycles=cycles+1;
  if(dut.flag_fault||dut.flag_overrun||dut.flag_underrun)$fatal(1,"audio deadline or engine fault");
  if(dut.flag_pcm)begin
   if(dut.enc_cycles>=1000)$fatal(1,"32 voice cycle budget %d",dut.enc_cycles);
   sample_value=$signed(dut.enc_pcm_left);
   rounded_value=sample_value<0?-((-sample_value+128)/256):(sample_value+128)/256;
   if(rounded_value>32767)rounded_value=32767;
   if(rounded_value< -32768)rounded_value=-32768;
   expected[pcm_count]=rounded_value;
   pcm_count=pcm_count+1;
  end
 end
 // PT8211 无延迟位；WS高为左，独立对照已提交的24位PCM舍入结果。
 always @(posedge bclk)if(dut.flag_initialized&&dut.flag_rstn)begin
  if(ws!=previous_ws)serial_slot=0;
  if(ws)serial_left={serial_left[14:0],sdata};else serial_right={serial_right[14:0],sdata};
  if(!ws&&serial_slot==15)begin
   if(serial_count==0)begin if(serial_left!==0||serial_right!==0)$fatal(1,"startup silence");end
   else begin
    if(serial_count>pcm_count)$fatal(1,"PCM missing at DAC deadline");
    if(serial_left!==expected[serial_count-1]||serial_right!==serial_left)
     $fatal(1,"PT8211 mismatch frame=%d got=%h expected=%h",serial_count,serial_left,expected[serial_count-1]);
    if(serial_left!=0)serial_nonzero=serial_nonzero+1;
   end
   serial_count=serial_count+1;
  end
  previous_ws=ws;serial_slot=serial_slot+1;
 end
 initial forever begin
  @(negedge tx);#160;
  if(tx!==0)$fatal(1,"UART start");
  for(uart_bit=0;uart_bit<8;uart_bit=uart_bit+1)begin #320;received[uart_bit]=tx;end
  #320;if(tx!==1)$fatal(1,"UART stop");
  packet[packet_index]=received;
  if(packet_index==191)begin
   checksum=0;for(uart_byte=0;uart_byte<190;uart_byte=uart_byte+1)checksum=checksum^packet[uart_byte];
   if(packet[0]!=8'ha5||packet[1]!=8'h5a||packet[2]!=4||packet[3]!=192||packet[191]!=13||packet[190]!=checksum)$fatal(1,"telemetry checksum or framing");
   if(packet[26]&7)$fatal(1,"telemetry audio error");
   uart_packets=uart_packets+1;packet_index=0;
  end else packet_index=packet_index+1;
 end
 reg [7:0] studio_packets[0:922];
 reg [511:0] held_profile;
 integer packet_number,byte_number,old_commits;
 task send_packet;
  input integer number;
  begin for(byte_number=0;byte_number<71;byte_number=byte_number+1)send_byte(studio_packets[number*71+byte_number]);end
 endtask
 task wait_frames;
  input integer count;
  integer goal;
  begin goal=pcm_count+count;while(pcm_count<goal)@(negedge clk);end
 endtask
 task send_byte;
  input [7:0] value;
  integer bit_index;
  begin
   @(negedge clk);rx=0;repeat(16)@(negedge clk);
   for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin rx=value[bit_index];repeat(16)@(negedge clk);end
   rx=1;repeat(20)@(negedge clk);
  end
 endtask
 initial begin
  $readmemh("raw_rest.hex",rest);$readmemh("raw_bottom.hex",bottom);
  for(k=0;k<32;k=k+1)raw[k]=rest[k];
  repeat(5)@(negedge clk);rstn=1;
  wait_frames(64);
  if(dut.enc_pressed!=0||dut.enc_delivered!=0||dut.cnt_nonzero!=0)$fatal(1,"idle keyboard not silent");
  raw[0]=bottom[0];raw[12]=bottom[12];raw[31]=bottom[31];
  wait_frames(180);
  if(dut.enc_pressed!==32'h80001001||dut.enc_delivered!==32'h80001001||dut.enc_events!=3)$fatal(1,"three physical key events");
  if(serial_nonzero<20)$fatal(1,"physical keys produced no DAC samples");
  for(k=0;k<32;k=k+1)raw[k]=bottom[k];
  wait_frames(700);
  if(dut.enc_pressed!==32'hffffffff||dut.enc_active_count!=32)$fatal(1,"32 simultaneous physical voices");
  if(dut.enc_stages!=127||dut.enc_env_peak==0||dut.enc_wave_peak==0||dut.enc_mod_peak==0)$fatal(1,"missing accepted pipeline stage activity");
  if(dut.enc_clips!=0)$fatal(1,"musical chord unexpectedly clipped");
  for(k=0;k<32;k=k+1)raw[k]=rest[k];
  wait_frames(180);
  if(dut.enc_active_count==0)$fatal(1,"release voices excluded from normalization");
  if(dut.enc_pressed!=0||dut.enc_delivered!=0||dut.enc_events!=64)$fatal(1,"key release events");
  wait_frames(10000);
  old_nonzero=dut.cnt_nonzero;wait_frames(100);
  if(dut.cnt_nonzero!=old_nonzero)$fatal(1,"release tail failed to become silent");
  send_byte(8'h54);wait_frames(100);
  if(dut.enc_pressed!=0||dut.enc_delivered!=32'h1000||dut.cnt_test==0)$fatal(1,"explicit test tone must be separate from physical keys");
  send_byte(8'h50);wait_frames(60);
  if(dut.enc_delivered!=0||dut.cnt_test!=0)$fatal(1,"test tone stop");
  if(uart_packets<10)$fatal(1,"missing telemetry");

  $readmemh("studio_packets.hex",studio_packets);
  wait_frames(30);
  for(packet_number=0;packet_number<12;packet_number=packet_number+3)begin
   send_packet(packet_number);wait_frames(3);
   if(dut.ack_status!=0||dut.ack_seq!=packet_number+1)$fatal(1,"patch not acknowledged");
   send_packet(packet_number+1);wait_frames(100);
   if(dut.enc_active_count!=1||dut.enc_delivered!=32'h1000)$fatal(1,"remote note on");
   if(dut.Synth_Inst.Engine_Inst.Store_Inst.mem_mod_envelope[12][34:32]==0)$fatal(1,"mod envelope inactive");
   held_profile=dut.Synth_Inst.Engine_Inst.Store_Inst.mem_profile[12];
   if(packet_number==0)begin
    send_packet(3);wait_frames(3);
    if(dut.Synth_Inst.Engine_Inst.Store_Inst.mem_profile[12]!==held_profile)$fatal(1,"patch changed held voice");
   end
   send_packet(packet_number+2);wait_frames(5);
   if(dut.Synth_Inst.Engine_Inst.Store_Inst.mem_profile[12]!==held_profile)$fatal(1,"note off changed release profile");
   wait_frames(895);
   if(dut.enc_active_count!=0||dut.enc_delivered!=0)$fatal(1,"remote note release");
  end
  old_commits=dut.enc_commits;send_packet(12);wait_frames(3);
  if(dut.enc_commits!=old_commits||dut.ack_status!=1||dut.cnt_test!=0||dut.reg_volume!=6)$fatal(1,"CRC packet altered audio control");
  $display("PASS keyboard ADC -> 32 voice AXIS -> PT8211 frames=%0d serial=%0d nonzero=%0d uart_packets=%0d conversions=%0d Studio dual-envelope cycles=%0d",pcm_count,serial_count,serial_nonzero,uart_packets,conversions,dut.enc_cycles);
  if(dut.Monitor_Inst.cnt_records<35||dut.Monitor_Inst.cnt_physical<32||dut.Monitor_Inst.cnt_remote<4)$fatal(1,"latency coverage records=%d physical=%d remote=%d",dut.Monitor_Inst.cnt_records,dut.Monitor_Inst.cnt_physical,dut.Monitor_Inst.cnt_remote);
  if(dut.Monitor_Inst.cnt_timeouts!=0||dut.Monitor_Inst.cnt_losses!=0)$fatal(1,"latency supervisor timeout/loss");
  $display("PASS latency full chain records=%0d physical=%0d remote=%0d min=%0d max=%0d last=%0d qualify=%0d queue=%0d compute=%0d onset=%0d output=%0d",dut.Monitor_Inst.cnt_records,dut.Monitor_Inst.cnt_physical,dut.Monitor_Inst.cnt_remote,dut.Monitor_Inst.reg_min,dut.Monitor_Inst.reg_max,dut.Monitor_Inst.reg_last_total,dut.Monitor_Inst.reg_last_qualify,dut.Monitor_Inst.reg_last_queue,dut.Monitor_Inst.reg_last_compute,dut.Monitor_Inst.reg_last_onset,dut.Monitor_Inst.reg_last_output);
  flag_done=1;$finish;
 end
 reg observed_latch=0,ws_history=1;
 reg [31:0] reference_tick=0,last_pin_latch=0;
 integer monitor_records=0,monitor_key;
 reg [31:0] first_cross[0:31],confirm_time[0:31];
 always @(posedge clk)begin
  if(!dut.flag_rstn)reference_tick<=0;else reference_tick<=reference_tick+1;
  observed_latch<=dut.flag_dac_latch;
  if(dut.flag_candidate)first_cross[dut.enc_key]<=reference_tick;
  if(dut.flag_confirm)confirm_time[dut.enc_key]<=reference_tick;
 end
 always @(negedge clk)if(dut.flag_rstn&&dut.flag_initialized)begin
  if(ws_history&&!ws)begin
   last_pin_latch=reference_tick-1;
   if(serial_count>0&&!observed_latch)$fatal(1,"missing observed PT8211 left latch");
  end else if(observed_latch)$fatal(1,"monitor latch is not a PT8211 WS falling edge");
  ws_history=ws;
  if(dut.Monitor_Inst.cnt_records!=monitor_records)begin
   monitor_records=dut.Monitor_Inst.cnt_records;monitor_key=dut.Monitor_Inst.reg_last_key;
   if(dut.Monitor_Inst.reg_last_dac!==last_pin_latch)$fatal(1,"latency endpoint not actual serial latch");
   if(dut.Monitor_Inst.reg_last_flags[0])begin
    if(dut.Monitor_Inst.reg_last_start!==first_cross[monitor_key])$fatal(1,"latency origin not first ADC crossing");
    if(dut.Monitor_Inst.reg_last_qualify!==confirm_time[monitor_key]-first_cross[monitor_key])$fatal(1,"debounce duration differs from ADC observations");
   end
   if(dut.Monitor_Inst.reg_last_total !== dut.Monitor_Inst.reg_last_qualify+dut.Monitor_Inst.reg_last_queue+dut.Monitor_Inst.reg_last_compute+dut.Monitor_Inst.reg_last_onset+dut.Monitor_Inst.reg_last_output)$fatal(1,"latency components do not sum");
  end
 end
 initial #900000000 $fatal(1,"watchdog");
endmodule
