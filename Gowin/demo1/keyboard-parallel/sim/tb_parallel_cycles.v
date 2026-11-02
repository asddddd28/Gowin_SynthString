`timescale 1ns/1ps
module tb_parallel_cycles;
 reg clk=0,rstn=0,start=0,cfg=0;
 reg [4:0] voice=0;reg [511:0] config_data=0;
 reg [511:0] profiles[0:31];
 wire cfg_ready,pcm,busy,fault,overrun;wire [15:0] cycles;
 integer i,tick=0,stage_start=0;
 always #10 clk=~clk;
 ParallelSynthEngine #(.C_VOICES(32),.C_MIX_SHIFT(5)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_start(start),.i_cfg_valid(cfg),.o_cfg_ready(cfg_ready),.i_cfg_voice(voice),.i_cfg_data(config_data),
 .i_wave_valid(1'b0),.i_wave_frame(1'b0),.i_wave_address(11'd0),.i_wave_data(16'd0),
 .o_pcm_valid(pcm),.i_pcm_ready(1'b1),.o_busy(busy),.o_fault(fault),.o_overrun(overrun),.o_frame_cycles(cycles));
 always @(posedge clk)begin
  tick=tick+1;
  if(dut.flag_start)stage_start=tick;
  if(dut.flag_last)begin $display("STAGE %0d %0d",dut.reg_stage,tick-stage_start);stage_start=tick;end
  if(fault||overrun)$fatal(1,"baseline fault");
 end
 initial begin
  $readmemh("note_profiles.hex",profiles);repeat(5)@(negedge clk);rstn=1;
  for(i=0;i<32;i=i+1)begin
   @(negedge clk);cfg=1;voice=i;config_data=profiles[i];config_data[482]=1;config_data[170:169]=1;
   while(!cfg_ready)@(negedge clk);
   @(negedge clk);cfg=0;
  end
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(pcm);@(negedge clk);$display("PASS parallel cycles %0d",cycles);$finish;
 end
 initial #100000 $fatal(1,"baseline timeout");
endmodule
