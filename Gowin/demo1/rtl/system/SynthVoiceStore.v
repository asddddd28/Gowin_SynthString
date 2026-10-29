`timescale 1ns/1ps
////////////////////////////////////English///////////////////////////////////////
// Company: Tang Synth project
// Engineer: Codex
// Create Date: 2026/10/28
// Design Name: SynthVoiceStore
// Module Name: SynthVoiceStore
// Description: spec/system/SynthVoiceStore_spec.md
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
// 设计名称: SynthVoiceStore
// 模块名称: SynthVoiceStore
// 模块说明: spec/system/SynthVoiceStore_spec.md
// 仿真工程: sim/tb_axis_synth_system.v
// 参考资料: docs/modular-pipeline/system.md
// 依赖文件: sources-axis-system.f
// 当前版本: V1.0
// 修订日期: 2026年10月28日
// 修订历史: 2026年10月28日 V1.0 Codex 建立系统互联
module SynthVoiceStore #(parameter C_VOICES=8)(
 input i_clk, // 统一计算时钟
 input i_rstn, // 全系统低有效复位，释放须同步
 input i_cfg_write, // 经过空闲仲裁的配置写入
 input [4:0] i_cfg_voice, // 配置写地址
 input [375:0] i_cfg_data, // 完整音色参数
 input [4:0] i_read_voice, // 当前待发射声部
 output [375:0] o_profile, // 稳定的声部参数及待处理事件
 output [348:0] o_state, // 当前声部相位包络滤波及中间结果
 input i_write, // 已核对身份的结果提交
 input [4:0] i_write_voice, // 结果所属声部
 input [2:0] i_write_stage, // 本次更新的状态字段
 input [191:0] i_write_data, // 结果完整快照
 input i_event_consume, // 包络请求已接受，清除一次性事件
 input [4:0] i_event_voice // 已发射包络的声部
);

 reg [375:0] reg_profile[0:C_VOICES-1]; // 每声部独立音色快照
 reg [348:0] reg_state[0:C_VOICES-1]; // 中间字段按阶段更新，递归状态跨帧保存
 reg [1:0] reg_event[0:C_VOICES-1]; // 门控事件只消费一次
 integer reset_index;
 assign o_profile = {reg_profile[i_read_voice][375:171],reg_event[i_read_voice],reg_profile[i_read_voice][168:0]};
 assign o_state = reg_state[i_read_voice];
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn) begin
   for(reset_index=0;reset_index<C_VOICES;reset_index=reset_index+1) begin
    reg_profile[reset_index]<=376'd0;reg_state[reset_index]<=349'd0;reg_event[reset_index]<=2'd0;
   end
  end else begin
   if(i_cfg_write) begin reg_profile[i_cfg_voice]<=i_cfg_data;reg_event[i_cfg_voice]<=i_cfg_data[170:169];end
   else if(i_event_consume) reg_event[i_event_voice]<=2'd0;
   if(i_write) begin
    case(i_write_stage)
     3'd0:reg_state[i_write_voice][31:0]<=i_write_data[31:0];
     3'd1:reg_state[i_write_voice][284:253]<=i_write_data[31:0];
     3'd2:reg_state[i_write_voice][63:32]<=i_write_data[31:0];
     3'd3:reg_state[i_write_voice][316:285]<=i_write_data[31:0];
     3'd4:reg_state[i_write_voice][98:64]<=i_write_data[34:0];
     3'd5:reg_state[i_write_voice][348:317]<=i_write_data[31:0];
     3'd6:reg_state[i_write_voice][252:99]<=i_write_data[185:32];
     default:reg_state[i_write_voice]<=reg_state[i_write_voice];
    endcase
   end
  end
 end
endmodule
