`timescale 1ns/1ps
module tb_voice_smoothing;
 reg clk=0,rstn=0;
 always #10 clk=~clk;
 reg [4:0] state=0;
 reg [31:0] current=0,target=0,random=32'hb871ea83;
 reg [31:0] expected_gain,expected_pan;
 integer n;
 VoiceSynthEngine dut(.i_axis_aclk(clk),.i_axis_arstn(rstn),.i_touch_gain(18'd65536),.i_touch_pitch(32'd0),
  .i_s_axis_tdata(384'd0),.i_s_axis_tuser(32'd0),.i_s_axis_tdest(8'd0),.i_s_axis_tvalid(1'b0),
  .i_m_axis_tready(1'b1),.i_sample_tick(1'b0));
 function [31:0] expected;
  input [31:0] a,b;
  reg [31:0] distance,step;
  begin
   distance=a>b ? a-b : b-a;
   step=distance/64;
   if(distance!=0 && step==0)step=1;
   expected=a<b ? a+step : a-step;
  end
 endfunction
 initial begin
  force dut.reg_state=state;
  force dut.reg_voice=0;
  force dut.reg_gain_current=current;
  force dut.reg_gain_target=target;
  force dut.reg_pan_current=target;
  force dut.reg_pan_target=current;
  force dut.flag_mod_done=1;
  repeat(3)@(negedge clk);rstn=1;
  for(n=0;n<4096;n=n+1)begin
   random=random^(random<<13);random=random^(random>>17);random=random^(random<<5);
   current=random%67108865;
   random={random[30:0],random[31]^random[21]^random[1]^random[0]};target=random%67108865;
   if(n<128)begin current=33554432;target=33554368+n;end
   if(n==128)begin current=0;target=67108864;end
   if(n==129)begin current=67108864;target=0;end
   expected_gain=expected(current,target);expected_pan=expected(target,current);
   state=17;@(negedge clk);state=14;@(negedge clk);
   if(dut.reg_mod_gain!==expected_gain || dut.reg_mod_pan!==expected_pan ||
      dut.mem_gain[0]!==expected_gain || dut.mem_pan[0]!==expected_pan)
    $fatal(1,"smoothing differs from original vector %0d",n);
  end
  $display("PASS smoothing: 4096 exact gain/pan and baseline writes, endpoints and sub-64 distances");$finish;
 end
endmodule
