`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/13 09:56:41
// Design Name:     SurgeVoiceTailTag
// Module Name:     SurgeVoiceTailTag
// Description:     description/SurgeVoiceTailTag_Design.pdf
// Simulations:     testbench/vivado/2021.1/SurgeVoiceTailTag
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/13 09:56:41
// History:
// Time             Version     Revised by        Contents
// 2026/10/13       V1.0        Codex              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月13日
// 设计名称:        SurgeVoiceTailTag
// 模块名称:        SurgeVoiceTailTag
// 模块说明:        Description/SurgeVoiceTailTag_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/SurgeVoiceTailTag
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

module SurgeVoiceTailTag
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 声部音量标签捕获时钟
	input i_rstn,                               // 异步撤销历史参数

	//-----------------用户接口-----------------//
	input [42:0]i_command,                      // 取消捕获与帧号音量力度的原子命令
	input [49:0]i_return,                       // State双份资格帧号音频
	output o_valid,                             // 只有当前快照对应的返回有效
	output [72:0]o_payload                      // 与返回音频同行的幅度参数
);

	//----------------寄存器信号----------------//
	reg [42:0]reg_metadata = 43'b1000000000000000000000000000000000000000000; // 两位所有权编码及完整参数

	//-----------------其他信号-----------------//
	// 帧身份与幅度包
	wire [17:0]wire_identity;                   // 返回双资格和帧号的身份字

	//-----------------输出信号-----------------//
	//用户接口
	wire valid_o;                               // 取消及重新捕获屏蔽旧返回
	wire [72:0]payload_o;                       // 元数据和返回样值拼接

	//---------------其他信号连线---------------//
	//其他信号连线
	assign wire_identity = i_return[49:32];     // 完整身份字段保持原子比较
	assign valid_o = {i_command[42:41], wire_identity} == {2'b00, reg_metadata[42:25]}; // 双份资格阻止无所有者假匹配
	assign payload_o = {reg_metadata[40:25], i_return[31:0], reg_metadata[24:0]}; // 音量不读取活动配置

	//---------------输出信号连线---------------//
	//用户接口
	assign o_valid = valid_o;                   // 上级附加固定声部地址
	assign o_payload = payload_o;               // 发布完整返回快照

	//-------------主要任务处理区域-------------//
	// 新命令在同拍返回之前取得参数所有权。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_metadata <= 43'b1000000000000000000000000000000000000000000; // 建立不可匹配的初始身份
		end else if(i_command[42:41] != 2'b00)begin
			reg_metadata <= i_command[42] ? 43'b1000000000000000000000000000000000000000000 : {2'b11, i_command[40:0]}; // 取消优先否则捕获同行参数
		end
	end

endmodule
