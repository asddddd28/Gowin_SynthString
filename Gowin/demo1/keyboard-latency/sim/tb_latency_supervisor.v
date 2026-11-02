`timescale 1ns/1ps
module tb_latency_supervisor;
 reg clk=0,rstn=0,clear=0,initialized=1,sample=0,candidate=0,confirm=0,cancel=0;
 reg [4:0] sample_key=0,commit_key=0,result_key=0;
 reg [31:0] physical=0,effective=0,result_sample=0;
 reg commit=0,result_valid=0,pcm_valid=0,pcm_nonzero=0,frame_load=0,latch=0;
 wire [879:0] payload;
 reg [31:0] tick=32'hffffff00;
 reg [31:0] t_start[0:31],t_detect[0:31],t_commit[0:31],t_first[0:31],t_voice[0:31],t_pcm[0:31],t_dac[0:31];
 reg [31:0] expected_valid=0;
 integer observed=0,previous_count=0,key,n;
 reg [31:0] expected_total;
 always #10 clk=~clk;
 always @(posedge clk)if(!rstn)tick<=32'hffffff00;else tick<=tick+1'b1;
 LatencySupervisor #(.C_TIMEOUT_CYCLES(1000),.C_BUDGET_CYCLES(180),.C_INITIAL_TICK(32'hffffff00)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_clear(clear),.i_initialized(initialized),.i_sample_valid(sample),.i_sample_key(sample_key),
 .i_candidate(candidate),.i_confirm(confirm),.i_cancel(cancel),.i_physical(physical),.i_effective(effective),
 .i_commit(commit),.i_commit_key(commit_key),.i_result_valid(result_valid),.i_result_key(result_key),.i_result_sample(result_sample),
 .i_pcm_valid(pcm_valid),.i_pcm_nonzero(pcm_nonzero),.i_frame_load(frame_load),.i_dac_left_latch(latch),.o_payload(payload));
 always @(negedge clk)if(rstn&&!clear)begin
  if(payload[31:0]!=previous_count)begin
   if(payload[31:0]!=previous_count+1)$fatal(1,"unexpected record count");
   previous_count=payload[31:0];key=payload[36:32];
   if(!expected_valid[key])$fatal(1,"unexpected completion key=%0d",key);
   expected_valid[key]=0;expected_total=t_dac[key]-t_start[key];
   if(payload[95:64]!==expected_total)$fatal(1,"total key=%0d got=%0d expected=%0d",key,payload[95:64],expected_total);
   if(payload[127:96]!==t_detect[key]-t_start[key])$fatal(1,"debounce");
   if(payload[159:128]!==t_commit[key]-t_detect[key])$fatal(1,"queue");
   if(payload[191:160]!==t_first[key]-t_commit[key])$fatal(1,"compute");
   if(payload[223:192]!==t_dac[key]-t_voice[key])$fatal(1,"output");
   if(payload[255:224]!==t_pcm[key]-t_voice[key])$fatal(1,"mix");
   if(payload[767:736]!==t_voice[key]-t_first[key])$fatal(1,"onset wait");
   observed=observed+1;
  end
 end
 task reset_stats;
  begin @(negedge clk);#1;clear=1;effective=0;physical=0;expected_valid=0;previous_count=0;
   @(negedge clk);#1;clear=0;repeat(5)@(negedge clk);#1;end
 endtask
 task remote_begin;
  input integer k;
  begin @(negedge clk);#1;effective[k]=1;t_start[k]=tick;t_detect[k]=tick;@(negedge clk);#1;end
 endtask
 task send_commit;
  input integer k;
  begin @(negedge clk);#1;commit=1;commit_key=k;t_commit[k]=tick;@(negedge clk);#1;commit=0;end
 endtask
 task send_result;
  input integer k;input integer value;input integer first;
  begin @(negedge clk);#1;result_valid=1;result_key=k;result_sample=value;
   if(first)t_first[k]=tick;if(value!=0)t_voice[k]=tick;
   @(negedge clk);#1;result_valid=0;end
 endtask
 task play_frame;
  input [31:0] mask;
  integer j;
  begin @(negedge clk);#1;pcm_valid=1;pcm_nonzero=1;
   for(j=0;j<32;j=j+1)if(mask[j])t_pcm[j]=tick;
   @(negedge clk);#1;pcm_valid=0;
   repeat(5)@(negedge clk);#1;frame_load=1;
   @(negedge clk);#1;frame_load=0;
   repeat(20)@(negedge clk);#1;latch=1;
   for(j=0;j<32;j=j+1)if(mask[j])t_dac[j]=tick;
   expected_valid=mask;
   @(negedge clk);#1;latch=0;
   repeat(40)@(negedge clk);#1;
   if(expected_valid!=0)$fatal(1,"completion drain");
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);#1;rstn=1;
  // A first crossing canceled by the next sample must not become a record.
  @(negedge clk);#1;sample=1;candidate=1;sample_key=2;
  @(negedge clk);#1;candidate=0;sample=0;
  repeat(4)@(negedge clk);#1;sample=1;cancel=1;
  @(negedge clk);#1;sample=0;cancel=0;
  repeat(8)@(negedge clk);#1;
  if(payload[799:768]!=1||payload[735:704]!=0)$fatal(1,"candidate cancellation");
  // Physical debounce + a zero result + a nonzero result in a muted PCM frame.
  sample_key=3;sample=1;candidate=1;t_start[3]=tick;
  @(negedge clk);#1;sample=0;candidate=0;
  repeat(100)@(negedge clk);#1;sample=1;confirm=1;t_detect[3]=tick;
  @(negedge clk);#1;sample=0;confirm=0;physical[3]=1;effective[3]=1;
  send_commit(3);send_result(3,0,1);repeat(15)@(negedge clk);
  send_result(3,100,0);
  @(negedge clk);#1;pcm_valid=1;pcm_nonzero=0;
  @(negedge clk);#1;pcm_valid=0;
  repeat(25)@(negedge clk);send_result(3,-100,0);play_frame(32'h8);
  if(!payload[40]||payload[671:640]!==t_dac[3])$fatal(1,"physical source or DAC stamp");
  // 32 independent simultaneous notes, with timestamps spanning counter wrap.
  reset_stats();effective=32'hffffffff;
  for(n=0;n<32;n=n+1)begin t_start[n]=tick;t_detect[n]=tick;end
  @(negedge clk);#1;
  for(n=0;n<32;n=n+1)send_commit(n);
  for(n=0;n<32;n=n+1)send_result(n,n+1,1);
  play_frame(32'hffffffff);
  if(payload[31:0]!=32||payload[575:544]!=32)$fatal(1,"32-key accounting");
  // A replacement must not publish the old generation; silence must time out.
  reset_stats();remote_begin(4);send_commit(4);send_result(4,0,1);
  effective[4]=0;repeat(3)@(negedge clk);remote_begin(4);
  send_commit(4);send_result(4,1,1);play_frame(32'h10);
  if(payload[479:448]!=1)$fatal(1,"overwrite accounting %d",payload[479:448]);
  remote_begin(7);send_commit(7);send_result(7,0,1);
  repeat(1100)@(negedge clk);#1;
  if(payload[447:416]!=1||payload[735:704]!=0)$fatal(1,"silent timeout");
  reset_stats();repeat(50)@(negedge clk);
  if(payload[31:0]!=0||payload[735:704]!=0)$fatal(1,"clear left stale transactions");
  $display("PASS latency supervisor exact parts, wrap, 32 keys, debounce cancel, zero PCM, timeout, overwrite, clear; records=%0d",observed);$finish;
 end
 initial #200000 $fatal(1,"watchdog");
endmodule
