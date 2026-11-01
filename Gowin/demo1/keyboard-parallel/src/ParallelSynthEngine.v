`timescale 1ns/1ps
////////////////////////////////////English///////////////////////////////////////
// Company: Tang Synth project
// Engineer: Codex
// Create Date: 2026/10/28
// Design Name: AxisSynthEngine
// Module Name: AxisSynthEngine
// Description: spec/system/AxisSynthEngine_spec.md
// Simulations: sim/tb_axis_synth_system.v
// Referrences: docs/modular-pipeline/system.md
// Dependencies: sources-axis-system.f
// Version: V1.0
// Revision Date: 2026/10/28
// History: 2026/10/28 V1.0 Codex Create system interconnect.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属: Tang Synth 项目
// 开发人员: Codex
// 创建日期: 2026年10月28日
// 设计名称: AxisSynthEngine
// 模块名称: AxisSynthEngine
// 模块说明: spec/system/AxisSynthEngine_spec.md
// 仿真工程: sim/tb_axis_synth_system.v
// 参考资料: docs/modular-pipeline/system.md
// 依赖文件: sources-axis-system.f
// 当前版本: V1.0
// 修订日期: 2026年10月28日
// 修订历史: 2026年10月28日 V1.0 Codex 建立系统互联
module ParallelSynthEngine #(parameter C_PHASE_CORES=1,parameter C_WAVE_CORES=2,parameter C_ENV_CORES=3,parameter C_MOD_CORES=1,parameter C_FILTER_CORES=1,parameter C_VCA_CORES=1,parameter C_VOICES=32,parameter C_MIX_SHIFT=5)(
 input i_clk, // 统一计算时钟
 input i_rstn, // 全系统低有效复位，释放须同步
 input i_start, // 请求计算下一音频帧，忙时拒收并记过载
 input i_cfg_valid, // 源端持有完整声部配置
 output o_cfg_ready, // 仅空闲帧接收配置
 input [4:0] i_cfg_voice, // 目标声部索引
 input [511:0] i_cfg_data, // 音色参数和一次性门控事件
 input i_wave_valid, // 波表上传字有效
 output o_wave_ready, // 空闲时允许更新波表
 input i_wave_frame, // 选择波表的A或B帧
 input [10:0] i_wave_address, // 银行位及1024点地址
 input [15:0] i_wave_data, // 有符号波表采样
 output o_pcm_valid, // 完整混音帧可消费
 input i_pcm_ready, // 音频出口消费当前帧
 output [23:0] o_pcm_left, // 限幅后的左声道PCM
 output [23:0] o_pcm_right, // 首版复制单声道到右声道
 output o_busy, // 当前音频帧尚未完全退役
 output o_overrun, // 忙时采样触发丢失的粘滞标志
 output o_fault, // 返回身份或算法错误，需要复位
 output [15:0] o_frame_cycles, // 最近完成帧的计算周期数
 output o_result_valid, // 一个有效声部尾部结果提交
 output [4:0] o_result_voice, // 本次提交所属声部
 output [31:0] o_active, output [6:0] o_stages,
 output [31:0] o_wave_peak, output [31:0] o_mod_peak, output [17:0] o_env_peak,
 output [191:0] o_result_data // 完整音频与滤波新状态
);
 wire [127:0] wire_phase_input; wire [31:0] wire_phase_output; wire [20:0] wire_phase_tag;
 wire flag_phase_input_ready,flag_phase_output_valid;
 wire [53:0] wire_wave_input; wire [31:0] wire_wave_output; wire [20:0] wire_wave_tag;
 wire flag_wave_input_ready,flag_wave_output_valid;
 wire [111:0] wire_env_input; wire [63:0] wire_env_output; wire [20:0] wire_env_tag;
 wire flag_env_input_ready,flag_env_output_valid;
 wire [135:0] wire_am_input; wire [63:0] wire_am_output; wire [20:0] wire_am_tag;
 wire flag_am_input_ready,flag_am_output_valid;
 wire [351:0] wire_tail_input; wire [191:0] wire_tail_output; wire [20:0] wire_tail_tag;
 wire flag_tail_input_ready,flag_tail_output_valid;

 localparam [1:0] C_IDLE=0,C_RUN=1,C_PCM=2;
 reg [1:0] state_current,state_next;
 reg [2:0] reg_stage;
 wire flag_run;
 wire flag_task_valid;
 wire [351:0] wire_task;
 reg [5:0] cnt_issue,cnt_retire;
 reg [15:0] cnt_epoch,cnt_cycles,cycles_o;
 reg flag_overrun,flag_fault;
 reg [31:0] reg_enabled;
 wire [511:0] wire_profile;
 wire [383:0] wire_state;
 wire [4:0] wire_read_voice;
 wire [20:0] wire_issue_tag,wire_retire_tag;
 wire flag_start,flag_issue,flag_return,flag_last,flag_identity,flag_commit;
 reg flag_input_ready,flag_output_valid,flag_algorithm_error;
 reg [191:0] reg_result;
 reg [20:0] reg_return_tag;
 wire flag_cfg,flag_wave_write,flag_env_consume;
 wire flag_wave_stage,flag_phase_stage,flag_env_stage,flag_am_stage,flag_tail_stage;
 wire [23:0] wire_mix_left,wire_mix_right;
 wire [31:0] wire_mix_sample;
 assign flag_run=state_current==C_RUN;
 assign flag_start=(state_current==C_IDLE)&&i_start&&!flag_fault;
 assign o_busy=state_current!=C_IDLE;
 assign o_fault=flag_fault;assign o_overrun=flag_overrun;assign o_frame_cycles=cycles_o;
 // 一帧内配置不可变；并行接口的源端需要保持VALID和整包直到READY。
 assign o_cfg_ready=(state_current==C_IDLE)&&!i_start&&!flag_fault&&(i_cfg_voice<C_VOICES);
 assign o_wave_ready=(state_current==C_IDLE)&&!i_start&&!flag_fault;
 assign flag_cfg=i_cfg_valid&&o_cfg_ready;
 assign flag_wave_write=i_wave_valid&&o_wave_ready;
 assign wire_retire_tag={cnt_epoch,cnt_retire[4:0]};
 assign flag_issue=flag_run&&flag_task_valid&&flag_input_ready;
 assign flag_return=flag_run&&flag_output_valid;
 assign flag_last=flag_return&&(cnt_retire==C_VOICES-1);
 assign flag_identity=reg_return_tag==wire_retire_tag;
 assign flag_commit=flag_return&&flag_identity&&!flag_algorithm_error&&!flag_fault;
 assign flag_phase_stage=flag_run&&((reg_stage==0)||(reg_stage==2));
 assign flag_wave_stage=flag_run&&((reg_stage==1)||(reg_stage==3));
 assign flag_env_stage=flag_run&&((reg_stage==4)||(reg_stage==7));
 assign flag_am_stage=flag_run&&(reg_stage==5);
 assign flag_tail_stage=flag_run&&(reg_stage==6);
 assign flag_env_consume=flag_env_stage&&(reg_stage==4)&&flag_issue;
 assign o_result_valid=flag_return&&flag_tail_stage;
 assign o_result_voice=cnt_retire[4:0];assign o_result_data=reg_result;
 assign wire_mix_sample=(flag_commit&&reg_enabled[cnt_retire[4:0]])?reg_result[31:0]:32'd0;
 assign o_pcm_left=flag_fault?24'd0:wire_mix_left;
 assign o_pcm_right=flag_fault?24'd0:wire_mix_right;
 StudioVoiceStore #(.C_VOICES(C_VOICES)) Store_Inst(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_cfg_write(flag_cfg),.i_cfg_voice(i_cfg_voice),.i_cfg_data(i_cfg_data),
 .i_read_voice(wire_read_voice),.o_profile(wire_profile),.o_state(wire_state),
 .i_write(flag_commit),.i_write_voice(cnt_retire[4:0]),.i_write_stage(reg_stage),.i_write_data(reg_result),
 .i_event_consume(flag_env_consume),.i_event_voice(wire_issue_tag[4:0]));
 SynthTaskPrefetch #(.C_VOICES(C_VOICES)) Prefetch_Inst(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_begin(flag_start||(flag_last&&reg_stage!=6)),.i_run(flag_run),.i_stage(reg_stage),.i_epoch(cnt_epoch),
 .o_read_voice(wire_read_voice),.i_profile(wire_profile),.i_state(wire_state),
 .o_valid(flag_task_valid),.i_ready(flag_input_ready),.o_data(wire_task),.o_user(wire_issue_tag));
 KeyboardFrameMixer #(.C_MIX_SHIFT(C_MIX_SHIFT)) Mixer_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_start(flag_start),
 .i_valid(o_result_valid),.i_sample(wire_mix_sample),.i_last(flag_last),
 .o_pcm_valid(o_pcm_valid),.i_pcm_ready(i_pcm_ready),.o_pcm_left(wire_mix_left),.o_pcm_right(wire_mix_right));
 // 三段式FSM：状态寄存器、下一状态组合决策、独立阶段和计数任务。
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn) state_current<=C_IDLE;else state_current<=state_next;
 end
 always @(*) begin
  state_next=state_current;
  case(state_current)
   C_IDLE:if(flag_start) state_next=C_RUN;
   C_RUN:if(flag_last&&reg_stage==6) state_next=C_PCM;
   C_PCM:if(o_pcm_valid&&i_pcm_ready) state_next=C_IDLE;
   default:state_next=C_IDLE;
  endcase
 end
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn) begin
   reg_stage<=7;cnt_issue<=0;cnt_retire<=0;cnt_epoch<=0;cnt_cycles<=0;cycles_o<=0;
   flag_overrun<=0;flag_fault<=0;reg_enabled<=0;
  end else begin
   if(i_start&&o_busy) flag_overrun<=1;
   if(flag_cfg) reg_enabled[i_cfg_voice]<=i_cfg_data[368];
   if(flag_return&&(!flag_identity||flag_algorithm_error)) flag_fault<=1;
   case(state_current)
    C_IDLE:if(flag_start) begin reg_stage<=7;cnt_issue<=0;cnt_retire<=0;cnt_epoch<=cnt_epoch+1'b1;cnt_cycles<=0;end
    C_RUN:begin
     cnt_cycles<=cnt_cycles+1'b1;
     if(flag_issue) cnt_issue<=cnt_issue+1'b1;
     if(flag_return) cnt_retire<=cnt_retire+1'b1;
     if(flag_last) begin
      cnt_issue<=0;cnt_retire<=0;
      if(reg_stage==6) cycles_o<=cnt_cycles+1'b1;
      else if(reg_stage==7)reg_stage<=0;else reg_stage<=reg_stage+1'b1;
     end
    end
    C_PCM:begin end
    default:begin reg_stage<=7;cnt_issue<=0;cnt_retire<=0;end
   endcase
  end
 end
 AxisComputePool #(.C_KIND(0),.C_CORES(C_PHASE_CORES),.C_INPUT_WIDTH(128),.C_OUTPUT_WIDTH(32),.C_ADDR_WIDTH(3)) Phase_Inst(.i_axis_aclk(i_clk),.i_axis_arstn(i_rstn),
 .i_s_axis_tdata(wire_phase_input),.i_s_axis_tuser(wire_issue_tag),.i_s_axis_tvalid(flag_phase_stage&&flag_task_valid),.o_s_axis_tready(flag_phase_input_ready),
 .o_m_axis_tdata(wire_phase_output),.o_m_axis_tuser(wire_phase_tag),.o_m_axis_tvalid(flag_phase_output_valid),.i_m_axis_tready(flag_phase_stage),.i_wave_write(1'b0),.i_wave_frame(1'b0),.i_wave_address(11'd0),.i_wave_data(16'd0));
 AxisComputePool #(.C_KIND(1),.C_CORES(C_WAVE_CORES),.C_INPUT_WIDTH(54),.C_OUTPUT_WIDTH(32),.C_ADDR_WIDTH(3)) Wave_Inst(.i_axis_aclk(i_clk),.i_axis_arstn(i_rstn),
 .i_s_axis_tdata(wire_wave_input),.i_s_axis_tuser(wire_issue_tag),.i_s_axis_tvalid(flag_wave_stage&&flag_task_valid),.o_s_axis_tready(flag_wave_input_ready),
 .o_m_axis_tdata(wire_wave_output),.o_m_axis_tuser(wire_wave_tag),.o_m_axis_tvalid(flag_wave_output_valid),.i_m_axis_tready(flag_wave_stage),.i_wave_write(flag_wave_write),.i_wave_frame(i_wave_frame),.i_wave_address(i_wave_address),.i_wave_data(i_wave_data));
 AxisComputePool #(.C_KIND(2),.C_CORES(C_ENV_CORES),.C_INPUT_WIDTH(112),.C_OUTPUT_WIDTH(64),.C_ADDR_WIDTH(3)) Envelope_Inst(.i_axis_aclk(i_clk),.i_axis_arstn(i_rstn),
 .i_s_axis_tdata(wire_env_input),.i_s_axis_tuser(wire_issue_tag),.i_s_axis_tvalid(flag_env_stage&&flag_task_valid),.o_s_axis_tready(flag_env_input_ready),
 .o_m_axis_tdata(wire_env_output),.o_m_axis_tuser(wire_env_tag),.o_m_axis_tvalid(flag_env_output_valid),.i_m_axis_tready(flag_env_stage),.i_wave_write(1'b0),.i_wave_frame(1'b0),.i_wave_address(11'd0),.i_wave_data(16'd0));
 AxisComputePool #(.C_KIND(3),.C_CORES(C_MOD_CORES),.C_INPUT_WIDTH(136),.C_OUTPUT_WIDTH(64),.C_ADDR_WIDTH(4)) Modulation_Inst(.i_axis_aclk(i_clk),.i_axis_arstn(i_rstn),
 .i_s_axis_tdata(wire_am_input),.i_s_axis_tuser(wire_issue_tag),.i_s_axis_tvalid(flag_am_stage&&flag_task_valid),.o_s_axis_tready(flag_am_input_ready),
 .o_m_axis_tdata(wire_am_output),.o_m_axis_tuser(wire_am_tag),.o_m_axis_tvalid(flag_am_output_valid),.i_m_axis_tready(flag_am_stage),.i_wave_write(1'b0),.i_wave_frame(1'b0),.i_wave_address(11'd0),.i_wave_data(16'd0));
 ParallelVoiceChain #(.C_ADDR_WIDTH(5),.C_FILTER_CORES(C_FILTER_CORES),.C_VCA_CORES(C_VCA_CORES)) Tail_Inst(.i_axis_aclk(i_clk),.i_axis_arstn(i_rstn),
 .i_s_axis_tdata(wire_tail_input),.i_s_axis_tuser(wire_issue_tag),.i_s_axis_tvalid(flag_tail_stage&&flag_task_valid),.o_s_axis_tready(flag_tail_input_ready),
 .o_m_axis_tdata(wire_tail_output),.o_m_axis_tuser(wire_tail_tag),.o_m_axis_tvalid(flag_tail_output_valid),.i_m_axis_tready(flag_tail_stage));

 assign wire_phase_input=wire_task[127:0];
 assign wire_wave_input=wire_task[53:0];
 assign wire_env_input=wire_task[111:0];
 assign wire_am_input=wire_task[135:0];
 assign wire_tail_input=wire_task;
 // 每个阶段先发射所有声部；全部返回后才进入后继阶段，避免读到旧递归状态。
 always @(*) begin
  flag_input_ready=0;flag_output_valid=0;reg_result=0;reg_return_tag=0;flag_algorithm_error=0;
  case(reg_stage)
   0,2:begin flag_input_ready=flag_phase_input_ready;flag_output_valid=flag_phase_output_valid;reg_result={160'd0,wire_phase_output};reg_return_tag=wire_phase_tag;end
   1,3:begin flag_input_ready=flag_wave_input_ready;flag_output_valid=flag_wave_output_valid;reg_result={160'd0,wire_wave_output};reg_return_tag=wire_wave_tag;end
   4,7:begin flag_input_ready=flag_env_input_ready;flag_output_valid=flag_env_output_valid;reg_result={128'd0,wire_env_output};reg_return_tag=wire_env_tag;flag_algorithm_error=wire_env_output[35];end
   5:begin flag_input_ready=flag_am_input_ready;flag_output_valid=flag_am_output_valid;reg_result={128'd0,wire_am_output};reg_return_tag=wire_am_tag;flag_algorithm_error=wire_am_output[34];end
   6:begin flag_input_ready=flag_tail_input_ready;flag_output_valid=flag_tail_output_valid;reg_result=wire_tail_output;reg_return_tag=wire_tail_tag;flag_algorithm_error=wire_tail_output[187];end
   default:begin flag_input_ready=0;flag_output_valid=0;reg_result=0;reg_return_tag=0;flag_algorithm_error=1;end
  endcase
 end


 reg [31:0] reg_active,reg_wave_peak,reg_mod_peak;
 reg [17:0] reg_env_peak;
 reg [6:0] reg_stages;
 reg [31:0] reg_wave_sample,reg_mod_sample,reg_wave_magnitude,reg_mod_magnitude;
 reg [1:0] flag_wave_observe,flag_mod_observe;
 assign o_active=reg_active;assign o_stages=reg_stages;
 assign o_wave_peak=reg_wave_peak;assign o_mod_peak=reg_mod_peak;assign o_env_peak=reg_env_peak;
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin
   reg_active<=0;reg_stages<=0;reg_wave_peak<=0;reg_mod_peak<=0;reg_env_peak<=0;
   reg_wave_sample<=0;reg_mod_sample<=0;reg_wave_magnitude<=0;reg_mod_magnitude<=0;
   flag_wave_observe<=0;flag_mod_observe<=0;
  end else begin
   flag_wave_observe<={flag_wave_observe[0],flag_wave_output_valid&&flag_wave_stage&&reg_stage==3&&!flag_fault};
   flag_mod_observe<={flag_mod_observe[0],flag_am_output_valid&&flag_am_stage&&!flag_fault};
   reg_wave_sample<=wire_wave_output;reg_mod_sample<=wire_am_output[31:0];
   reg_wave_magnitude<=reg_wave_sample[31]?-reg_wave_sample:reg_wave_sample;
   reg_mod_magnitude<=reg_mod_sample[31]?-reg_mod_sample:reg_mod_sample;
   if(flag_wave_observe[1]&&reg_wave_magnitude>reg_wave_peak)reg_wave_peak<=reg_wave_magnitude;
   if(flag_mod_observe[1]&&reg_mod_magnitude>reg_mod_peak)reg_mod_peak<=reg_mod_magnitude;
   if(flag_commit&&reg_stage!=7)reg_stages[reg_stage]<=1;
   if(flag_env_output_valid&&flag_env_stage&&reg_stage==4&&!flag_fault&&!wire_env_output[35])begin
    reg_active[wire_env_tag[4:0]]<=wire_env_output[34:32]!=0;
    if(wire_env_output[31:14]>reg_env_peak)reg_env_peak<=wire_env_output[31:14];
   end
  end
 end
endmodule
