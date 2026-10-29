`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/13 00:20:28
// Design Name:     WavetableVoiceSchedule
// Module Name:     WavetableVoiceSchedule
// Description:     description/WavetableVoiceSchedule_Design.pdf
// Simulations:     testbench/vivado/2021.1/WavetableVoiceSchedule
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/13 00:20:28
// History:
// Time             Version     Revised by        Contents
// 2026/10/13       V1.0        Codex              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月13日
// 设计名称:        WavetableVoiceSchedule
// 模块名称:        WavetableVoiceSchedule
// 模块说明:        Description/WavetableVoiceSchedule_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/WavetableVoiceSchedule
//
// 参考资料:        None
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年10月13日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月13日   V1.0        Codex              创建文件

module WavetableVoiceSchedule
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 计算时钟,
	input i_rstn,                               // 异步低有效复位,

	//-----------------用户接口-----------------//
	input i_start,                              // 重启十六槽阶段计数,
	input i_run,                                // 帧控制端授予运行资格,
	input i_abort,                              // 本拍撤销输出资格,
	output [5:0]o_stage,                        // 供数据通路译码的计算阶段,
	output [3:0]o_voice,                        // 当前组内声部地址,
	output o_busy,                              // 本拍可以执行阶段,
	output o_complete                           // 最后槽提交阶段的通知
);

	//---------------配置参数区域---------------//
	localparam [149:0]STAGE_MAP = 150'b001010001001001000010101000111000110100001100000011100011011011010011001011000010100010011010010011110011101010111010110010001010000001111000101000100; // 二十五个阶段按计数排列

	//-----------------计数信号-----------------//
	reg [8:0]cnt_cycle = 9'd0;                  // 从本轮启动开始的时钟位置

	//-----------------其他信号-----------------//
	// 遍历计数及组内计算阶段
	wire [9:0]wire_successor;                   // 扩展一位的计数加一
	wire [8:0]wire_quotient;                    // 四百拍内除二十五得到槽号
	wire [8:0]wire_remainder;                   // 每槽内的二十五拍位置

	//-----------------输出信号-----------------//
	//用户接口
	wire [5:0]stage_o;                          // 阶段表中的计算编号
	wire [3:0]voice_o;                          // 本组的声部槽地址
	wire busy_o;                                // 运行区间和上级资格同时有效
	wire complete_o;                            // 最后声部的累加阶段

	//---------------其他信号连线---------------//
	//其他信号连线
	assign wire_successor = cnt_cycle + 1'b1;   // 时钟计数保留进位
	assign wire_quotient = cnt_cycle / 5'd25;   // 固定长度声部划分
	assign wire_remainder = cnt_cycle % 5'd25;  // 取组内阶段位置
	assign stage_o = STAGE_MAP[wire_remainder * 3'd6 +: 6]; // 查出当前算术步骤
	assign voice_o = wire_quotient[3:0];        // 组地址仅运行时有效
	assign busy_o = ({i_run, i_abort} == 2'b10) && (cnt_cycle < 9'd400); // 放行四百拍遍历区间
	assign complete_o = ({i_run, i_abort} == 2'b10) && (cnt_cycle == 9'd399); // 最后累加拍形成通知

	//---------------输出信号连线---------------//
	//用户接口
	assign o_stage = stage_o;                   // 提供查表和乘加译码
	assign o_voice = voice_o;                   // 提供组内快照读地址
	assign o_busy = busy_o;                     // 数据通路采用本拍资格
	assign o_complete = complete_o;             // 帧控制据此结束遍历

	//-------------主要任务处理区域-------------//
	// 启动只重建时间原点，运行和取消资格由调用端负责。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			cnt_cycle <= 9'd0;                  // 清除时间坐标
		end else if(i_start == 1'b1)begin
			cnt_cycle <= 9'd0;                  // 下一拍开始首槽装载
		end else begin
			cnt_cycle <= wire_successor[8:0];   // 连续走时允许自然回绕
		end
	end

endmodule
