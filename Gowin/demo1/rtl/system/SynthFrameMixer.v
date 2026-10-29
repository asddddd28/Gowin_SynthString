`timescale 1ns/1ps
////////////////////////////////////English///////////////////////////////////////
// Company: Tang Synth project
// Engineer: Codex
// Create Date: 2026/10/28
// Design Name: SynthFrameMixer
// Module Name: SynthFrameMixer
// Description: spec/system/SynthFrameMixer_spec.md
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
// 设计名称: SynthFrameMixer
// 模块名称: SynthFrameMixer
// 模块说明: spec/system/SynthFrameMixer_spec.md
// 仿真工程: sim/tb_axis_synth_system.v
// 参考资料: docs/modular-pipeline/system.md
// 依赖文件: sources-axis-system.f
// 当前版本: V1.0
// 修订日期: 2026年10月28日
// 修订历史: 2026年10月28日 V1.0 Codex 建立系统互联
module SynthFrameMixer #(parameter C_MIX_SHIFT=3)(
 input i_clk, // 统一计算时钟
 input i_rstn, // 全系统低有效复位，释放须同步
 input i_start, // 开始一帧，清除旧累加值
 input i_valid, // 一个声部音频提交
 input [31:0] i_sample, // 有符号Q17声部样值
 input i_last, // 最后一个声部已提交
 output o_pcm_valid, // 完整混音帧可消费
 input i_pcm_ready, // 音频出口消费当前帧
 output [23:0] o_pcm_left, // 限幅后的左声道PCM
 output [23:0] o_pcm_right // 首版复制单声道到右声道
);

 reg signed [63:0] reg_sum;
 wire signed [63:0] wire_extended,wire_sum,wire_scaled;
 reg flag_valid;
 reg [23:0] pcm_o;
 assign wire_extended={{32{i_sample[31]}},i_sample};
 assign wire_sum=reg_sum+wire_extended;
 assign wire_scaled=(wire_sum >>> C_MIX_SHIFT) <<< 6;
 assign o_pcm_valid=flag_valid;assign o_pcm_left=pcm_o;assign o_pcm_right=pcm_o;
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn) begin reg_sum<=0;flag_valid<=0;pcm_o<=0;end
  else begin
   if(flag_valid&&i_pcm_ready) flag_valid<=0;
   if(i_start) reg_sum<=0;
   else if(i_valid) begin
    reg_sum<=wire_sum;
    if(i_last) begin
     flag_valid<=1;
     if(wire_scaled>64'sd8388607) pcm_o<=24'h7fffff;
     else if(wire_scaled< -64'sd8388608) pcm_o<=24'h800000;
     else pcm_o<=wire_scaled[23:0];
    end
   end
  end
 end
endmodule
