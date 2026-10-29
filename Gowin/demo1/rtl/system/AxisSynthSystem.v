`timescale 1ns/1ps
////////////////////////////////////English///////////////////////////////////////
// Company: Tang Synth project
// Engineer: Codex
// Create Date: 2026/10/28
// Design Name: AxisSynthSystem
// Module Name: AxisSynthSystem
// Description: spec/system/AxisSynthSystem_spec.md
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
// 设计名称: AxisSynthSystem
// 模块名称: AxisSynthSystem
// 模块说明: spec/system/AxisSynthSystem_spec.md
// 仿真工程: sim/tb_axis_synth_system.v
// 参考资料: docs/modular-pipeline/system.md
// 依赖文件: sources-axis-system.f
// 当前版本: V1.0
// 修订日期: 2026年10月28日
// 修订历史: 2026年10月28日 V1.0 Codex 建立系统互联
module AxisSynthSystem #(parameter C_VOICES=8, parameter C_MIX_SHIFT=3, parameter C_FRAME_STEP=2, parameter C_PT8211=0)(
 input i_clk, // 统一计算时钟
 input i_rstn, // 全系统低有效复位，释放须同步
 input i_run, // 配置结束后启动音频；只在空闲时停止
 input i_cfg_valid, // 源端持有完整声部配置
 output o_cfg_ready, // 仅空闲帧接收配置
 input [4:0] i_cfg_voice, // 目标声部索引
 input [375:0] i_cfg_data, // 音色参数和一次性门控事件
 input i_wave_valid, // 波表上传字有效
 output o_wave_ready, // 空闲时允许更新波表
 input i_wave_frame, // 选择波表的A或B帧
 input [10:0] i_wave_address, // 银行位及1024点地址
 input [15:0] i_wave_data, // 有符号波表采样
 output o_pcm_valid, // 完整混音帧可消费
 output [23:0] o_pcm_left, // 限幅后的左声道PCM
 output [23:0] o_pcm_right, // 首版复制单声道到右声道
 output o_busy, // 当前音频帧尚未完全退役
 output o_overrun, // 忙时采样触发丢失的粘滞标志
 output o_fault, // 返回身份或算法错误，需要复位
 output [15:0] o_frame_cycles, // 最近完成帧的计算周期数
 output o_result_valid, // 一个有效声部尾部结果提交
 output [4:0] o_result_voice, // 本次提交所属声部
 output [191:0] o_result_data, // 完整音频与滤波新状态
 output o_sample_tick, // 音频帧节拍监测
 output o_bclk, // 串行位时钟
 output o_lrclk, // 左右声道选择
 output o_sdata, // I2S音频输出
 output o_mclk, // 主音频时钟
 output o_underrun // I2S缺帧粘滞标志
);

 wire flag_audio_reset;
 wire flag_start;
 // 控制端和全部算术模块同域。板级PLL、复位同步和主机跨时钟桥由外层提供。
 assign flag_audio_reset=i_rstn&&i_run;
 assign flag_start=o_sample_tick&&i_run;
 AxisSynthEngine #(.C_VOICES(C_VOICES),.C_MIX_SHIFT(C_MIX_SHIFT)) Engine_Inst(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_start(flag_start),.i_pcm_ready(1'b1),
 .i_cfg_valid(i_cfg_valid),
 .o_cfg_ready(o_cfg_ready),
 .i_cfg_voice(i_cfg_voice),
 .i_cfg_data(i_cfg_data),
 .i_wave_valid(i_wave_valid),
 .o_wave_ready(o_wave_ready),
 .i_wave_frame(i_wave_frame),
 .i_wave_address(i_wave_address),
 .i_wave_data(i_wave_data),
 .o_pcm_valid(o_pcm_valid),
 .o_pcm_left(o_pcm_left),
 .o_pcm_right(o_pcm_right),
 .o_busy(o_busy),
 .o_overrun(o_overrun),
 .o_fault(o_fault),
 .o_frame_cycles(o_frame_cycles),
 .o_result_valid(o_result_valid),
 .o_result_voice(o_result_voice),
 .o_result_data(o_result_data));
 I2sTx #(.C_PT8211(C_PT8211),.C_FRAME_STEP(C_FRAME_STEP)) I2s_Inst(
 .i_clk(i_clk),.i_rstn(flag_audio_reset),.i_sample_valid(o_pcm_valid),.i_left(o_pcm_left),.i_right(o_pcm_right),
 .o_sample_tick(o_sample_tick),.o_bclk(o_bclk),.o_lrclk(o_lrclk),.o_sdata(o_sdata),.o_mclk(o_mclk),.o_underrun(o_underrun));

endmodule
