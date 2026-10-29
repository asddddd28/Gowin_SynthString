`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/12 19:13:44
// Design Name:     SurgeSvfSample
// Module Name:     SurgeSvfSample
// Description:     description/SurgeSvfSample_Design.pdf
// Simulations:     testbench/vivado/2021.1/SurgeSvfSample
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/12 19:13:44
// History:
// Time             Version     Revised by        Contents
// 2026/10/12       V1.0        Codex              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月12日
// 设计名称:        SurgeSvfSample
// 模块名称:        SurgeSvfSample
// 模块说明:        Description/SurgeSvfSample_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/SurgeSvfSample
//
// 参考资料:        None
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年10月12日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月12日   V1.0        Codex              创建文件

module SurgeSvfSample
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 计算时钟
	input i_rstn,                               // 异步低有效复位
	input i_clear,                              // 声部重用时丢弃旧递归状态

	//-----------------用户接口-----------------//
	input i_valid,                              // 输入快照的事务有效资格
	input [4:0]i_voice,                         // 调用者拥有的声部编号
	input [15:0]i_generation,                   // 本事务所属的配置世代
	input [2:0]i_mode,                          // 原生模式编号：低通1、高通4、带通6
	input signed [31:0]i_sample,                // 当前滤波输入的二十六位小数幅度
	input signed [31:0]i_band,                  // 上一采样的带通递归状态
	input signed [31:0]i_low,                   // 上一采样的低通递归状态
	input signed [31:0]i_damping,               // 上一采样已算出的非线性阻尼
	input signed [28:0]i_low_residue,           // 低通积分器的有符号乘积余数
	input signed [28:0]i_band_residue,          // 带通积分器的有符号乘积余数
	input signed [31:0]i_frequency,             // 本采样已推进的频率系数
	input signed [31:0]i_resonance,             // 本采样已推进的共振系数
	input signed [31:0]i_clip,                  // 本采样已推进的非线性阻尼系数
	input signed [31:0]i_gain,                  // 本采样已推进的输出增益系数
	output o_valid,                             // 完整结果快照具有提交资格
	output [4:0]o_voice,                        // 与结果同时输出的声部所有者
	output [15:0]o_generation,                  // 供提交端检查的参数世代标签
	output signed [31:0]o_sample,               // 按所选滤波模式完成增益补偿的音频
	output signed [31:0]o_band,                 // 下个采样应使用的带通递归幅度
	output signed [31:0]o_low,                  // 接续声部低频轨迹的新状态
	output signed [31:0]o_damping,              // 下一次双步积分的非线性衰减系数
	output signed [28:0]o_low_residue,          // 低通下一采样带入的小数误差
	output signed [28:0]o_band_residue,         // 带通累加可继续保留的乘法余数
	output o_saturated,                         // 当前事务至少一次发生整数边界钳位
	output o_error                              // 模式编号无效，外部不得提交本结果
);

	//----------------寄存器信号----------------//
	reg [1151:0]reg_cutoff_waiting = 1152'd0;   // 截止频率移位历史队列
	reg [28:0]reg_old_low_residue_waiting = 29'd0; // 前态低通余差移位历史队列
	reg [129:0]reg_low_first_corrected_waiting = 130'd0; // 低通初段校正移位历史队列
	reg [127:0]reg_old_low_waiting = 128'd0;    // 前态低通移位历史队列
	reg [959:0]reg_sample_waiting = 960'd0;     // 音频移位历史队列
	reg [703:0]reg_resonance_waiting = 704'd0;  // 共振移位历史队列
	reg [258:0]reg_high_first_resonance_rounded_waiting = 259'd0; // 高通初段共振缩放值移位历史队列
	reg [405:0]reg_old_band_residue_waiting = 406'd0; // 前态带通余差移位历史队列
	reg [63:0]reg_band_first_product_waiting = 64'd0; // 带通初段乘积移位历史队列
	reg [129:0]reg_band_first_corrected_waiting = 130'd0; // 带通初段校正移位历史队列
	reg [575:0]reg_old_band_waiting = 576'd0;   // 前态带通移位历史队列
	reg [463:0]reg_low_first_residue_waiting = 464'd0; // 低通初段余差移位历史队列
	reg [63:0]reg_low_second_product_waiting = 64'd0; // 低通尾段乘积移位历史队列
	reg [129:0]reg_low_second_corrected_waiting = 130'd0; // 低通尾段校正移位历史队列
	reg [607:0]reg_low_first_limited_waiting = 608'd0; // 低通初段安全幅度移位历史队列
	reg [295:0]reg_high_second_resonance_rounded_waiting = 296'd0; // 高通尾段共振缩放值移位历史队列
	reg [492:0]reg_band_first_residue_waiting = 493'd0; // 带通初段余差移位历史队列
	reg [127:0]reg_band_second_product_waiting = 128'd0; // 带通尾段乘积移位历史队列
	reg [129:0]reg_band_second_corrected_waiting = 130'd0; // 带通尾段校正移位历史队列
	reg [639:0]reg_band_first_limited_waiting = 640'd0; // 带通初段安全幅度移位历史队列
	reg [623:0]reg_clip_narrow_waiting = 624'd0; // 阻尼系数有效精度移位历史队列
	reg [1407:0]reg_old_damping_waiting = 1408'd0; // 前态阻尼移位历史队列
	reg [191:0]reg_low_selected_waiting = 192'd0; // 低通选定幅度移位历史队列
	reg [263:0]reg_mode_partial_waiting = 264'd0; // 模式中间和移位历史队列
	reg [1535:0]reg_gain_waiting = 1536'd0;     // 增益移位历史队列
	reg [724:0]reg_low_second_residue_waiting = 725'd0; // 低通尾段余差移位历史队列
	reg [289:0]reg_band_second_residue_waiting = 290'd0; // 带通尾段余差移位历史队列
	reg [274:0]reg_voice_waiting = 275'd0;      // 声部标签移位历史队列
	reg [879:0]reg_generation_waiting = 880'd0; // 配置代号移位历史队列
	reg [63:0]reg_sample_output_limited_waiting = 64'd0; // 音频提交安全幅度移位历史队列
	reg [159:0]reg_band_recursion_limited_waiting = 160'd0; // 带通回授安全幅度移位历史队列
	reg [639:0]reg_low_recursion_limited_waiting = 640'd0; // 低通回授安全幅度移位历史队列
	reg [799:0]reg_damping_next_waiting = 800'd0; // 阻尼下拍状态移位历史队列
	reg signed [64:0]reg_band_first_corrected = 65'd0; // 带通初段校正寄存值
	reg signed [38:0]reg_band_first_sum = 39'd0; // 带通初段累加寄存值
	reg signed [64:0]reg_band_second_corrected = 65'd0; // 带通尾段校正寄存值
	reg signed [38:0]reg_band_second_sum = 39'd0; // 带通尾段累加寄存值
	reg signed [64:0]reg_low_first_corrected = 65'd0; // 低通初段校正寄存值
	reg signed [38:0]reg_low_first_sum = 39'd0; // 低通初段累加寄存值
	reg signed [64:0]reg_low_second_corrected = 65'd0; // 低通尾段校正寄存值
	reg signed [38:0]reg_low_second_sum = 39'd0; // 低通尾段累加寄存值
	reg signed [32:0]reg_mode_partial = 33'd0;  // 模式中间和寄存值
	reg signed [33:0]reg_mode_selected = 34'd0; // 模式选定幅度寄存值
	reg signed [65:0]reg_band_first_biased = 66'd0; // 带通初段舍入偏置寄存值
	reg signed [64:0]reg_band_recursion_biased = 65'd0; // 带通回授舍入偏置寄存值
	reg signed [65:0]reg_band_second_biased = 66'd0; // 带通尾段舍入偏置寄存值
	reg signed [65:0]reg_damping_clip_biased = 66'd0; // 阻尼阻尼系数舍入偏置寄存值
	reg signed [64:0]reg_damping_square_biased = 65'd0; // 阻尼能量平方舍入偏置寄存值
	reg signed [64:0]reg_high_first_resonance_biased = 65'd0; // 高通初段共振舍入偏置寄存值
	reg signed [64:0]reg_high_second_resonance_biased = 65'd0; // 高通尾段共振舍入偏置寄存值
	reg signed [65:0]reg_low_first_biased = 66'd0; // 低通初段舍入偏置寄存值
	reg signed [64:0]reg_low_recursion_biased = 65'd0; // 低通回授舍入偏置寄存值
	reg signed [65:0]reg_low_second_biased = 66'd0; // 低通尾段舍入偏置寄存值
	reg signed [64:0]reg_sample_gain_biased = 65'd0; // 音频增益舍入偏置寄存值
	reg signed [25:0]reg_clip_narrow = 26'd0;   // 阻尼系数有效精度寄存值
	reg signed [28:0]reg_band_first_residue = 29'd0; // 带通初段余差寄存值
	reg signed [31:0]reg_band_first_value = 32'd0; // 带通初段低位候选寄存值
	reg signed [31:0]reg_band_recursion_value = 32'd0; // 带通回授低位候选寄存值
	reg signed [28:0]reg_band_second_residue = 29'd0; // 带通尾段余差寄存值
	reg signed [31:0]reg_band_second_value = 32'd0; // 带通尾段低位候选寄存值
	reg signed [31:0]reg_high_first_deviation_value = 32'd0; // 高通初段残差低位候选寄存值
	reg signed [31:0]reg_high_first_value = 32'd0; // 高通初段低位候选寄存值
	reg signed [31:0]reg_high_second_deviation_value = 32'd0; // 高通尾段残差低位候选寄存值
	reg signed [31:0]reg_high_second_value = 32'd0; // 高通尾段低位候选寄存值
	reg signed [28:0]reg_low_first_residue = 29'd0; // 低通初段余差寄存值
	reg signed [31:0]reg_low_first_value = 32'd0; // 低通初段低位候选寄存值
	reg signed [31:0]reg_low_recursion_value = 32'd0; // 低通回授低位候选寄存值
	reg signed [28:0]reg_low_second_residue = 29'd0; // 低通尾段余差寄存值
	reg signed [31:0]reg_low_second_value = 32'd0; // 低通尾段低位候选寄存值
	reg signed [31:0]reg_mode_amplitude = 32'd0; // 模式音频幅度寄存值
	reg signed [31:0]reg_sample_output_value = 32'd0; // 音频提交低位候选寄存值
	reg signed [31:0]reg_band_selected = 32'd0; // 带通选定幅度寄存值
	reg signed [31:0]reg_high_selected = 32'd0; // 高通选定幅度寄存值
	reg signed [31:0]reg_low_selected = 32'd0;  // 低通选定幅度寄存值
	reg signed [31:0]reg_band_first_limited = 32'd0; // 带通初段安全幅度寄存值
	reg signed [31:0]reg_band_recursion_limited = 32'd0; // 带通回授安全幅度寄存值
	reg signed [31:0]reg_band_second_limited = 32'd0; // 带通尾段安全幅度寄存值
	reg signed [31:0]reg_high_first_deviation_limited = 32'd0; // 高通初段残差安全幅度寄存值
	reg signed [31:0]reg_high_first_limited = 32'd0; // 高通初段安全幅度寄存值
	reg signed [31:0]reg_high_second_deviation_limited = 32'd0; // 高通尾段残差安全幅度寄存值
	reg signed [31:0]reg_high_second_limited = 32'd0; // 高通尾段安全幅度寄存值
	reg signed [31:0]reg_low_first_limited = 32'd0; // 低通初段安全幅度寄存值
	reg signed [31:0]reg_low_recursion_limited = 32'd0; // 低通回授安全幅度寄存值
	reg signed [31:0]reg_low_second_limited = 32'd0; // 低通尾段安全幅度寄存值
	reg signed [31:0]reg_sample_output_limited = 32'd0; // 音频提交安全幅度寄存值
	reg signed [28:0]reg_band_first_residue_input = 29'd0; // 带通初段余差输入寄存值
	reg signed [28:0]reg_band_residue_final = 29'd0; // 带通余差尾级寄存值
	reg signed [28:0]reg_band_second_residue_input = 29'd0; // 带通尾段余差输入寄存值
	reg signed [28:0]reg_low_residue_final = 29'd0; // 低通余差尾级寄存值
	reg signed [28:0]reg_low_second_residue_input = 29'd0; // 低通尾段余差输入寄存值
	reg signed [31:0]reg_old_band = 32'd0;      // 前态带通寄存值
	reg signed [28:0]reg_old_band_residue = 29'd0; // 前态带通余差寄存值
	reg signed [31:0]reg_old_damping = 32'd0;   // 前态阻尼寄存值
	reg signed [31:0]reg_old_low = 32'd0;       // 前态低通寄存值
	reg signed [28:0]reg_old_low_residue = 29'd0; // 前态低通余差寄存值
	reg signed [31:0]reg_damping_next = 32'd0;  // 阻尼下拍状态寄存值
	reg signed [63:0]reg_band_first_product = 64'd0; // 带通初段乘积寄存值
	reg signed [63:0]reg_band_recursion_product = 64'd0; // 带通回授乘积寄存值
	reg signed [63:0]reg_band_second_product = 64'd0; // 带通尾段乘积寄存值
	reg signed [64:0]reg_damping_clip_product = 65'd0; // 阻尼阻尼系数乘积寄存值
	reg signed [63:0]reg_damping_square_product = 64'd0; // 阻尼能量平方乘积寄存值
	reg signed [63:0]reg_high_first_resonance_product = 64'd0; // 高通初段共振乘积寄存值
	reg signed [63:0]reg_high_second_resonance_product = 64'd0; // 高通尾段共振乘积寄存值
	reg signed [63:0]reg_low_first_product = 64'd0; // 低通初段乘积寄存值
	reg signed [63:0]reg_low_recursion_product = 64'd0; // 低通回授乘积寄存值
	reg signed [63:0]reg_low_second_product = 64'd0; // 低通尾段乘积寄存值
	reg signed [63:0]reg_sample_gain_product = 64'd0; // 音频增益乘积寄存值
	reg signed [65:0]reg_band_first_residue_wide = 66'd0; // 带通初段余差宽值寄存值
	reg signed [65:0]reg_band_second_residue_wide = 66'd0; // 带通尾段余差宽值寄存值
	reg signed [65:0]reg_low_first_residue_wide = 66'd0; // 低通初段余差宽值寄存值
	reg signed [65:0]reg_low_second_residue_wide = 66'd0; // 低通尾段余差宽值寄存值
	reg signed [37:0]reg_band_first_rounded = 38'd0; // 带通初段缩放值寄存值
	reg signed [38:0]reg_band_recursion_rounded = 39'd0; // 带通回授缩放值寄存值
	reg signed [37:0]reg_band_second_rounded = 38'd0; // 带通尾段缩放值寄存值
	reg signed [37:0]reg_damping_clip_rounded = 38'd0; // 阻尼阻尼系数缩放值寄存值
	reg signed [38:0]reg_damping_square_rounded = 39'd0; // 阻尼能量平方缩放值寄存值
	reg signed [36:0]reg_high_first_resonance_rounded = 37'd0; // 高通初段共振缩放值寄存值
	reg signed [36:0]reg_high_second_resonance_rounded = 37'd0; // 高通尾段共振缩放值寄存值
	reg signed [37:0]reg_low_first_rounded = 38'd0; // 低通初段缩放值寄存值
	reg signed [38:0]reg_low_recursion_rounded = 39'd0; // 低通回授缩放值寄存值
	reg signed [37:0]reg_low_second_rounded = 38'd0; // 低通尾段缩放值寄存值
	reg signed [36:0]reg_sample_gain_rounded = 37'd0; // 音频增益缩放值寄存值
	reg signed [32:0]reg_high_first_deviation = 33'd0; // 高通初段残差寄存值
	reg signed [37:0]reg_high_first_sum = 38'd0; // 高通初段累加寄存值
	reg signed [32:0]reg_high_second_deviation = 33'd0; // 高通尾段残差寄存值
	reg signed [37:0]reg_high_second_sum = 38'd0; // 高通尾段累加寄存值
	reg signed [38:0]reg_damping_candidate = 39'd0; // 阻尼计算候选寄存值

	//-----------------标志信号-----------------//
	reg [6:0]flag_saturation_start_waiting = 7'd0; // 整数饱和事务起点移位历史队列
	reg [1:0]flag_low_first_history_waiting = 2'd0; // 低通初段饱和记忆移位历史队列
	reg [1:0]flag_high_first_deviation_history_waiting = 2'd0; // 高通初段残差饱和记忆移位历史队列
	reg [6:0]flag_high_first_history_waiting = 7'd0; // 高通初段饱和记忆移位历史队列
	reg [6:0]flag_band_first_history_waiting = 7'd0; // 带通初段饱和记忆移位历史队列
	reg [1:0]flag_low_second_history_waiting = 2'd0; // 低通尾段饱和记忆移位历史队列
	reg [1:0]flag_high_second_deviation_history_waiting = 2'd0; // 高通尾段残差饱和记忆移位历史队列
	reg [7:0]flag_band_first_overflow_waiting = 8'd0; // 带通初段边界故障移位历史队列
	reg [2:0]flag_high_second_deviation_overflow_waiting = 3'd0; // 高通尾段残差边界故障移位历史队列
	reg [5:0]flag_band_residue_early_discard_waiting = 6'd0; // 带通余差较早区间余数丢弃移位历史队列
	reg [7:0]flag_high_second_history_waiting = 8'd0; // 高通尾段饱和记忆移位历史队列
	reg [3:0]flag_band_second_history_waiting = 4'd0; // 带通尾段饱和记忆移位历史队列
	reg [15:0]flag_low_recursion_overflow_waiting = 16'd0; // 低通回授边界故障移位历史队列
	reg [28:0]flag_mode_low_waiting = 29'd0;    // 模式低通移位历史队列
	reg [34:0]flag_mode_high_waiting = 35'd0;   // 模式高通移位历史队列
	reg [43:0]flag_mode_band_waiting = 44'd0;   // 模式带通移位历史队列
	reg [0:0]flag_low_recursion_history_waiting = 1'd0; // 低通回授饱和记忆移位历史队列
	reg [54:0]flag_valid_waiting = 55'd0;       // 事务资格移位历史队列
	reg [0:0]flag_sample_output_history_waiting = 1'd0; // 音频提交饱和记忆移位历史队列
	reg [52:0]flag_mode_invalid_waiting = 53'd0; // 模式非法编号移位历史队列

	// 延时后的事务控制条件
	wire flag_band_first_history_at_thirty;     // 延时带通初段饱和记忆供低通尾段饱和记忆
	wire flag_band_first_overflow_at_thirty;    // 延时带通初段边界故障供带通余差较早区间余数丢弃
	wire flag_band_residue_early_discard_at_thirty_seven; // 延时带通余差较早区间余数丢弃供带通余差生存区间余数丢弃
	wire flag_band_second_history_at_fifty;     // 延时带通尾段饱和记忆供带通回授饱和记忆
	wire flag_high_first_deviation_history_at_fourteen; // 延时高通初段残差饱和记忆供高通初段饱和记忆
	wire flag_high_first_history_at_twenty_two; // 延时高通初段饱和记忆供带通初段饱和记忆
	wire flag_high_second_deviation_history_at_thirty_six; // 延时高通尾段残差饱和记忆供高通尾段饱和记忆
	wire flag_high_second_deviation_overflow_at_thirty_six; // 延时高通尾段残差边界故障供带通余差后续区间余数丢弃
	wire flag_high_second_history_at_forty_five; // 延时高通尾段饱和记忆供带通尾段饱和记忆
	wire flag_low_first_history_at_eleven;      // 延时低通初段饱和记忆供高通初段残差饱和记忆
	wire flag_low_recursion_history_at_fifty_three; // 延时低通回授饱和记忆供音频提交饱和记忆
	wire flag_low_recursion_overflow_at_fifty_one; // 延时低通回授边界故障供低通回授饱和记忆
	wire flag_low_second_history_at_thirty_three; // 延时低通尾段饱和记忆供高通尾段残差饱和记忆
	wire flag_mode_band_at_forty_five;          // 延时模式带通供带通选定幅度
	wire flag_mode_high_at_thirty_six;          // 延时模式高通供高通选定幅度
	wire flag_mode_invalid_at_fifty_five;       // 延时模式非法编号供模式拒绝
	wire flag_mode_low_at_thirty;               // 延时模式低通供低通选定幅度
	wire flag_sample_output_history_at_fifty_five; // 延时音频提交饱和记忆供饱和状态
	wire flag_saturation_start_at_eight;        // 延时整数饱和事务起点供低通初段饱和记忆
	wire flag_valid_at_fifty_five;              // 延时事务资格供事务资格
	reg flag_mode_invalid = 1'd0;               // 模式非法编号寄存值
	reg flag_band_first_lower = 1'd0;           // 带通初段负越界寄存值
	reg flag_band_recursion_lower = 1'd0;       // 带通回授负越界寄存值
	reg flag_band_second_lower = 1'd0;          // 带通尾段负越界寄存值
	reg flag_high_first_deviation_lower = 1'd0; // 高通初段残差负越界寄存值
	reg flag_high_first_lower = 1'd0;           // 高通初段负越界寄存值
	reg flag_high_second_deviation_lower = 1'd0; // 高通尾段残差负越界寄存值
	reg flag_high_second_lower = 1'd0;          // 高通尾段负越界寄存值
	reg flag_low_first_lower = 1'd0;            // 低通初段负越界寄存值
	reg flag_low_recursion_lower = 1'd0;        // 低通回授负越界寄存值
	reg flag_low_second_lower = 1'd0;           // 低通尾段负越界寄存值
	reg flag_sample_output_lower = 1'd0;        // 音频提交负越界寄存值
	reg flag_saturation_start = 1'd0;           // 整数饱和事务起点寄存值
	reg flag_mode_band = 1'd0;                  // 模式带通寄存值
	reg flag_mode_high = 1'd0;                  // 模式高通寄存值
	reg flag_mode_low = 1'd0;                   // 模式低通寄存值
	reg flag_band_first_history = 1'd0;         // 带通初段饱和记忆寄存值
	reg flag_band_first_overflow = 1'd0;        // 带通初段边界故障寄存值
	reg flag_band_recursion_history = 1'd0;     // 带通回授饱和记忆寄存值
	reg flag_band_recursion_overflow = 1'd0;    // 带通回授边界故障寄存值
	reg flag_band_residue_early_discard = 1'd0; // 带通余差较早区间余数丢弃寄存值
	reg flag_band_residue_interval_discard = 1'd0; // 带通余差生存区间余数丢弃寄存值
	reg flag_band_residue_late_discard = 1'd0;  // 带通余差后续区间余数丢弃寄存值
	reg flag_band_second_history = 1'd0;        // 带通尾段饱和记忆寄存值
	reg flag_band_second_overflow = 1'd0;       // 带通尾段边界故障寄存值
	reg flag_high_first_deviation_history = 1'd0; // 高通初段残差饱和记忆寄存值
	reg flag_high_first_deviation_overflow = 1'd0; // 高通初段残差边界故障寄存值
	reg flag_high_first_history = 1'd0;         // 高通初段饱和记忆寄存值
	reg flag_high_first_overflow = 1'd0;        // 高通初段边界故障寄存值
	reg flag_high_second_deviation_history = 1'd0; // 高通尾段残差饱和记忆寄存值
	reg flag_high_second_deviation_overflow = 1'd0; // 高通尾段残差边界故障寄存值
	reg flag_high_second_history = 1'd0;        // 高通尾段饱和记忆寄存值
	reg flag_high_second_overflow = 1'd0;       // 高通尾段边界故障寄存值
	reg flag_low_first_history = 1'd0;          // 低通初段饱和记忆寄存值
	reg flag_low_first_overflow = 1'd0;         // 低通初段边界故障寄存值
	reg flag_low_recursion_history = 1'd0;      // 低通回授饱和记忆寄存值
	reg flag_low_recursion_overflow = 1'd0;     // 低通回授边界故障寄存值
	reg flag_low_second_history = 1'd0;         // 低通尾段饱和记忆寄存值
	reg flag_low_second_overflow = 1'd0;        // 低通尾段边界故障寄存值
	reg flag_sample_output_history = 1'd0;      // 音频提交饱和记忆寄存值
	reg flag_sample_output_overflow = 1'd0;     // 音频提交边界故障寄存值
	reg flag_band_first_upper = 1'd0;           // 带通初段正越界寄存值
	reg flag_band_recursion_upper = 1'd0;       // 带通回授正越界寄存值
	reg flag_band_second_upper = 1'd0;          // 带通尾段正越界寄存值
	reg flag_high_first_deviation_upper = 1'd0; // 高通初段残差正越界寄存值
	reg flag_high_first_upper = 1'd0;           // 高通初段正越界寄存值
	reg flag_high_second_deviation_upper = 1'd0; // 高通尾段残差正越界寄存值
	reg flag_high_second_upper = 1'd0;          // 高通尾段正越界寄存值
	reg flag_low_first_upper = 1'd0;            // 低通初段正越界寄存值
	reg flag_low_recursion_upper = 1'd0;        // 低通回授正越界寄存值
	reg flag_low_second_upper = 1'd0;           // 低通尾段正越界寄存值
	reg flag_sample_output_upper = 1'd0;        // 音频提交正越界寄存值

	//-----------------其他信号-----------------//
	// 算术寄存级需要的历史抽头
	wire signed [64:0]wire_band_first_corrected_at_nineteen; // 延时带通初段校正供带通初段余差宽值
	wire signed [31:0]wire_band_first_limited_at_forty_two; // 延时带通初段安全幅度供带通尾段累加
	wire signed [63:0]wire_band_first_product_at_sixteen; // 延时带通初段乘积供带通初段校正
	wire signed [28:0]wire_band_first_residue_at_thirty_eight; // 延时带通初段余差供带通尾段余差输入
	wire signed [31:0]wire_band_recursion_limited_at_fifty_five; // 延时带通回授安全幅度供带通
	wire signed [64:0]wire_band_second_corrected_at_forty_two; // 延时带通尾段校正供带通尾段余差宽值
	wire signed [63:0]wire_band_second_product_at_thirty_nine; // 延时带通尾段乘积供带通尾段校正
	wire signed [28:0]wire_band_second_residue_at_fifty_four; // 延时带通尾段余差供带通余差尾级
	wire signed [25:0]wire_clip_narrow_at_twenty_five; // 延时阻尼系数有效精度供阻尼阻尼系数乘积
	wire signed [31:0]wire_cutoff_at_fourteen;  // 延时截止频率供带通初段乘积
	wire signed [31:0]wire_cutoff_at_one;       // 延时截止频率供低通初段乘积
	wire signed [31:0]wire_cutoff_at_thirty_six; // 延时截止频率供带通尾段乘积
	wire signed [31:0]wire_cutoff_at_twenty_two; // 延时截止频率供低通尾段乘积
	wire signed [31:0]wire_damping_next_at_fifty_five; // 延时阻尼下拍状态供阻尼
	wire signed [31:0]wire_gain_at_forty_eight; // 延时增益供音频增益乘积
	wire [15:0]wire_generation_at_fifty_five;   // 延时配置代号供配置代号
	wire signed [36:0]wire_high_first_resonance_rounded_at_eleven; // 延时高通初段共振缩放值供高通初段累加
	wire signed [36:0]wire_high_second_resonance_rounded_at_thirty_three; // 延时高通尾段共振缩放值供高通尾段累加
	wire signed [64:0]wire_low_first_corrected_at_five; // 延时低通初段校正供低通初段余差宽值
	wire signed [31:0]wire_low_first_limited_at_twenty_seven; // 延时低通初段安全幅度供低通尾段累加
	wire signed [28:0]wire_low_first_residue_at_twenty_three; // 延时低通初段余差供低通尾段余差输入
	wire signed [31:0]wire_low_recursion_limited_at_fifty_five; // 延时低通回授安全幅度供低通
	wire signed [64:0]wire_low_second_corrected_at_twenty_seven; // 延时低通尾段校正供低通尾段余差宽值
	wire signed [63:0]wire_low_second_product_at_twenty_four; // 延时低通尾段乘积供低通尾段校正
	wire signed [28:0]wire_low_second_residue_at_fifty_four; // 延时低通尾段余差供低通余差尾级
	wire signed [31:0]wire_low_selected_at_thirty_seven; // 延时低通选定幅度供模式中间和
	wire signed [32:0]wire_mode_partial_at_forty_six; // 延时模式中间和供模式选定幅度
	wire signed [31:0]wire_old_band_at_nineteen; // 延时前态带通供带通初段累加
	wire signed [28:0]wire_old_band_residue_at_fifteen; // 延时前态带通余差供带通初段余差输入
	wire signed [31:0]wire_old_damping_at_forty_five; // 延时前态阻尼供带通回授乘积
	wire signed [31:0]wire_old_damping_at_thirty; // 延时前态阻尼供低通回授乘积
	wire signed [31:0]wire_old_low_at_five;     // 延时前态低通供低通初段累加
	wire signed [28:0]wire_old_low_residue_at_two; // 延时前态低通余差供低通初段校正
	wire signed [31:0]wire_resonance_at_one;    // 延时共振供高通初段共振乘积
	wire signed [31:0]wire_resonance_at_twenty_two; // 延时共振供高通尾段共振乘积
	wire signed [31:0]wire_sample_at_eight;     // 延时音频供高通初段残差
	wire signed [31:0]wire_sample_at_thirty;    // 延时音频供高通尾段残差
	wire signed [31:0]wire_sample_output_limited_at_fifty_five; // 延时音频提交安全幅度供音频
	wire [4:0]wire_voice_at_fifty_five;         // 延时声部标签供声部标签

	//-----------------输出信号-----------------//
	//用户接口
	reg valid_o = 1'd0;                         // 事务资格寄存值
	reg [4:0]voice_o = 5'd0;                    // 声部标签寄存值
	reg [15:0]generation_o = 16'd0;             // 配置代号寄存值
	reg signed [31:0]sample_o = 32'd0;          // 音频寄存值
	reg signed [31:0]band_o = 32'd0;            // 带通寄存值
	reg signed [31:0]low_o = 32'd0;             // 低通寄存值
	reg signed [31:0]damping_o = 32'd0;         // 阻尼寄存值
	reg signed [28:0]low_residue_o = 29'd0;     // 低通余差寄存值
	reg signed [28:0]band_residue_o = 29'd0;    // 带通余差寄存值
	reg saturated_o = 1'd0;                     // 饱和状态寄存值
	reg error_o = 1'd0;                         // 模式拒绝寄存值

	//---------------其他信号连线---------------//
	//其他信号连线
	assign flag_band_first_history_at_thirty = flag_band_first_history_waiting[6]; // 低通尾段饱和记忆取带通初段饱和记忆
	assign flag_band_first_overflow_at_thirty = flag_band_first_overflow_waiting[7]; // 带通余差较早区间余数丢弃取带通初段边界故障
	assign flag_band_residue_early_discard_at_thirty_seven = flag_band_residue_early_discard_waiting[5]; // 带通余差生存区间余数丢弃取带通余差较早区间余数丢弃
	assign flag_band_second_history_at_fifty = flag_band_second_history_waiting[3]; // 带通回授饱和记忆取带通尾段饱和记忆
	assign flag_high_first_deviation_history_at_fourteen = flag_high_first_deviation_history_waiting[1]; // 高通初段饱和记忆取高通初段残差饱和记忆
	assign flag_high_first_history_at_twenty_two = flag_high_first_history_waiting[6]; // 带通初段饱和记忆取高通初段饱和记忆
	assign flag_high_second_deviation_history_at_thirty_six = flag_high_second_deviation_history_waiting[1]; // 高通尾段饱和记忆取高通尾段残差饱和记忆
	assign flag_high_second_deviation_overflow_at_thirty_six = flag_high_second_deviation_overflow_waiting[2]; // 带通余差后续区间余数丢弃取高通尾段残差边界故障
	assign flag_high_second_history_at_forty_five = flag_high_second_history_waiting[7]; // 带通尾段饱和记忆取高通尾段饱和记忆
	assign flag_low_first_history_at_eleven = flag_low_first_history_waiting[1]; // 高通初段残差饱和记忆取低通初段饱和记忆
	assign flag_low_recursion_history_at_fifty_three = flag_low_recursion_history_waiting[0]; // 音频提交饱和记忆取低通回授饱和记忆
	assign flag_low_recursion_overflow_at_fifty_one = flag_low_recursion_overflow_waiting[15]; // 低通回授饱和记忆取低通回授边界故障
	assign flag_low_second_history_at_thirty_three = flag_low_second_history_waiting[1]; // 高通尾段残差饱和记忆取低通尾段饱和记忆
	assign flag_mode_band_at_forty_five = flag_mode_band_waiting[43]; // 带通选定幅度取模式带通
	assign flag_mode_high_at_thirty_six = flag_mode_high_waiting[34]; // 高通选定幅度取模式高通
	assign flag_mode_invalid_at_fifty_five = flag_mode_invalid_waiting[52]; // 模式拒绝取模式非法编号
	assign flag_mode_low_at_thirty = flag_mode_low_waiting[28]; // 低通选定幅度取模式低通
	assign flag_sample_output_history_at_fifty_five = flag_sample_output_history_waiting[0]; // 饱和状态取音频提交饱和记忆
	assign flag_saturation_start_at_eight = flag_saturation_start_waiting[6]; // 低通初段饱和记忆取整数饱和事务起点
	assign flag_valid_at_fifty_five = flag_valid_waiting[54]; // 事务资格取事务资格
	assign wire_band_first_corrected_at_nineteen = reg_band_first_corrected_waiting[129:65]; // 带通初段余差宽值取带通初段校正
	assign wire_band_first_limited_at_forty_two = reg_band_first_limited_waiting[639:608]; // 带通尾段累加取带通初段安全幅度
	assign wire_band_first_product_at_sixteen = reg_band_first_product_waiting[63:0]; // 带通初段校正取带通初段乘积
	assign wire_band_first_residue_at_thirty_eight = reg_band_first_residue_waiting[492:464]; // 带通尾段余差输入取带通初段余差
	assign wire_band_recursion_limited_at_fifty_five = reg_band_recursion_limited_waiting[159:128]; // 带通取带通回授安全幅度
	assign wire_band_second_corrected_at_forty_two = reg_band_second_corrected_waiting[129:65]; // 带通尾段余差宽值取带通尾段校正
	assign wire_band_second_product_at_thirty_nine = reg_band_second_product_waiting[127:64]; // 带通尾段校正取带通尾段乘积
	assign wire_band_second_residue_at_fifty_four = reg_band_second_residue_waiting[289:261]; // 带通余差尾级取带通尾段余差
	assign wire_clip_narrow_at_twenty_five = reg_clip_narrow_waiting[623:598]; // 阻尼阻尼系数乘积取阻尼系数有效精度
	assign wire_cutoff_at_fourteen = reg_cutoff_waiting[447:416]; // 带通初段乘积取截止频率
	assign wire_cutoff_at_one = reg_cutoff_waiting[31:0]; // 低通初段乘积取截止频率
	assign wire_cutoff_at_thirty_six = reg_cutoff_waiting[1151:1120]; // 带通尾段乘积取截止频率
	assign wire_cutoff_at_twenty_two = reg_cutoff_waiting[703:672]; // 低通尾段乘积取截止频率
	assign wire_damping_next_at_fifty_five = reg_damping_next_waiting[799:768]; // 阻尼取阻尼下拍状态
	assign wire_gain_at_forty_eight = reg_gain_waiting[1535:1504]; // 音频增益乘积取增益
	assign wire_generation_at_fifty_five = reg_generation_waiting[879:864]; // 配置代号取配置代号
	assign wire_high_first_resonance_rounded_at_eleven = reg_high_first_resonance_rounded_waiting[258:222]; // 高通初段累加取高通初段共振缩放值
	assign wire_high_second_resonance_rounded_at_thirty_three = reg_high_second_resonance_rounded_waiting[295:259]; // 高通尾段累加取高通尾段共振缩放值
	assign wire_low_first_corrected_at_five = reg_low_first_corrected_waiting[129:65]; // 低通初段余差宽值取低通初段校正
	assign wire_low_first_limited_at_twenty_seven = reg_low_first_limited_waiting[607:576]; // 低通尾段累加取低通初段安全幅度
	assign wire_low_first_residue_at_twenty_three = reg_low_first_residue_waiting[463:435]; // 低通尾段余差输入取低通初段余差
	assign wire_low_recursion_limited_at_fifty_five = reg_low_recursion_limited_waiting[639:608]; // 低通取低通回授安全幅度
	assign wire_low_second_corrected_at_twenty_seven = reg_low_second_corrected_waiting[129:65]; // 低通尾段余差宽值取低通尾段校正
	assign wire_low_second_product_at_twenty_four = reg_low_second_product_waiting[63:0]; // 低通尾段校正取低通尾段乘积
	assign wire_low_second_residue_at_fifty_four = reg_low_second_residue_waiting[724:696]; // 低通余差尾级取低通尾段余差
	assign wire_low_selected_at_thirty_seven = reg_low_selected_waiting[191:160]; // 模式中间和取低通选定幅度
	assign wire_mode_partial_at_forty_six = reg_mode_partial_waiting[263:231]; // 模式选定幅度取模式中间和
	assign wire_old_band_at_nineteen = reg_old_band_waiting[575:544]; // 带通初段累加取前态带通
	assign wire_old_band_residue_at_fifteen = reg_old_band_residue_waiting[405:377]; // 带通初段余差输入取前态带通余差
	assign wire_old_damping_at_forty_five = reg_old_damping_waiting[1407:1376]; // 带通回授乘积取前态阻尼
	assign wire_old_damping_at_thirty = reg_old_damping_waiting[927:896]; // 低通回授乘积取前态阻尼
	assign wire_old_low_at_five = reg_old_low_waiting[127:96]; // 低通初段累加取前态低通
	assign wire_old_low_residue_at_two = reg_old_low_residue_waiting[28:0]; // 低通初段校正取前态低通余差
	assign wire_resonance_at_one = reg_resonance_waiting[31:0]; // 高通初段共振乘积取共振
	assign wire_resonance_at_twenty_two = reg_resonance_waiting[703:672]; // 高通尾段共振乘积取共振
	assign wire_sample_at_eight = reg_sample_waiting[255:224]; // 高通初段残差取音频
	assign wire_sample_at_thirty = reg_sample_waiting[959:928]; // 高通尾段残差取音频
	assign wire_sample_output_limited_at_fifty_five = reg_sample_output_limited_waiting[63:32]; // 音频取音频提交安全幅度
	assign wire_voice_at_fifty_five = reg_voice_waiting[274:270]; // 声部标签取声部标签

	//---------------输出信号连线---------------//
	//用户接口
	assign o_valid = valid_o;                   // 完整结果快照具有提交资格对外提供
	assign o_voice = voice_o;                   // 与结果同时输出的声部所有者对外提供
	assign o_generation = generation_o;         // 供提交端检查的参数世代标签对外提供
	assign o_sample = sample_o;                 // 按所选滤波模式完成增益补偿的音频对外提供
	assign o_band = band_o;                     // 下个采样应使用的带通递归幅度对外提供
	assign o_low = low_o;                       // 接续声部低频轨迹的新状态对外提供
	assign o_damping = damping_o;               // 下一次双步积分的非线性衰减系数对外提供
	assign o_low_residue = low_residue_o;       // 低通下一采样带入的小数误差对外提供
	assign o_band_residue = band_residue_o;     // 带通累加可继续保留的乘法余数对外提供
	assign o_saturated = saturated_o;           // 当前事务至少一次发生整数边界钳位对外提供
	assign o_error = error_o;                   // 模式编号无效，外部不得提交本结果对外提供

	//-------------输出信号处理区域-------------//
	//用户接口
	// 事务资格：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			valid_o <= 1'd0;                    // 清除事务资格旧值
		end else begin
			valid_o <= flag_valid_at_fifty_five; // 对齐形成事务资格
		end
	end

	// 声部标签：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			voice_o <= 5'd0;                    // 清除声部标签旧值
		end else begin
			voice_o <= wire_voice_at_fifty_five; // 对齐形成声部标签
		end
	end

	// 配置代号：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			generation_o <= 16'd0;              // 清除配置代号旧值
		end else begin
			generation_o <= wire_generation_at_fifty_five; // 对齐形成配置代号
		end
	end

	// 音频：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			sample_o <= 32'd0;                  // 清除音频旧值
		end else begin
			sample_o <= wire_sample_output_limited_at_fifty_five; // 对齐形成音频
		end
	end

	// 带通：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			band_o <= 32'd0;                    // 清除带通旧值
		end else begin
			band_o <= wire_band_recursion_limited_at_fifty_five; // 对齐形成带通
		end
	end

	// 低通：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			low_o <= 32'd0;                     // 清除低通旧值
		end else begin
			low_o <= wire_low_recursion_limited_at_fifty_five; // 对齐形成低通
		end
	end

	// 阻尼：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			damping_o <= 32'd0;                 // 清除阻尼旧值
		end else begin
			damping_o <= wire_damping_next_at_fifty_five; // 对齐形成阻尼
		end
	end

	// 低通余差：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			low_residue_o <= 29'd0;             // 清除低通余差旧值
		end else begin
			low_residue_o <= reg_low_residue_final; // 对齐形成低通余差
		end
	end

	// 带通余差：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			band_residue_o <= 29'd0;            // 清除带通余差旧值
		end else begin
			band_residue_o <= reg_band_residue_final; // 对齐形成带通余差
		end
	end

	// 饱和状态：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			saturated_o <= 1'd0;                // 清除饱和状态旧值
		end else begin
			saturated_o <= flag_sample_output_history_at_fifty_five; // 对齐形成饱和状态
		end
	end

	// 模式拒绝：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			error_o <= 1'd0;                    // 清除模式拒绝旧值
		end else begin
			error_o <= flag_mode_invalid_at_fifty_five; // 对齐形成模式拒绝
		end
	end

	//-------------主要任务处理区域-------------//
	// 截止频率延后36沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_cutoff_waiting <= 1152'd0;      // 截止频率历史归零
		end else begin
			reg_cutoff_waiting <= {reg_cutoff_waiting[1119:0], i_frequency}; // 推入截止频率最新快照
		end
	end

	// 前态低通余差延后1沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_old_low_residue_waiting <= 29'd0; // 前态低通余差历史归零
		end else begin
			reg_old_low_residue_waiting <= reg_old_low_residue; // 推入前态低通余差最新快照
		end
	end

	// 低通初段校正延后2沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_corrected_waiting <= 130'd0; // 低通初段校正历史归零
		end else begin
			reg_low_first_corrected_waiting <= {reg_low_first_corrected_waiting[64:0], reg_low_first_corrected}; // 推入低通初段校正最新快照
		end
	end

	// 前态低通延后4沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_old_low_waiting <= 128'd0;      // 前态低通历史归零
		end else begin
			reg_old_low_waiting <= {reg_old_low_waiting[95:0], reg_old_low}; // 推入前态低通最新快照
		end
	end

	// 整数饱和事务起点延后7沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_saturation_start_waiting <= 7'd0; // 整数饱和事务起点历史归零
		end else begin
			flag_saturation_start_waiting <= {flag_saturation_start_waiting[5:0], flag_saturation_start}; // 推入整数饱和事务起点最新快照
		end
	end

	// 音频延后30沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_sample_waiting <= 960'd0;       // 音频历史归零
		end else begin
			reg_sample_waiting <= {reg_sample_waiting[927:0], i_sample}; // 推入音频最新快照
		end
	end

	// 低通初段饱和记忆延后2沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_first_history_waiting <= 2'd0; // 低通初段饱和记忆历史归零
		end else begin
			flag_low_first_history_waiting <= {flag_low_first_history_waiting[0:0], flag_low_first_history}; // 推入低通初段饱和记忆最新快照
		end
	end

	// 共振延后22沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_resonance_waiting <= 704'd0;    // 共振历史归零
		end else begin
			reg_resonance_waiting <= {reg_resonance_waiting[671:0], i_resonance}; // 推入共振最新快照
		end
	end

	// 高通初段共振缩放值延后7沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_first_resonance_rounded_waiting <= 259'd0; // 高通初段共振缩放值历史归零
		end else begin
			reg_high_first_resonance_rounded_waiting <= {reg_high_first_resonance_rounded_waiting[221:0], reg_high_first_resonance_rounded}; // 推入高通初段共振缩放值最新快照
		end
	end

	// 高通初段残差饱和记忆延后2沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_first_deviation_history_waiting <= 2'd0; // 高通初段残差饱和记忆历史归零
		end else begin
			flag_high_first_deviation_history_waiting <= {flag_high_first_deviation_history_waiting[0:0], flag_high_first_deviation_history}; // 推入高通初段残差饱和记忆最新快照
		end
	end

	// 前态带通余差延后14沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_old_band_residue_waiting <= 406'd0; // 前态带通余差历史归零
		end else begin
			reg_old_band_residue_waiting <= {reg_old_band_residue_waiting[376:0], reg_old_band_residue}; // 推入前态带通余差最新快照
		end
	end

	// 带通初段乘积延后1沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_product_waiting <= 64'd0; // 带通初段乘积历史归零
		end else begin
			reg_band_first_product_waiting <= reg_band_first_product; // 推入带通初段乘积最新快照
		end
	end

	// 带通初段校正延后2沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_corrected_waiting <= 130'd0; // 带通初段校正历史归零
		end else begin
			reg_band_first_corrected_waiting <= {reg_band_first_corrected_waiting[64:0], reg_band_first_corrected}; // 推入带通初段校正最新快照
		end
	end

	// 前态带通延后18沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_old_band_waiting <= 576'd0;     // 前态带通历史归零
		end else begin
			reg_old_band_waiting <= {reg_old_band_waiting[543:0], reg_old_band}; // 推入前态带通最新快照
		end
	end

	// 高通初段饱和记忆延后7沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_first_history_waiting <= 7'd0; // 高通初段饱和记忆历史归零
		end else begin
			flag_high_first_history_waiting <= {flag_high_first_history_waiting[5:0], flag_high_first_history}; // 推入高通初段饱和记忆最新快照
		end
	end

	// 低通初段余差延后16沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_residue_waiting <= 464'd0; // 低通初段余差历史归零
		end else begin
			reg_low_first_residue_waiting <= {reg_low_first_residue_waiting[434:0], reg_low_first_residue}; // 推入低通初段余差最新快照
		end
	end

	// 低通尾段乘积延后1沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_product_waiting <= 64'd0; // 低通尾段乘积历史归零
		end else begin
			reg_low_second_product_waiting <= reg_low_second_product; // 推入低通尾段乘积最新快照
		end
	end

	// 低通尾段校正延后2沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_corrected_waiting <= 130'd0; // 低通尾段校正历史归零
		end else begin
			reg_low_second_corrected_waiting <= {reg_low_second_corrected_waiting[64:0], reg_low_second_corrected}; // 推入低通尾段校正最新快照
		end
	end

	// 低通初段安全幅度延后19沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_limited_waiting <= 608'd0; // 低通初段安全幅度历史归零
		end else begin
			reg_low_first_limited_waiting <= {reg_low_first_limited_waiting[575:0], reg_low_first_limited}; // 推入低通初段安全幅度最新快照
		end
	end

	// 带通初段饱和记忆延后7沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_first_history_waiting <= 7'd0; // 带通初段饱和记忆历史归零
		end else begin
			flag_band_first_history_waiting <= {flag_band_first_history_waiting[5:0], flag_band_first_history}; // 推入带通初段饱和记忆最新快照
		end
	end

	// 低通尾段饱和记忆延后2沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_second_history_waiting <= 2'd0; // 低通尾段饱和记忆历史归零
		end else begin
			flag_low_second_history_waiting <= {flag_low_second_history_waiting[0:0], flag_low_second_history}; // 推入低通尾段饱和记忆最新快照
		end
	end

	// 高通尾段共振缩放值延后8沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_second_resonance_rounded_waiting <= 296'd0; // 高通尾段共振缩放值历史归零
		end else begin
			reg_high_second_resonance_rounded_waiting <= {reg_high_second_resonance_rounded_waiting[258:0], reg_high_second_resonance_rounded}; // 推入高通尾段共振缩放值最新快照
		end
	end

	// 高通尾段残差饱和记忆延后2沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_second_deviation_history_waiting <= 2'd0; // 高通尾段残差饱和记忆历史归零
		end else begin
			flag_high_second_deviation_history_waiting <= {flag_high_second_deviation_history_waiting[0:0], flag_high_second_deviation_history}; // 推入高通尾段残差饱和记忆最新快照
		end
	end

	// 带通初段边界故障延后8沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_first_overflow_waiting <= 8'd0; // 带通初段边界故障历史归零
		end else begin
			flag_band_first_overflow_waiting <= {flag_band_first_overflow_waiting[6:0], flag_band_first_overflow}; // 推入带通初段边界故障最新快照
		end
	end

	// 高通尾段残差边界故障延后3沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_second_deviation_overflow_waiting <= 3'd0; // 高通尾段残差边界故障历史归零
		end else begin
			flag_high_second_deviation_overflow_waiting <= {flag_high_second_deviation_overflow_waiting[1:0], flag_high_second_deviation_overflow}; // 推入高通尾段残差边界故障最新快照
		end
	end

	// 带通余差较早区间余数丢弃延后6沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_residue_early_discard_waiting <= 6'd0; // 带通余差较早区间余数丢弃历史归零
		end else begin
			flag_band_residue_early_discard_waiting <= {flag_band_residue_early_discard_waiting[4:0], flag_band_residue_early_discard}; // 推入带通余差较早区间余数丢弃最新快照
		end
	end

	// 带通初段余差延后17沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_residue_waiting <= 493'd0; // 带通初段余差历史归零
		end else begin
			reg_band_first_residue_waiting <= {reg_band_first_residue_waiting[463:0], reg_band_first_residue}; // 推入带通初段余差最新快照
		end
	end

	// 带通尾段乘积延后2沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_product_waiting <= 128'd0; // 带通尾段乘积历史归零
		end else begin
			reg_band_second_product_waiting <= {reg_band_second_product_waiting[63:0], reg_band_second_product}; // 推入带通尾段乘积最新快照
		end
	end

	// 带通尾段校正延后2沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_corrected_waiting <= 130'd0; // 带通尾段校正历史归零
		end else begin
			reg_band_second_corrected_waiting <= {reg_band_second_corrected_waiting[64:0], reg_band_second_corrected}; // 推入带通尾段校正最新快照
		end
	end

	// 带通初段安全幅度延后20沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_limited_waiting <= 640'd0; // 带通初段安全幅度历史归零
		end else begin
			reg_band_first_limited_waiting <= {reg_band_first_limited_waiting[607:0], reg_band_first_limited}; // 推入带通初段安全幅度最新快照
		end
	end

	// 高通尾段饱和记忆延后8沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_second_history_waiting <= 8'd0; // 高通尾段饱和记忆历史归零
		end else begin
			flag_high_second_history_waiting <= {flag_high_second_history_waiting[6:0], flag_high_second_history}; // 推入高通尾段饱和记忆最新快照
		end
	end

	// 阻尼系数有效精度延后24沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_clip_narrow_waiting <= 624'd0;  // 阻尼系数有效精度历史归零
		end else begin
			reg_clip_narrow_waiting <= {reg_clip_narrow_waiting[597:0], reg_clip_narrow}; // 推入阻尼系数有效精度最新快照
		end
	end

	// 前态阻尼延后44沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_old_damping_waiting <= 1408'd0; // 前态阻尼历史归零
		end else begin
			reg_old_damping_waiting <= {reg_old_damping_waiting[1375:0], reg_old_damping}; // 推入前态阻尼最新快照
		end
	end

	// 带通尾段饱和记忆延后4沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_second_history_waiting <= 4'd0; // 带通尾段饱和记忆历史归零
		end else begin
			flag_band_second_history_waiting <= {flag_band_second_history_waiting[2:0], flag_band_second_history}; // 推入带通尾段饱和记忆最新快照
		end
	end

	// 低通回授边界故障延后16沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_recursion_overflow_waiting <= 16'd0; // 低通回授边界故障历史归零
		end else begin
			flag_low_recursion_overflow_waiting <= {flag_low_recursion_overflow_waiting[14:0], flag_low_recursion_overflow}; // 推入低通回授边界故障最新快照
		end
	end

	// 模式低通延后29沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_mode_low_waiting <= 29'd0;     // 模式低通历史归零
		end else begin
			flag_mode_low_waiting <= {flag_mode_low_waiting[27:0], flag_mode_low}; // 推入模式低通最新快照
		end
	end

	// 模式高通延后35沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_mode_high_waiting <= 35'd0;    // 模式高通历史归零
		end else begin
			flag_mode_high_waiting <= {flag_mode_high_waiting[33:0], flag_mode_high}; // 推入模式高通最新快照
		end
	end

	// 模式带通延后44沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_mode_band_waiting <= 44'd0;    // 模式带通历史归零
		end else begin
			flag_mode_band_waiting <= {flag_mode_band_waiting[42:0], flag_mode_band}; // 推入模式带通最新快照
		end
	end

	// 低通选定幅度延后6沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_selected_waiting <= 192'd0; // 低通选定幅度历史归零
		end else begin
			reg_low_selected_waiting <= {reg_low_selected_waiting[159:0], reg_low_selected}; // 推入低通选定幅度最新快照
		end
	end

	// 模式中间和延后8沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_mode_partial_waiting <= 264'd0; // 模式中间和历史归零
		end else begin
			reg_mode_partial_waiting <= {reg_mode_partial_waiting[230:0], reg_mode_partial}; // 推入模式中间和最新快照
		end
	end

	// 增益延后48沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_gain_waiting <= 1536'd0;        // 增益历史归零
		end else begin
			reg_gain_waiting <= {reg_gain_waiting[1503:0], i_gain}; // 推入增益最新快照
		end
	end

	// 低通回授饱和记忆延后1沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_recursion_history_waiting <= 1'd0; // 低通回授饱和记忆历史归零
		end else begin
			flag_low_recursion_history_waiting <= flag_low_recursion_history; // 推入低通回授饱和记忆最新快照
		end
	end

	// 低通尾段余差延后25沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_residue_waiting <= 725'd0; // 低通尾段余差历史归零
		end else begin
			reg_low_second_residue_waiting <= {reg_low_second_residue_waiting[695:0], reg_low_second_residue}; // 推入低通尾段余差最新快照
		end
	end

	// 带通尾段余差延后10沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_residue_waiting <= 290'd0; // 带通尾段余差历史归零
		end else begin
			reg_band_second_residue_waiting <= {reg_band_second_residue_waiting[260:0], reg_band_second_residue}; // 推入带通尾段余差最新快照
		end
	end

	// 事务资格延后55沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_valid_waiting <= 55'd0;        // 事务资格历史归零
		end else begin
			flag_valid_waiting <= {flag_valid_waiting[53:0], i_valid}; // 推入事务资格最新快照
		end
	end

	// 声部标签延后55沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_voice_waiting <= 275'd0;        // 声部标签历史归零
		end else begin
			reg_voice_waiting <= {reg_voice_waiting[269:0], i_voice}; // 推入声部标签最新快照
		end
	end

	// 配置代号延后55沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_generation_waiting <= 880'd0;   // 配置代号历史归零
		end else begin
			reg_generation_waiting <= {reg_generation_waiting[863:0], i_generation}; // 推入配置代号最新快照
		end
	end

	// 音频提交安全幅度延后2沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_sample_output_limited_waiting <= 64'd0; // 音频提交安全幅度历史归零
		end else begin
			reg_sample_output_limited_waiting <= {reg_sample_output_limited_waiting[31:0], reg_sample_output_limited}; // 推入音频提交安全幅度最新快照
		end
	end

	// 带通回授安全幅度延后5沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_recursion_limited_waiting <= 160'd0; // 带通回授安全幅度历史归零
		end else begin
			reg_band_recursion_limited_waiting <= {reg_band_recursion_limited_waiting[127:0], reg_band_recursion_limited}; // 推入带通回授安全幅度最新快照
		end
	end

	// 低通回授安全幅度延后20沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_recursion_limited_waiting <= 640'd0; // 低通回授安全幅度历史归零
		end else begin
			reg_low_recursion_limited_waiting <= {reg_low_recursion_limited_waiting[607:0], reg_low_recursion_limited}; // 推入低通回授安全幅度最新快照
		end
	end

	// 阻尼下拍状态延后25沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_damping_next_waiting <= 800'd0; // 阻尼下拍状态历史归零
		end else begin
			reg_damping_next_waiting <= {reg_damping_next_waiting[767:0], reg_damping_next}; // 推入阻尼下拍状态最新快照
		end
	end

	// 音频提交饱和记忆延后1沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_sample_output_history_waiting <= 1'd0; // 音频提交饱和记忆历史归零
		end else begin
			flag_sample_output_history_waiting <= flag_sample_output_history; // 推入音频提交饱和记忆最新快照
		end
	end

	// 模式非法编号延后53沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_mode_invalid_waiting <= 53'd0; // 模式非法编号历史归零
		end else begin
			flag_mode_invalid_waiting <= {flag_mode_invalid_waiting[51:0], flag_mode_invalid}; // 推入模式非法编号最新快照
		end
	end

	// 前态带通：清零选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_old_band <= 32'd0;              // 清除前态带通旧值
		end else begin
			reg_old_band <= i_clear ? 32'd0 : i_band; // 清零选择形成前态带通
		end
	end

	// 前态低通：清零选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_old_low <= 32'd0;               // 清除前态低通旧值
		end else begin
			reg_old_low <= i_clear ? 32'd0 : i_low; // 清零选择形成前态低通
		end
	end

	// 前态阻尼：清零选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_old_damping <= 32'd0;           // 清除前态阻尼旧值
		end else begin
			reg_old_damping <= i_clear ? 32'd0 : i_damping; // 清零选择形成前态阻尼
		end
	end

	// 前态低通余差：清零选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_old_low_residue <= 29'd0;       // 清除前态低通余差旧值
		end else begin
			reg_old_low_residue <= i_clear ? 29'd0 : i_low_residue; // 清零选择形成前态低通余差
		end
	end

	// 前态带通余差：清零选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_old_band_residue <= 29'd0;      // 清除前态带通余差旧值
		end else begin
			reg_old_band_residue <= i_clear ? 29'd0 : i_band_residue; // 清零选择形成前态带通余差
		end
	end

	// 模式低通：译码。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_mode_low <= 1'd0;              // 清除模式低通旧值
		end else begin
			flag_mode_low <= i_mode == 3'b001;  // 译码形成模式低通
		end
	end

	// 模式高通：识别。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_mode_high <= 1'd0;             // 清除模式高通旧值
		end else begin
			flag_mode_high <= i_mode == 3'd4;   // 识别形成模式高通
		end
	end

	// 模式带通：译码。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_mode_band <= 1'd0;             // 清除模式带通旧值
		end else begin
			flag_mode_band <= i_mode == 3'd6;   // 译码形成模式带通
		end
	end

	// 模式非法编号：拒绝。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_mode_invalid <= 1'd0;          // 清除模式非法编号旧值
		end else begin
			flag_mode_invalid <= ~(flag_mode_low | flag_mode_high | flag_mode_band); // 拒绝形成模式非法编号
		end
	end

	// 整数饱和事务起点：清零选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_saturation_start <= 1'd0;      // 清除整数饱和事务起点旧值
		end else begin
			flag_saturation_start <= 1'b0;      // 清零选择形成整数饱和事务起点
		end
	end

	// 低通初段乘积：相乘。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_product <= 64'd0;     // 清除低通初段乘积旧值
		end else begin
			reg_low_first_product <= wire_cutoff_at_one * reg_old_band; // 相乘形成低通初段乘积
		end
	end

	// 低通初段校正：相加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_corrected <= 65'd0;   // 清除低通初段校正旧值
		end else begin
			reg_low_first_corrected <= reg_low_first_product + wire_old_low_residue_at_two; // 相加形成低通初段校正
		end
	end

	// 低通初段舍入偏置：舍入补偿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_biased <= 66'd0;      // 清除低通初段舍入偏置旧值
		end else begin
			reg_low_first_biased <= reg_low_first_corrected + (reg_low_first_corrected[64] ? 32'sh07ffffff : 32'sh08000000); // 舍入补偿形成低通初段舍入偏置
		end
	end

	// 低通初段缩放值：截取整数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_rounded <= 38'd0;     // 清除低通初段缩放值旧值
		end else begin
			reg_low_first_rounded <= reg_low_first_biased[65:28]; // 截取整数形成低通初段缩放值
		end
	end

	// 低通初段余差宽值：恢复余差。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_residue_wide <= 66'd0; // 清除低通初段余差宽值旧值
		end else begin
			reg_low_first_residue_wide <= wire_low_first_corrected_at_five - (reg_low_first_rounded << 5'd28); // 恢复余差形成低通初段余差宽值
		end
	end

	// 低通初段余差：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_residue <= 29'd0;     // 清除低通初段余差旧值
		end else begin
			reg_low_first_residue <= reg_low_first_residue_wide[28:0]; // 对齐形成低通初段余差
		end
	end

	// 低通初段累加：相加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_sum <= 39'd0;         // 清除低通初段累加旧值
		end else begin
			reg_low_first_sum <= wire_old_low_at_five + reg_low_first_rounded; // 相加形成低通初段累加
		end
	end

	// 低通初段正越界：检上界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_first_upper <= 1'd0;       // 清除低通初段正越界旧值
		end else begin
			flag_low_first_upper <= reg_low_first_sum > 39'sb000000001111111111111111111111111111111; // 检上界形成低通初段正越界
		end
	end

	// 低通初段负越界：检下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_first_lower <= 1'd0;       // 清除低通初段负越界旧值
		end else begin
			flag_low_first_lower <= reg_low_first_sum < 39'sb111111110000000000000000000000000000000; // 检下界形成低通初段负越界
		end
	end

	// 低通初段低位候选：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_value <= 32'd0;       // 清除低通初段低位候选旧值
		end else begin
			reg_low_first_value <= reg_low_first_sum[31:0]; // 对齐形成低通初段低位候选
		end
	end

	// 低通初段安全幅度：钳位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_first_limited <= 32'd0;     // 清除低通初段安全幅度旧值
		end else begin
			reg_low_first_limited <= flag_low_first_upper ? 32'sh7fffffff : (flag_low_first_lower ? 32'sh80000000 : reg_low_first_value); // 钳位形成低通初段安全幅度
		end
	end

	// 低通初段边界故障：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_first_overflow <= 1'd0;    // 清除低通初段边界故障旧值
		end else begin
			flag_low_first_overflow <= flag_low_first_upper | flag_low_first_lower; // 并集形成低通初段边界故障
		end
	end

	// 低通初段饱和记忆：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_first_history <= 1'd0;     // 清除低通初段饱和记忆旧值
		end else begin
			flag_low_first_history <= flag_saturation_start_at_eight | flag_low_first_overflow; // 并集形成低通初段饱和记忆
		end
	end

	// 高通初段残差：求差。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_first_deviation <= 33'd0;  // 清除高通初段残差旧值
		end else begin
			reg_high_first_deviation <= wire_sample_at_eight - reg_low_first_limited; // 求差形成高通初段残差
		end
	end

	// 高通初段残差正越界：检上界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_first_deviation_upper <= 1'd0; // 清除高通初段残差正越界旧值
		end else begin
			flag_high_first_deviation_upper <= reg_high_first_deviation > 33'sb001111111111111111111111111111111; // 检上界形成高通初段残差正越界
		end
	end

	// 高通初段残差负越界：检下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_first_deviation_lower <= 1'd0; // 清除高通初段残差负越界旧值
		end else begin
			flag_high_first_deviation_lower <= reg_high_first_deviation < 33'sb110000000000000000000000000000000; // 检下界形成高通初段残差负越界
		end
	end

	// 高通初段残差低位候选：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_first_deviation_value <= 32'd0; // 清除高通初段残差低位候选旧值
		end else begin
			reg_high_first_deviation_value <= reg_high_first_deviation[31:0]; // 对齐形成高通初段残差低位候选
		end
	end

	// 高通初段残差安全幅度：钳位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_first_deviation_limited <= 32'd0; // 清除高通初段残差安全幅度旧值
		end else begin
			reg_high_first_deviation_limited <= flag_high_first_deviation_upper ? 32'sh7fffffff : (flag_high_first_deviation_lower ? 32'sh80000000 : reg_high_first_deviation_value); // 钳位形成高通初段残差安全幅度
		end
	end

	// 高通初段残差边界故障：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_first_deviation_overflow <= 1'd0; // 清除高通初段残差边界故障旧值
		end else begin
			flag_high_first_deviation_overflow <= flag_high_first_deviation_upper | flag_high_first_deviation_lower; // 并集形成高通初段残差边界故障
		end
	end

	// 高通初段残差饱和记忆：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_first_deviation_history <= 1'd0; // 清除高通初段残差饱和记忆旧值
		end else begin
			flag_high_first_deviation_history <= flag_low_first_history_at_eleven | flag_high_first_deviation_overflow; // 并集形成高通初段残差饱和记忆
		end
	end

	// 高通初段共振乘积：相乘。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_first_resonance_product <= 64'd0; // 清除高通初段共振乘积旧值
		end else begin
			reg_high_first_resonance_product <= wire_resonance_at_one * reg_old_band; // 相乘形成高通初段共振乘积
		end
	end

	// 高通初段共振舍入偏置：舍入补偿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_first_resonance_biased <= 65'd0; // 清除高通初段共振舍入偏置旧值
		end else begin
			reg_high_first_resonance_biased <= reg_high_first_resonance_product + (reg_high_first_resonance_product[63] ? 32'sh07ffffff : 32'sh08000000); // 舍入补偿形成高通初段共振舍入偏置
		end
	end

	// 高通初段共振缩放值：截取整数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_first_resonance_rounded <= 37'd0; // 清除高通初段共振缩放值旧值
		end else begin
			reg_high_first_resonance_rounded <= reg_high_first_resonance_biased[64:28]; // 截取整数形成高通初段共振缩放值
		end
	end

	// 高通初段累加：求差。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_first_sum <= 38'd0;        // 清除高通初段累加旧值
		end else begin
			reg_high_first_sum <= reg_high_first_deviation_limited - wire_high_first_resonance_rounded_at_eleven; // 求差形成高通初段累加
		end
	end

	// 高通初段正越界：检上界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_first_upper <= 1'd0;      // 清除高通初段正越界旧值
		end else begin
			flag_high_first_upper <= reg_high_first_sum > 38'sb00000001111111111111111111111111111111; // 检上界形成高通初段正越界
		end
	end

	// 高通初段负越界：检下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_first_lower <= 1'd0;      // 清除高通初段负越界旧值
		end else begin
			flag_high_first_lower <= reg_high_first_sum < 38'sb11111110000000000000000000000000000000; // 检下界形成高通初段负越界
		end
	end

	// 高通初段低位候选：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_first_value <= 32'd0;      // 清除高通初段低位候选旧值
		end else begin
			reg_high_first_value <= reg_high_first_sum[31:0]; // 对齐形成高通初段低位候选
		end
	end

	// 高通初段安全幅度：钳位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_first_limited <= 32'd0;    // 清除高通初段安全幅度旧值
		end else begin
			reg_high_first_limited <= flag_high_first_upper ? 32'sh7fffffff : (flag_high_first_lower ? 32'sh80000000 : reg_high_first_value); // 钳位形成高通初段安全幅度
		end
	end

	// 高通初段边界故障：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_first_overflow <= 1'd0;   // 清除高通初段边界故障旧值
		end else begin
			flag_high_first_overflow <= flag_high_first_upper | flag_high_first_lower; // 并集形成高通初段边界故障
		end
	end

	// 高通初段饱和记忆：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_first_history <= 1'd0;    // 清除高通初段饱和记忆旧值
		end else begin
			flag_high_first_history <= flag_high_first_deviation_history_at_fourteen | flag_high_first_overflow; // 并集形成高通初段饱和记忆
		end
	end

	// 带通初段余差输入：清零选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_residue_input <= 29'd0; // 清除带通初段余差输入旧值
		end else begin
			reg_band_first_residue_input <= flag_high_first_history ? 29'd0 : wire_old_band_residue_at_fifteen; // 清零选择形成带通初段余差输入
		end
	end

	// 带通初段乘积：相乘。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_product <= 64'd0;    // 清除带通初段乘积旧值
		end else begin
			reg_band_first_product <= wire_cutoff_at_fourteen * reg_high_first_limited; // 相乘形成带通初段乘积
		end
	end

	// 带通初段校正：相加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_corrected <= 65'd0;  // 清除带通初段校正旧值
		end else begin
			reg_band_first_corrected <= wire_band_first_product_at_sixteen + reg_band_first_residue_input; // 相加形成带通初段校正
		end
	end

	// 带通初段舍入偏置：舍入补偿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_biased <= 66'd0;     // 清除带通初段舍入偏置旧值
		end else begin
			reg_band_first_biased <= reg_band_first_corrected + (reg_band_first_corrected[64] ? 32'sh07ffffff : 32'sh08000000); // 舍入补偿形成带通初段舍入偏置
		end
	end

	// 带通初段缩放值：截取整数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_rounded <= 38'd0;    // 清除带通初段缩放值旧值
		end else begin
			reg_band_first_rounded <= reg_band_first_biased[65:28]; // 截取整数形成带通初段缩放值
		end
	end

	// 带通初段余差宽值：恢复余差。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_residue_wide <= 66'd0; // 清除带通初段余差宽值旧值
		end else begin
			reg_band_first_residue_wide <= wire_band_first_corrected_at_nineteen - (reg_band_first_rounded << 5'd28); // 恢复余差形成带通初段余差宽值
		end
	end

	// 带通初段余差：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_residue <= 29'd0;    // 清除带通初段余差旧值
		end else begin
			reg_band_first_residue <= reg_band_first_residue_wide[28:0]; // 对齐形成带通初段余差
		end
	end

	// 带通初段累加：相加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_sum <= 39'd0;        // 清除带通初段累加旧值
		end else begin
			reg_band_first_sum <= wire_old_band_at_nineteen + reg_band_first_rounded; // 相加形成带通初段累加
		end
	end

	// 带通初段正越界：检上界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_first_upper <= 1'd0;      // 清除带通初段正越界旧值
		end else begin
			flag_band_first_upper <= reg_band_first_sum > 39'sb000000001111111111111111111111111111111; // 检上界形成带通初段正越界
		end
	end

	// 带通初段负越界：检下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_first_lower <= 1'd0;      // 清除带通初段负越界旧值
		end else begin
			flag_band_first_lower <= reg_band_first_sum < 39'sb111111110000000000000000000000000000000; // 检下界形成带通初段负越界
		end
	end

	// 带通初段低位候选：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_value <= 32'd0;      // 清除带通初段低位候选旧值
		end else begin
			reg_band_first_value <= reg_band_first_sum[31:0]; // 对齐形成带通初段低位候选
		end
	end

	// 带通初段安全幅度：钳位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_first_limited <= 32'd0;    // 清除带通初段安全幅度旧值
		end else begin
			reg_band_first_limited <= flag_band_first_upper ? 32'sh7fffffff : (flag_band_first_lower ? 32'sh80000000 : reg_band_first_value); // 钳位形成带通初段安全幅度
		end
	end

	// 带通初段边界故障：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_first_overflow <= 1'd0;   // 清除带通初段边界故障旧值
		end else begin
			flag_band_first_overflow <= flag_band_first_upper | flag_band_first_lower; // 并集形成带通初段边界故障
		end
	end

	// 带通初段饱和记忆：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_first_history <= 1'd0;    // 清除带通初段饱和记忆旧值
		end else begin
			flag_band_first_history <= flag_high_first_history_at_twenty_two | flag_band_first_overflow; // 并集形成带通初段饱和记忆
		end
	end

	// 低通尾段余差输入：清零选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_residue_input <= 29'd0; // 清除低通尾段余差输入旧值
		end else begin
			reg_low_second_residue_input <= flag_band_first_history ? 29'd0 : wire_low_first_residue_at_twenty_three; // 清零选择形成低通尾段余差输入
		end
	end

	// 低通尾段乘积：相乘。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_product <= 64'd0;    // 清除低通尾段乘积旧值
		end else begin
			reg_low_second_product <= wire_cutoff_at_twenty_two * reg_band_first_limited; // 相乘形成低通尾段乘积
		end
	end

	// 低通尾段校正：相加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_corrected <= 65'd0;  // 清除低通尾段校正旧值
		end else begin
			reg_low_second_corrected <= wire_low_second_product_at_twenty_four + reg_low_second_residue_input; // 相加形成低通尾段校正
		end
	end

	// 低通尾段舍入偏置：舍入补偿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_biased <= 66'd0;     // 清除低通尾段舍入偏置旧值
		end else begin
			reg_low_second_biased <= reg_low_second_corrected + (reg_low_second_corrected[64] ? 32'sh07ffffff : 32'sh08000000); // 舍入补偿形成低通尾段舍入偏置
		end
	end

	// 低通尾段缩放值：截取整数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_rounded <= 38'd0;    // 清除低通尾段缩放值旧值
		end else begin
			reg_low_second_rounded <= reg_low_second_biased[65:28]; // 截取整数形成低通尾段缩放值
		end
	end

	// 低通尾段余差宽值：恢复余差。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_residue_wide <= 66'd0; // 清除低通尾段余差宽值旧值
		end else begin
			reg_low_second_residue_wide <= wire_low_second_corrected_at_twenty_seven - (reg_low_second_rounded << 5'd28); // 恢复余差形成低通尾段余差宽值
		end
	end

	// 低通尾段余差：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_residue <= 29'd0;    // 清除低通尾段余差旧值
		end else begin
			reg_low_second_residue <= reg_low_second_residue_wide[28:0]; // 对齐形成低通尾段余差
		end
	end

	// 低通尾段累加：相加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_sum <= 39'd0;        // 清除低通尾段累加旧值
		end else begin
			reg_low_second_sum <= wire_low_first_limited_at_twenty_seven + reg_low_second_rounded; // 相加形成低通尾段累加
		end
	end

	// 低通尾段正越界：检上界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_second_upper <= 1'd0;      // 清除低通尾段正越界旧值
		end else begin
			flag_low_second_upper <= reg_low_second_sum > 39'sb000000001111111111111111111111111111111; // 检上界形成低通尾段正越界
		end
	end

	// 低通尾段负越界：检下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_second_lower <= 1'd0;      // 清除低通尾段负越界旧值
		end else begin
			flag_low_second_lower <= reg_low_second_sum < 39'sb111111110000000000000000000000000000000; // 检下界形成低通尾段负越界
		end
	end

	// 低通尾段低位候选：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_value <= 32'd0;      // 清除低通尾段低位候选旧值
		end else begin
			reg_low_second_value <= reg_low_second_sum[31:0]; // 对齐形成低通尾段低位候选
		end
	end

	// 低通尾段安全幅度：钳位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_second_limited <= 32'd0;    // 清除低通尾段安全幅度旧值
		end else begin
			reg_low_second_limited <= flag_low_second_upper ? 32'sh7fffffff : (flag_low_second_lower ? 32'sh80000000 : reg_low_second_value); // 钳位形成低通尾段安全幅度
		end
	end

	// 低通尾段边界故障：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_second_overflow <= 1'd0;   // 清除低通尾段边界故障旧值
		end else begin
			flag_low_second_overflow <= flag_low_second_upper | flag_low_second_lower; // 并集形成低通尾段边界故障
		end
	end

	// 低通尾段饱和记忆：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_second_history <= 1'd0;    // 清除低通尾段饱和记忆旧值
		end else begin
			flag_low_second_history <= flag_band_first_history_at_thirty | flag_low_second_overflow; // 并集形成低通尾段饱和记忆
		end
	end

	// 高通尾段残差：求差。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_second_deviation <= 33'd0; // 清除高通尾段残差旧值
		end else begin
			reg_high_second_deviation <= wire_sample_at_thirty - reg_low_second_limited; // 求差形成高通尾段残差
		end
	end

	// 高通尾段残差正越界：检上界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_second_deviation_upper <= 1'd0; // 清除高通尾段残差正越界旧值
		end else begin
			flag_high_second_deviation_upper <= reg_high_second_deviation > 33'sb001111111111111111111111111111111; // 检上界形成高通尾段残差正越界
		end
	end

	// 高通尾段残差负越界：检下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_second_deviation_lower <= 1'd0; // 清除高通尾段残差负越界旧值
		end else begin
			flag_high_second_deviation_lower <= reg_high_second_deviation < 33'sb110000000000000000000000000000000; // 检下界形成高通尾段残差负越界
		end
	end

	// 高通尾段残差低位候选：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_second_deviation_value <= 32'd0; // 清除高通尾段残差低位候选旧值
		end else begin
			reg_high_second_deviation_value <= reg_high_second_deviation[31:0]; // 对齐形成高通尾段残差低位候选
		end
	end

	// 高通尾段残差安全幅度：钳位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_second_deviation_limited <= 32'd0; // 清除高通尾段残差安全幅度旧值
		end else begin
			reg_high_second_deviation_limited <= flag_high_second_deviation_upper ? 32'sh7fffffff : (flag_high_second_deviation_lower ? 32'sh80000000 : reg_high_second_deviation_value); // 钳位形成高通尾段残差安全幅度
		end
	end

	// 高通尾段残差边界故障：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_second_deviation_overflow <= 1'd0; // 清除高通尾段残差边界故障旧值
		end else begin
			flag_high_second_deviation_overflow <= flag_high_second_deviation_upper | flag_high_second_deviation_lower; // 并集形成高通尾段残差边界故障
		end
	end

	// 高通尾段残差饱和记忆：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_second_deviation_history <= 1'd0; // 清除高通尾段残差饱和记忆旧值
		end else begin
			flag_high_second_deviation_history <= flag_low_second_history_at_thirty_three | flag_high_second_deviation_overflow; // 并集形成高通尾段残差饱和记忆
		end
	end

	// 高通尾段共振乘积：相乘。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_second_resonance_product <= 64'd0; // 清除高通尾段共振乘积旧值
		end else begin
			reg_high_second_resonance_product <= wire_resonance_at_twenty_two * reg_band_first_limited; // 相乘形成高通尾段共振乘积
		end
	end

	// 高通尾段共振舍入偏置：舍入补偿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_second_resonance_biased <= 65'd0; // 清除高通尾段共振舍入偏置旧值
		end else begin
			reg_high_second_resonance_biased <= reg_high_second_resonance_product + (reg_high_second_resonance_product[63] ? 32'sh07ffffff : 32'sh08000000); // 舍入补偿形成高通尾段共振舍入偏置
		end
	end

	// 高通尾段共振缩放值：截取整数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_second_resonance_rounded <= 37'd0; // 清除高通尾段共振缩放值旧值
		end else begin
			reg_high_second_resonance_rounded <= reg_high_second_resonance_biased[64:28]; // 截取整数形成高通尾段共振缩放值
		end
	end

	// 高通尾段累加：求差。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_second_sum <= 38'd0;       // 清除高通尾段累加旧值
		end else begin
			reg_high_second_sum <= reg_high_second_deviation_limited - wire_high_second_resonance_rounded_at_thirty_three; // 求差形成高通尾段累加
		end
	end

	// 高通尾段正越界：检上界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_second_upper <= 1'd0;     // 清除高通尾段正越界旧值
		end else begin
			flag_high_second_upper <= reg_high_second_sum > 38'sb00000001111111111111111111111111111111; // 检上界形成高通尾段正越界
		end
	end

	// 高通尾段负越界：检下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_second_lower <= 1'd0;     // 清除高通尾段负越界旧值
		end else begin
			flag_high_second_lower <= reg_high_second_sum < 38'sb11111110000000000000000000000000000000; // 检下界形成高通尾段负越界
		end
	end

	// 高通尾段低位候选：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_second_value <= 32'd0;     // 清除高通尾段低位候选旧值
		end else begin
			reg_high_second_value <= reg_high_second_sum[31:0]; // 对齐形成高通尾段低位候选
		end
	end

	// 高通尾段安全幅度：钳位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_second_limited <= 32'd0;   // 清除高通尾段安全幅度旧值
		end else begin
			reg_high_second_limited <= flag_high_second_upper ? 32'sh7fffffff : (flag_high_second_lower ? 32'sh80000000 : reg_high_second_value); // 钳位形成高通尾段安全幅度
		end
	end

	// 高通尾段边界故障：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_second_overflow <= 1'd0;  // 清除高通尾段边界故障旧值
		end else begin
			flag_high_second_overflow <= flag_high_second_upper | flag_high_second_lower; // 并集形成高通尾段边界故障
		end
	end

	// 高通尾段饱和记忆：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_high_second_history <= 1'd0;   // 清除高通尾段饱和记忆旧值
		end else begin
			flag_high_second_history <= flag_high_second_deviation_history_at_thirty_six | flag_high_second_overflow; // 并集形成高通尾段饱和记忆
		end
	end

	// 带通余差较早区间余数丢弃：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_residue_early_discard <= 1'd0; // 清除带通余差较早区间余数丢弃旧值
		end else begin
			flag_band_residue_early_discard <= flag_band_first_overflow_at_thirty | flag_low_second_overflow; // 并集形成带通余差较早区间余数丢弃
		end
	end

	// 带通余差后续区间余数丢弃：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_residue_late_discard <= 1'd0; // 清除带通余差后续区间余数丢弃旧值
		end else begin
			flag_band_residue_late_discard <= flag_high_second_deviation_overflow_at_thirty_six | flag_high_second_overflow; // 并集形成带通余差后续区间余数丢弃
		end
	end

	// 带通余差生存区间余数丢弃：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_residue_interval_discard <= 1'd0; // 清除带通余差生存区间余数丢弃旧值
		end else begin
			flag_band_residue_interval_discard <= flag_band_residue_early_discard_at_thirty_seven | flag_band_residue_late_discard; // 并集形成带通余差生存区间余数丢弃
		end
	end

	// 带通尾段余差输入：清零选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_residue_input <= 29'd0; // 清除带通尾段余差输入旧值
		end else begin
			reg_band_second_residue_input <= flag_band_residue_interval_discard ? 29'd0 : wire_band_first_residue_at_thirty_eight; // 清零选择形成带通尾段余差输入
		end
	end

	// 带通尾段乘积：相乘。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_product <= 64'd0;   // 清除带通尾段乘积旧值
		end else begin
			reg_band_second_product <= wire_cutoff_at_thirty_six * reg_high_second_limited; // 相乘形成带通尾段乘积
		end
	end

	// 带通尾段校正：相加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_corrected <= 65'd0; // 清除带通尾段校正旧值
		end else begin
			reg_band_second_corrected <= wire_band_second_product_at_thirty_nine + reg_band_second_residue_input; // 相加形成带通尾段校正
		end
	end

	// 带通尾段舍入偏置：舍入补偿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_biased <= 66'd0;    // 清除带通尾段舍入偏置旧值
		end else begin
			reg_band_second_biased <= reg_band_second_corrected + (reg_band_second_corrected[64] ? 32'sh07ffffff : 32'sh08000000); // 舍入补偿形成带通尾段舍入偏置
		end
	end

	// 带通尾段缩放值：截取整数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_rounded <= 38'd0;   // 清除带通尾段缩放值旧值
		end else begin
			reg_band_second_rounded <= reg_band_second_biased[65:28]; // 截取整数形成带通尾段缩放值
		end
	end

	// 带通尾段余差宽值：恢复余差。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_residue_wide <= 66'd0; // 清除带通尾段余差宽值旧值
		end else begin
			reg_band_second_residue_wide <= wire_band_second_corrected_at_forty_two - (reg_band_second_rounded << 5'd28); // 恢复余差形成带通尾段余差宽值
		end
	end

	// 带通尾段余差：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_residue <= 29'd0;   // 清除带通尾段余差旧值
		end else begin
			reg_band_second_residue <= reg_band_second_residue_wide[28:0]; // 对齐形成带通尾段余差
		end
	end

	// 带通尾段累加：相加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_sum <= 39'd0;       // 清除带通尾段累加旧值
		end else begin
			reg_band_second_sum <= wire_band_first_limited_at_forty_two + reg_band_second_rounded; // 相加形成带通尾段累加
		end
	end

	// 带通尾段正越界：检上界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_second_upper <= 1'd0;     // 清除带通尾段正越界旧值
		end else begin
			flag_band_second_upper <= reg_band_second_sum > 39'sb000000001111111111111111111111111111111; // 检上界形成带通尾段正越界
		end
	end

	// 带通尾段负越界：检下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_second_lower <= 1'd0;     // 清除带通尾段负越界旧值
		end else begin
			flag_band_second_lower <= reg_band_second_sum < 39'sb111111110000000000000000000000000000000; // 检下界形成带通尾段负越界
		end
	end

	// 带通尾段低位候选：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_value <= 32'd0;     // 清除带通尾段低位候选旧值
		end else begin
			reg_band_second_value <= reg_band_second_sum[31:0]; // 对齐形成带通尾段低位候选
		end
	end

	// 带通尾段安全幅度：钳位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_second_limited <= 32'd0;   // 清除带通尾段安全幅度旧值
		end else begin
			reg_band_second_limited <= flag_band_second_upper ? 32'sh7fffffff : (flag_band_second_lower ? 32'sh80000000 : reg_band_second_value); // 钳位形成带通尾段安全幅度
		end
	end

	// 带通尾段边界故障：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_second_overflow <= 1'd0;  // 清除带通尾段边界故障旧值
		end else begin
			flag_band_second_overflow <= flag_band_second_upper | flag_band_second_lower; // 并集形成带通尾段边界故障
		end
	end

	// 带通尾段饱和记忆：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_second_history <= 1'd0;   // 清除带通尾段饱和记忆旧值
		end else begin
			flag_band_second_history <= flag_high_second_history_at_forty_five | flag_band_second_overflow; // 并集形成带通尾段饱和记忆
		end
	end

	// 阻尼能量平方乘积：相乘。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_damping_square_product <= 64'd0; // 清除阻尼能量平方乘积旧值
		end else begin
			reg_damping_square_product <= reg_band_first_limited * reg_band_first_limited; // 相乘形成阻尼能量平方乘积
		end
	end

	// 阻尼能量平方舍入偏置：舍入补偿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_damping_square_biased <= 65'd0; // 清除阻尼能量平方舍入偏置旧值
		end else begin
			reg_damping_square_biased <= reg_damping_square_product + (reg_damping_square_product[63] ? 32'sh01ffffff : 32'sh02000000); // 舍入补偿形成阻尼能量平方舍入偏置
		end
	end

	// 阻尼能量平方缩放值：截取整数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_damping_square_rounded <= 39'd0; // 清除阻尼能量平方缩放值旧值
		end else begin
			reg_damping_square_rounded <= reg_damping_square_biased[64:26]; // 截取整数形成阻尼能量平方缩放值
		end
	end

	// 阻尼系数有效精度：精确截位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_clip_narrow <= 26'd0;           // 清除阻尼系数有效精度旧值
		end else begin
			reg_clip_narrow <= i_clip[25:0];    // 精确截位形成阻尼系数有效精度
		end
	end

	// 阻尼阻尼系数乘积：相乘。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_damping_clip_product <= 65'd0;  // 清除阻尼阻尼系数乘积旧值
		end else begin
			reg_damping_clip_product <= wire_clip_narrow_at_twenty_five * reg_damping_square_rounded; // 相乘形成阻尼阻尼系数乘积
		end
	end

	// 阻尼阻尼系数舍入偏置：舍入补偿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_damping_clip_biased <= 66'd0;   // 清除阻尼阻尼系数舍入偏置旧值
		end else begin
			reg_damping_clip_biased <= reg_damping_clip_product + (reg_damping_clip_product[64] ? 32'sh07ffffff : 32'sh08000000); // 舍入补偿形成阻尼阻尼系数舍入偏置
		end
	end

	// 阻尼阻尼系数缩放值：截取整数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_damping_clip_rounded <= 38'd0;  // 清除阻尼阻尼系数缩放值旧值
		end else begin
			reg_damping_clip_rounded <= reg_damping_clip_biased[65:28]; // 截取整数形成阻尼阻尼系数缩放值
		end
	end

	// 阻尼计算候选：单位求差。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_damping_candidate <= 39'd0;     // 清除阻尼计算候选旧值
		end else begin
			reg_damping_candidate <= 28'sh4000000 - reg_damping_clip_rounded; // 单位求差形成阻尼计算候选
		end
	end

	// 阻尼下拍状态：限制下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_damping_next <= 32'd0;          // 清除阻尼下拍状态旧值
		end else begin
			reg_damping_next <= reg_damping_candidate < 39'sb000000000000000011001100110011001100110 ? 32'sh00666666 : reg_damping_candidate[31:0]; // 限制下界形成阻尼下拍状态
		end
	end

	// 带通回授乘积：相乘。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_recursion_product <= 64'd0; // 清除带通回授乘积旧值
		end else begin
			reg_band_recursion_product <= reg_band_second_limited * wire_old_damping_at_forty_five; // 相乘形成带通回授乘积
		end
	end

	// 带通回授舍入偏置：舍入补偿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_recursion_biased <= 65'd0; // 清除带通回授舍入偏置旧值
		end else begin
			reg_band_recursion_biased <= reg_band_recursion_product + (reg_band_recursion_product[63] ? 32'sh01ffffff : 32'sh02000000); // 舍入补偿形成带通回授舍入偏置
		end
	end

	// 带通回授缩放值：截取整数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_recursion_rounded <= 39'd0; // 清除带通回授缩放值旧值
		end else begin
			reg_band_recursion_rounded <= reg_band_recursion_biased[64:26]; // 截取整数形成带通回授缩放值
		end
	end

	// 带通回授正越界：检上界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_recursion_upper <= 1'd0;  // 清除带通回授正越界旧值
		end else begin
			flag_band_recursion_upper <= reg_band_recursion_rounded > 39'sb000000001111111111111111111111111111111; // 检上界形成带通回授正越界
		end
	end

	// 带通回授负越界：检下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_recursion_lower <= 1'd0;  // 清除带通回授负越界旧值
		end else begin
			flag_band_recursion_lower <= reg_band_recursion_rounded < 39'sb111111110000000000000000000000000000000; // 检下界形成带通回授负越界
		end
	end

	// 带通回授低位候选：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_recursion_value <= 32'd0;  // 清除带通回授低位候选旧值
		end else begin
			reg_band_recursion_value <= reg_band_recursion_rounded[31:0]; // 对齐形成带通回授低位候选
		end
	end

	// 带通回授安全幅度：钳位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_recursion_limited <= 32'd0; // 清除带通回授安全幅度旧值
		end else begin
			reg_band_recursion_limited <= flag_band_recursion_upper ? 32'sh7fffffff : (flag_band_recursion_lower ? 32'sh80000000 : reg_band_recursion_value); // 钳位形成带通回授安全幅度
		end
	end

	// 带通回授边界故障：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_recursion_overflow <= 1'd0; // 清除带通回授边界故障旧值
		end else begin
			flag_band_recursion_overflow <= flag_band_recursion_upper | flag_band_recursion_lower; // 并集形成带通回授边界故障
		end
	end

	// 带通回授饱和记忆：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_band_recursion_history <= 1'd0; // 清除带通回授饱和记忆旧值
		end else begin
			flag_band_recursion_history <= flag_band_second_history_at_fifty | flag_band_recursion_overflow; // 并集形成带通回授饱和记忆
		end
	end

	// 低通回授乘积：相乘。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_recursion_product <= 64'd0; // 清除低通回授乘积旧值
		end else begin
			reg_low_recursion_product <= reg_low_second_limited * wire_old_damping_at_thirty; // 相乘形成低通回授乘积
		end
	end

	// 低通回授舍入偏置：舍入补偿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_recursion_biased <= 65'd0;  // 清除低通回授舍入偏置旧值
		end else begin
			reg_low_recursion_biased <= reg_low_recursion_product + (reg_low_recursion_product[63] ? 32'sh01ffffff : 32'sh02000000); // 舍入补偿形成低通回授舍入偏置
		end
	end

	// 低通回授缩放值：截取整数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_recursion_rounded <= 39'd0; // 清除低通回授缩放值旧值
		end else begin
			reg_low_recursion_rounded <= reg_low_recursion_biased[64:26]; // 截取整数形成低通回授缩放值
		end
	end

	// 低通回授正越界：检上界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_recursion_upper <= 1'd0;   // 清除低通回授正越界旧值
		end else begin
			flag_low_recursion_upper <= reg_low_recursion_rounded > 39'sb000000001111111111111111111111111111111; // 检上界形成低通回授正越界
		end
	end

	// 低通回授负越界：检下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_recursion_lower <= 1'd0;   // 清除低通回授负越界旧值
		end else begin
			flag_low_recursion_lower <= reg_low_recursion_rounded < 39'sb111111110000000000000000000000000000000; // 检下界形成低通回授负越界
		end
	end

	// 低通回授低位候选：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_recursion_value <= 32'd0;   // 清除低通回授低位候选旧值
		end else begin
			reg_low_recursion_value <= reg_low_recursion_rounded[31:0]; // 对齐形成低通回授低位候选
		end
	end

	// 低通回授安全幅度：钳位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_recursion_limited <= 32'd0; // 清除低通回授安全幅度旧值
		end else begin
			reg_low_recursion_limited <= flag_low_recursion_upper ? 32'sh7fffffff : (flag_low_recursion_lower ? 32'sh80000000 : reg_low_recursion_value); // 钳位形成低通回授安全幅度
		end
	end

	// 低通回授边界故障：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_recursion_overflow <= 1'd0; // 清除低通回授边界故障旧值
		end else begin
			flag_low_recursion_overflow <= flag_low_recursion_upper | flag_low_recursion_lower; // 并集形成低通回授边界故障
		end
	end

	// 低通回授饱和记忆：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_low_recursion_history <= 1'd0; // 清除低通回授饱和记忆旧值
		end else begin
			flag_low_recursion_history <= flag_band_recursion_history | flag_low_recursion_overflow_at_fifty_one; // 并集形成低通回授饱和记忆
		end
	end

	// 低通选定幅度：屏蔽。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_selected <= 32'd0;          // 清除低通选定幅度旧值
		end else begin
			reg_low_selected <= flag_mode_low_at_thirty ? reg_low_second_limited : 32'd0; // 屏蔽形成低通选定幅度
		end
	end

	// 高通选定幅度：屏蔽。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high_selected <= 32'd0;         // 清除高通选定幅度旧值
		end else begin
			reg_high_selected <= flag_mode_high_at_thirty_six ? reg_high_second_limited : 32'd0; // 屏蔽形成高通选定幅度
		end
	end

	// 带通选定幅度：屏蔽。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_selected <= 32'd0;         // 清除带通选定幅度旧值
		end else begin
			reg_band_selected <= flag_mode_band_at_forty_five ? reg_band_second_limited : 32'd0; // 屏蔽形成带通选定幅度
		end
	end

	// 模式中间和：相加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_mode_partial <= 33'd0;          // 清除模式中间和旧值
		end else begin
			reg_mode_partial <= wire_low_selected_at_thirty_seven + reg_high_selected; // 相加形成模式中间和
		end
	end

	// 模式选定幅度：相加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_mode_selected <= 34'd0;         // 清除模式选定幅度旧值
		end else begin
			reg_mode_selected <= wire_mode_partial_at_forty_six + reg_band_selected; // 相加形成模式选定幅度
		end
	end

	// 模式音频幅度：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_mode_amplitude <= 32'd0;        // 清除模式音频幅度旧值
		end else begin
			reg_mode_amplitude <= reg_mode_selected[31:0]; // 对齐形成模式音频幅度
		end
	end

	// 音频增益乘积：相乘。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_sample_gain_product <= 64'd0;   // 清除音频增益乘积旧值
		end else begin
			reg_sample_gain_product <= wire_gain_at_forty_eight * reg_mode_amplitude; // 相乘形成音频增益乘积
		end
	end

	// 音频增益舍入偏置：舍入补偿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_sample_gain_biased <= 65'd0;    // 清除音频增益舍入偏置旧值
		end else begin
			reg_sample_gain_biased <= reg_sample_gain_product + (reg_sample_gain_product[63] ? 32'sh07ffffff : 32'sh08000000); // 舍入补偿形成音频增益舍入偏置
		end
	end

	// 音频增益缩放值：截取整数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_sample_gain_rounded <= 37'd0;   // 清除音频增益缩放值旧值
		end else begin
			reg_sample_gain_rounded <= reg_sample_gain_biased[64:28]; // 截取整数形成音频增益缩放值
		end
	end

	// 音频提交正越界：检上界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_sample_output_upper <= 1'd0;   // 清除音频提交正越界旧值
		end else begin
			flag_sample_output_upper <= reg_sample_gain_rounded > 37'sb0000001111111111111111111111111111111; // 检上界形成音频提交正越界
		end
	end

	// 音频提交负越界：检下界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_sample_output_lower <= 1'd0;   // 清除音频提交负越界旧值
		end else begin
			flag_sample_output_lower <= reg_sample_gain_rounded < 37'sb1111110000000000000000000000000000000; // 检下界形成音频提交负越界
		end
	end

	// 音频提交低位候选：对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_sample_output_value <= 32'd0;   // 清除音频提交低位候选旧值
		end else begin
			reg_sample_output_value <= reg_sample_gain_rounded[31:0]; // 对齐形成音频提交低位候选
		end
	end

	// 音频提交安全幅度：钳位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_sample_output_limited <= 32'd0; // 清除音频提交安全幅度旧值
		end else begin
			reg_sample_output_limited <= flag_sample_output_upper ? 32'sh7fffffff : (flag_sample_output_lower ? 32'sh80000000 : reg_sample_output_value); // 钳位形成音频提交安全幅度
		end
	end

	// 音频提交边界故障：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_sample_output_overflow <= 1'd0; // 清除音频提交边界故障旧值
		end else begin
			flag_sample_output_overflow <= flag_sample_output_upper | flag_sample_output_lower; // 并集形成音频提交边界故障
		end
	end

	// 音频提交饱和记忆：并集。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_sample_output_history <= 1'd0; // 清除音频提交饱和记忆旧值
		end else begin
			flag_sample_output_history <= flag_low_recursion_history_at_fifty_three | flag_sample_output_overflow; // 并集形成音频提交饱和记忆
		end
	end

	// 低通余差尾级：清零选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_residue_final <= 29'd0;     // 清除低通余差尾级旧值
		end else begin
			reg_low_residue_final <= flag_sample_output_history ? 29'd0 : wire_low_second_residue_at_fifty_four; // 清零选择形成低通余差尾级
		end
	end

	// 带通余差尾级：清零选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_band_residue_final <= 29'd0;    // 清除带通余差尾级旧值
		end else begin
			reg_band_residue_final <= flag_sample_output_history ? 29'd0 : wire_band_second_residue_at_fifty_four; // 清零选择形成带通余差尾级
		end
	end

endmodule
