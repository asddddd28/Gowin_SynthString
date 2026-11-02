`timescale 1ns / 1ps
// 行为从机检查真实 SCL/SDA 边沿，独立于主机内部字节握手。
module MprBehavior #(parameter [6:0] ADDRESS=7'h5a)(input scl,inout sda,input enable,output reg [31:0] reads=0);
reg drive=0,active=0,reading=0,selected=0;
reg [7:0] memory[0:255];
reg [7:0] incoming=0,pointer=0,outgoing=0;
integer count=0,stage=0,k;
reg master_nack=0;
assign sda=drive ? 1'b0 : 1'bz;
initial begin
    for(k=0;k<256;k=k+1) memory[k]=0;
    memory[8'h5c]=8'h10; memory[8'h5d]=8'h24;
    memory[0]=8'h21;
    for(k=0;k<12;k=k+1) begin
        memory[4+k*2]=(700+k)&255;
        memory[5+k*2]=(700+k)>>8;
        memory[30+k]=180+k;
    end
end
always @(negedge sda) if(scl===1'b1) begin
    active=1; reading=0; selected=0; count=0; stage=0; incoming=0;
end
always @(posedge sda) if(scl===1'b1) begin active=0; drive=0; end
always @(posedge scl) if(active) begin
    count=count+1;
    if(count<=8 && !reading) incoming={incoming[6:0],sda};
    if(count==9 && reading) master_nack=sda;
end
always @(negedge scl) if(active) begin
    if(reading) begin
        if(count<8) drive=!outgoing[7-count];
        else if(count==8) drive=0;
        else begin
            reads=reads+1;
            if(master_nack) begin reading=0; selected=0; drive=0; end
            else begin pointer=pointer+1; outgoing=memory[pointer]; drive=!outgoing[7]; end
            count=0;
        end
    end else begin
        if(count==8) begin
            if(stage==0) selected=enable && incoming[7:1]==ADDRESS;
            drive=selected && enable;
        end else if(count==9) begin
            drive=0;
            if(selected && enable) begin
                if(stage==0) begin
                    if(incoming[0]) begin reading=1; outgoing=memory[pointer]; drive=!outgoing[7]; end
                    else stage=1;
                end else if(stage==1) begin pointer=incoming; stage=2; end
                else begin memory[pointer]=incoming; pointer=pointer+1; end
            end
            count=0; incoming=0;
        end
    end
end
endmodule

`timescale 1ns / 1ps
module tb_hardware_lab;
reg clk=0,rstn=0,dout=0,rx=1;
reg [4:0] encoder_a=31,encoder_b=31,joystick=16;
reg [5:0] buttons=0;
tri1 [1:0] pad_scl,pad_sda;
wire [31:0] reads_left,reads_right;
integer output_file;
initial output_file=$fopen("all_uart.bin","wb");
MprBehavior left_pad(pad_scl[0],pad_sda[0],1'b1,reads_left);
MprBehavior right_pad(pad_scl[1],pad_sda[1],1'b1,reads_right);
wire [2:0] mux;
wire en,cs,sclk,din,tx,rgb;
reg [11:0] raw[0:31];
reg [199:0] vectors[0:54];
reg [1:0] selected=0;
reg [15:0] response=0,adc_command=0;
integer edges=0,conversions=0,col,i,j,raw_lines=0,next_key=1,press_events=0;
integer byte_index=0,bit_index,line_len,key_number,ack_count=0,old_ack,checks=0;
reg [7:0] rx_byte,line_bytes[0:99],last_seq,last_result,last_mode,last_gen,crc;
reg [71:0] status_payload;
reg [127:0] game_payload=0;
integer game_count=0,play_key,wrong_key;
reg [31:0] last_pressed=0;
reg last_configured=0,verify_static=1;
reg [11:0] raw_value;
HardwareLab #(.C_SETTLE_CYCLES(30),.C_UART_CYCLES(16),.C_FRAME_CYCLES(65000),
 .C_KEY_REPORT(200000),.C_ENCODER_REPORT(300000),.C_JOY_REPORT(150000),.C_TOUCH_REPORT(100000),.C_ID_REPORT(400000),
 .C_BUTTON_REPORT(300000),.C_BUTTON_FILTER(10),
 .C_ENCODER_FILTER(3),.C_JOY_FILTER(10),.C_I2C_DIVIDER(4),.C_TOUCH_BOOT(100),.C_TOUCH_RETRY(5000),.C_TOUCH_RESET(200),.C_TOUCH_TIMEOUT(100000)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_adc_dout(dout),.i_uart_rx(rx),.o_mux_sel(mux),.o_mux_en(en),
 .o_adc_cs_n(cs),.o_adc_sclk(sclk),.o_adc_din(din),.o_uart_tx(tx),.o_rgb(rgb),.i_encoder_a(encoder_a),.i_encoder_b(encoder_b),.i_joystick(joystick),.i_buttons(buttons),.i_irq(2'b11),.io_scl(pad_scl),.io_sda(pad_sda));
defparam dut.keyboard.CommandParser_Inst.C_TIMEOUT=1000;
always #10 clk=~clk;
always @(posedge clk) if(rstn)for(j=0;j<32;j=j+1)if(dut.keyboard.reg_press[j])press_events=press_events+1;
always @(negedge cs)begin
 case(mux)4:col=0;5:col=1;6:col=2;7:col=3;3:col=4;2:col=5;1:col=6;default:col=7;endcase
 edges=0;adc_command=0;response={4'b0,raw[selected*8+col]};dout=0;
end
always @(posedge sclk)if(!cs)begin adc_command={adc_command[14:0],din};edges=edges+1;end
always @(negedge sclk)if(!cs && edges<16)begin response={response[14:0],1'b0};dout<=#30 response[15];end
always @(posedge cs)if(rstn && edges!=0)begin
 if(edges!=16)begin $display("FAIL ADC edge count");$finish;end
 selected=adc_command[12:11];conversions=conversions+1;
end
function [3:0] nibble;
 input [7:0] ch;
 begin
  if(ch>=48 && ch<=57)nibble=ch-48;
  else if(ch>=65 && ch<=70)nibble=ch-55;
  else begin $display("FAIL hex character %h",ch);$finish;end
 end
endfunction
function [7:0] crc_byte;
 input [7:0] previous,value;
 reg [7:0] work;
 integer k;
 begin work=previous^value;for(k=0;k<8;k=k+1)work=work[7]?(work<<1)^8'h07:work<<1;crc_byte=work;end
endfunction
// Independently decode wire-level 8N1 telemetry, including interleaved replies.
initial forever begin
 @(negedge tx);#160;
 if(tx!==0)begin $display("FAIL UART start");$finish;end
 for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin #320;rx_byte[bit_index]=tx;end
 #320;if(tx!==1)begin $display("FAIL UART stop");$finish;end
 line_bytes[byte_index]=rx_byte;
 $fwrite(output_file,"%c",rx_byte);
 if(byte_index==0)begin
  if(rx_byte==75)line_len=9;else if(rx_byte==64)line_len=23;else if(rx_byte==35)line_len=37;
  else if(rx_byte==69)line_len=34;
  else if(rx_byte==74)line_len=21;
  else if(rx_byte==84)line_len=100;
  else if(rx_byte==71)line_len=37;
  else if(rx_byte==72)line_len=15;
  else if(rx_byte==66)line_len=87;
  else begin $display("FAIL line prefix %h",rx_byte);$finish;end
 end
 if(byte_index==line_len-1)begin
  byte_index=0;
  if(rx_byte!=10)begin $display("FAIL newline");$finish;end
  if(line_len==9)begin
   key_number=(line_bytes[1]-48)*10+line_bytes[2]-48;
   raw_value={nibble(line_bytes[4]),nibble(line_bytes[5]),nibble(line_bytes[6])};
   if(key_number!=next_key || line_bytes[3]!=58 || line_bytes[7]!=13)begin $display("FAIL raw key sequence");$finish;end
   if(verify_static && raw_value !== raw[key_number-1])begin $display("FAIL raw ADC value key%0d got%0d expected%0d",key_number,raw_value,raw[key_number-1]);$finish;end
   next_key=key_number==32?1:key_number+1;raw_lines=raw_lines+1;
  end else if(line_len==23)begin
   status_payload=0;
   for(checks=1;checks<=18;checks=checks+1)status_payload={status_payload[67:0],nibble(line_bytes[checks])};
   crc=0;for(checks=8;checks>=0;checks=checks-1)crc=crc_byte(crc,status_payload>>(checks*8));
   if(line_bytes[19]!=42 || crc!={nibble(line_bytes[20]),nibble(line_bytes[21])})begin $display("FAIL status CRC");$finish;end
   last_configured=status_payload[48];last_mode=status_payload[47:40];last_gen=status_payload[39:32];last_pressed=status_payload[31:0];
   if(status_payload[63:56]!=8'h80)begin last_seq=status_payload[71:64];last_result=status_payload[63:56];ack_count=ack_count+1;end
  end else if(line_bytes[0]==35)begin
   game_payload=0;
   for(checks=1;checks<=32;checks=checks+1)game_payload={game_payload[123:0],nibble(line_bytes[checks])};
   crc=0;for(checks=15;checks>=0;checks=checks-1)crc=crc_byte(crc,game_payload>>(checks*8));
   if(line_bytes[33]!=42 || crc!={nibble(line_bytes[34]),nibble(line_bytes[35])})begin $display("FAIL game CRC");$finish;end
   game_count=game_count+1;
  end
 end else byte_index=byte_index+1;
end
task send_byte;
 input [7:0] value;
 integer bit_number;
 begin
  @(negedge clk);rx=0;#320;
  for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin rx=value[bit_number];#320;end
  rx=1;#320;
 end
endtask
task transact;
 input integer vector_index;
 input [7:0] expected_result;
 integer character,timeout_count;
 reg [7:0] expected_seq;
 begin
  old_ack=ack_count;expected_seq={nibble(vectors[vector_index][191:184]),nibble(vectors[vector_index][183:176])};
  for(character=24;character>=0;character=character-1)send_byte(vectors[vector_index]>>(character*8));
  timeout_count=0;
  while(ack_count==old_ack && timeout_count<600000)begin @(negedge clk);timeout_count=timeout_count+1;end
  if(ack_count!=old_ack+1 || last_seq!=expected_seq || last_result!=expected_result)begin
   $display("FAIL command index=%0d ack=%0d seq=%0d expected_seq=%0d result=%0d expected=%0d",vector_index,ack_count-old_ack,last_seq,expected_seq,last_result,expected_result);$finish;
  end
 end
endtask
task wait_mask;
 input [31:0] expected_mask;
 integer timeout_count;
 begin
  timeout_count=0;
  while(last_pressed!==expected_mask && timeout_count<1500000)begin @(negedge clk);timeout_count=timeout_count+1;end
  if(last_pressed!==expected_mask)begin $display("FAIL pressed mask %h expected%h",last_pressed,expected_mask);$finish;end
 end
endtask
initial begin
 $readmemh("command_vectors.hex",vectors);
 for(i=0;i<32;i=i+1)raw[i]=i<16?900:100;
 #101;rstn=1;
 wait(dut.resetn);repeat(4)@(negedge clk);
 // An abandoned frame must time out and the next valid start must resynchronize.
 send_byte(33);send_byte(48);#30000;
 for(i=0;i<=40;i=i+1)begin
  case(i)1:transact(i,1);5:transact(i,4);7:transact(i,3);default:transact(i,0);endcase
  if(i<40 && last_configured)begin $display("FAIL premature calibration activation");$finish;end
 end
 if(!last_configured || last_gen!=1)begin $display("FAIL commit state");$finish;end
 transact(41,0);if(last_gen!=1)begin $display("FAIL duplicate commit executed twice");$finish;end
 transact(42,0);transact(43,2);transact(44,0);
 verify_static=0;
 // Concurrent encoders, joystick and dual-pad events while calibrated keyboard commands continue.
 encoder_a=0;#1000;encoder_b=0;#1000;encoder_a=31;#1000;encoder_b=31;
 joystick=0;#2000;joystick=16;
 wait(dut.touchpad.left_sequence>3 && dut.touchpad.right_sequence>3);
 left_pad.memory[0]=8'h10;left_pad.memory[1]=1;
 right_pad.memory[0]=8'h10;right_pad.memory[1]=1;
 #2000000;
 // A short simultaneous press is retained in counters even between B1 reports.
 buttons=63;#2000;
 if(dut.buttons.bus_pressed!==6'b111111) $fatal(1,"Six-key debounce failed");
 buttons=0;#2000;
 if(dut.buttons.bus_pressed!==0 || dut.buttons.bus_presses!==96'h000100010001000100010001 ||
    dut.buttons.bus_releases!==96'h000100010001000100010001) $fatal(1,"Six-key counts lost");
 // Exactly one outlying sample cannot trigger a key.
 @(negedge clk);raw[2]=100;
 wait(dut.keyboard.flag_sample_transfer && dut.keyboard.enc_key==2 && dut.keyboard.enc_raw==100);
 @(negedge clk);raw[2]=900;
 #2500000;
 if(press_events!=0 || last_pressed!=0)begin $display("FAIL one-sample spike");$finish;end
 raw[0]=100;raw[1]=100;raw[17]=900;
 wait_mask(32'h00020003);#2000000;
 if(press_events!=3)begin $display("FAIL hold repeats %0d",press_events);$finish;end
 raw[0]=900;raw[1]=400;raw[17]=600;
 wait_mask(32'h00020002);#2000000;
 if(last_pressed!=32'h00020002)begin $display("FAIL hysteresis");$finish;end
 raw[1]=900;raw[17]=100;wait_mask(0);
 for(i=45;i<=49;i=i+1)begin
  transact(i,0);
  case(i)
   45:if(last_mode!=8'h20)begin $display("FAIL ripple mode");$finish;end
   46:if(last_mode!=8'h30)begin $display("FAIL horizontal mode");$finish;end
   47:if(last_mode!=8'h31)begin $display("FAIL vertical mode");$finish;end
   48:if(last_mode!=8'h40)begin $display("FAIL cross mode");$finish;end
   49:if(last_mode!=0)begin $display("FAIL off mode");$finish;end
  endcase
 end

 transact(51,0);transact(52,0);transact(53,3);
 wait(game_payload[119:112]==2);
 if(game_payload[127:120]!=3 || game_payload[71:64]!=1)begin $display("FAIL game start/idempotent epoch");$finish;end
 play_key=24;
 for(i=24;i<32;i=i+1)if(game_payload[i*2+:2]==1)play_key=i;
 raw[play_key]=900;
 wait(game_payload[95:80]==1);
 raw[play_key]=100;wait_mask(0);
 wrong_key=24;
 for(i=24;i<32;i=i+1)if(game_payload[i*2+:2]==0)wrong_key=i;
 raw[wrong_key]=900;
 wait(game_payload[119:112]==3);
 if(game_payload[103:96]!=3 || game_payload[95:80]!=1)begin $display("FAIL ADC piano wrong-key result");$finish;end
 raw[wrong_key]=100;
 transact(54,0);
 if(last_mode!=8'h20)begin $display("FAIL game stop restores normal effect");$finish;end
 wait(game_payload[119:112]==0);
 if(game_count<10)begin $display("FAIL missing game telemetry");$finish;end
 $display("PASS games over real UART framing: CRC128, start, duplicate epoch, invalid game, ADC calibrated bottom-key hit, wrong-key game over, stop restores effect; game_frames=%0d",game_count);
 $fclose(output_file);
 @(negedge cs);#150;rstn=0;#40;
 if(cs!==1 || sclk!==0 || tx!==1 || en!==0 || rgb!==0 || dut.keyboard.flag_configured!==0)begin $display("FAIL reset state");$finish;end
 $display("PASS: UART command/reply CRC, timeout recovery, incomplete/invalid config rejection, atomic 32-key commit, idempotent retry, ADC scan, two-sample qualification, both polarities, hysteresis, no repeat, effect selection, reset. raw_lines=%0d conversions=%0d",raw_lines,conversions);$finish;
end
initial begin #1000000000;$display("FAIL timeout");$finish;end
endmodule
