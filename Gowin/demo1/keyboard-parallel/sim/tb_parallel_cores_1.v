`timescale 1ns/1ps
// Compare sample/state values independently of the two engines' completion times.
module tb_parallel_cores_1;
 parameter C_PHASE=1,C_WAVE=1,C_ENV=1,C_MOD=1,C_FILTER=1,C_VCA=1;
 reg clk=0,rstn=0,start=0,cfg=0,wave_valid=0,wave_frame=0,pcm_ready=1;
 reg [4:0] voice=0;reg [511:0] config_data=0;
 reg [10:0] wave_address=0;reg [15:0] wave_data=0;
 reg [511:0] profiles[0:31];reg [15:0] waves[0:2047];
 wire [1:0] cfg_ready,wave_ready,pcm_valid,busy,fault,overrun,result_valid;
 wire [4:0] old_voice,new_voice;
 wire [191:0] old_result,new_result;
 wire [23:0] old_pcm,new_pcm;
 wire [15:0] old_cycles,new_cycles;
 reg [191:0] expected_results[0:31],actual_results[0:31];
 reg [31:0] old_seen=0,new_seen=0;
 reg [23:0] expected_pcm=0,actual_pcm=0;
 reg old_pcm_seen=0,new_pcm_seen=0;
 integer i,f,ticks=0,compared=0,random_state=1729;
 always #10 clk=~clk;
 KeyboardSynthEngine #(.C_VOICES(32),.C_MIX_SHIFT(5)) baseline(
 .i_clk(clk),.i_rstn(rstn),.i_start(start),.i_cfg_valid(cfg),.o_cfg_ready(cfg_ready[0]),.i_cfg_voice(voice),.i_cfg_data(config_data),
 .i_wave_valid(wave_valid),.o_wave_ready(wave_ready[0]),.i_wave_frame(wave_frame),.i_wave_address(wave_address),.i_wave_data(wave_data),
 .o_pcm_valid(pcm_valid[0]),.i_pcm_ready(pcm_ready),.o_pcm_left(old_pcm),.o_busy(busy[0]),.o_fault(fault[0]),.o_overrun(overrun[0]),.o_frame_cycles(old_cycles),
 .o_result_valid(result_valid[0]),.o_result_voice(old_voice),.o_result_data(old_result));
 ParallelSynthEngine #(.C_VOICES(32),.C_MIX_SHIFT(5),.C_PHASE_CORES(C_PHASE),.C_WAVE_CORES(C_WAVE),.C_ENV_CORES(C_ENV),.C_MOD_CORES(C_MOD),.C_FILTER_CORES(C_FILTER),.C_VCA_CORES(C_VCA)) candidate(
 .i_clk(clk),.i_rstn(rstn),.i_start(start),.i_cfg_valid(cfg),.o_cfg_ready(cfg_ready[1]),.i_cfg_voice(voice),.i_cfg_data(config_data),
 .i_wave_valid(wave_valid),.o_wave_ready(wave_ready[1]),.i_wave_frame(wave_frame),.i_wave_address(wave_address),.i_wave_data(wave_data),
 .o_pcm_valid(pcm_valid[1]),.i_pcm_ready(pcm_ready),.o_pcm_left(new_pcm),.o_busy(busy[1]),.o_fault(fault[1]),.o_overrun(overrun[1]),.o_frame_cycles(new_cycles),
 .o_result_valid(result_valid[1]),.o_result_voice(new_voice),.o_result_data(new_result));
 always @(posedge clk)if(rstn)begin
  ticks=ticks+1;
  if(fault!=0||overrun!=0)$fatal(1,"fault/overrun baseline=%b candidate=%b",fault,overrun);
  if(result_valid[0])begin
   if(old_seen[old_voice])$fatal(1,"duplicate baseline voice");
   old_seen[old_voice]=1;expected_results[old_voice]=old_result;
  end
  if(result_valid[1])begin
   if(new_seen[new_voice])$fatal(1,"duplicate candidate voice");
   new_seen[new_voice]=1;actual_results[new_voice]=new_result;
  end
  if(pcm_valid[0]&&pcm_ready)begin expected_pcm=old_pcm;old_pcm_seen=1;end
  if(pcm_valid[1]&&pcm_ready)begin actual_pcm=new_pcm;new_pcm_seen=1;end
  if(candidate.Prefetch_Inst.cnt_reserved>8||candidate.Prefetch_Inst.cnt_queued>8)$fatal(1,"prefetch capacity");
 end
 task configure;
  input integer key;input [511:0] value;
  begin
   while(cfg_ready!=3)@(negedge clk);
   cfg=1;voice=key;config_data=value;@(negedge clk);cfg=0;
  end
 endtask
 task frame;
  begin
   old_seen=0;new_seen=0;old_pcm_seen=0;new_pcm_seen=0;
   start=1;@(negedge clk);start=0;
   while(busy!=0||!old_pcm_seen||!new_pcm_seen)begin
    random_state=(random_state*1103515245+12345)&32'h7fffffff;
    pcm_ready=(random_state%7)!=0;@(negedge clk);
   end
   pcm_ready=1;
   if(old_seen!==32'hffffffff||new_seen!==32'hffffffff)$fatal(1,"missing voice results");
   for(i=0;i<32;i=i+1)begin
    if(expected_results[i]!==actual_results[i])$fatal(1,"voice/state mismatch frame=%d voice=%d old=%h new=%h",f,i,expected_results[i],actual_results[i]);
    if(baseline.Store_Inst.mem_mod_envelope[i]!==candidate.Store_Inst.mem_mod_envelope[i])$fatal(1,"mod envelope mismatch");
    if(baseline.Store_Inst.mem_envelope[i]!==candidate.Store_Inst.mem_envelope[i])$fatal(1,"amp envelope mismatch");
    if(baseline.Store_Inst.mem_phase_mod[i]!==candidate.Store_Inst.mem_phase_mod[i]||baseline.Store_Inst.mem_phase_carrier[i]!==candidate.Store_Inst.mem_phase_carrier[i])$fatal(1,"phase mismatch");
   end
   if(expected_pcm!==actual_pcm)$fatal(1,"PCM mismatch");
   compared=compared+32;
  end
 endtask
 initial begin
  $readmemh("equivalence_profiles.hex",profiles);$readmemh("equivalence_waves.hex",waves);
  repeat(5)@(negedge clk);rstn=1;
  for(i=0;i<32;i=i+1)begin config_data=profiles[i];config_data[482]=1;config_data[170:169]=1;configure(i,config_data);end
  for(i=0;i<2048;i=i+1)begin
   while(wave_ready!=3)@(negedge clk);
   wave_valid=1;wave_frame=i>=1024;wave_address=i%1024;wave_data=waves[i];@(negedge clk);
  end
  wave_valid=0;
  for(f=0;f<160;f=f+1)begin
   if(f>=32&&f<64)begin config_data=profiles[f-32];config_data[170:169]=2;config_data[483]=1;configure(f-32,config_data);end
   if(f>=96&&f<128)begin config_data=profiles[f-96];config_data[170:169]=1;configure(f-96,config_data);end
   frame;
  end
  // Cancel in-flight jobs, reinitialize states, then ensure no old result can retire.
  start=1;@(negedge clk);start=0;repeat(20)@(negedge clk);rstn=0;
  repeat(5)@(negedge clk);rstn=1;@(negedge clk);
  for(i=0;i<32;i=i+1)begin config_data=profiles[i];config_data[482]=1;config_data[170:169]=1;configure(i,config_data);end
  for(f=0;f<8;f=f+1)frame;
  $display("PASS equivalence voices=%0d PCM=168 cores=%0d/%0d/%0d/%0d/%0d/%0d baseline=%0d parallel=%0d",compared,C_PHASE,C_WAVE,C_ENV,C_MOD,C_FILTER,C_VCA,old_cycles,new_cycles);
  $finish;
 end
 initial #10000000 $fatal(1,"equivalence watchdog");
endmodule
