`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/13 03:49:42
// Design Name:     SurgeVoiceIngress
// Module Name:     SurgeVoiceIngress
// Description:     description/SurgeVoiceIngress_Design.pdf
// Simulations:     testbench/vivado/2021.1/SurgeVoiceIngress
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/13 03:49:42
// History:
// Time             Version     Revised by        Contents
// 2026/10/13       V1.0        Codex              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月13日
// 设计名称:        SurgeVoiceIngress
// 模块名称:        SurgeVoiceIngress
// 模块说明:        Description/SurgeVoiceIngress_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/SurgeVoiceIngress
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

module SurgeVoiceIngress
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 两组邮箱的捕获时钟
	input i_rstn,                               // 异步清空所有请求

	//-----------------用户接口-----------------//
	input [1:0]i_control,                       // 同拍取消和下游就绪
	input [1:0]i_valid,                         // 低高组分别具有候选包
	input [209:0]i_low_packet,                  // 低组完整音色快照
	input [209:0]i_high_packet,                 // 高组同域参数和音频
	output o_low_ready,                         // 低组邮箱当前空闲
	output o_high_ready,                        // 高组存储可以捕获
	output o_valid,                             // 已保存的交付资格
	output [209:0]o_packet                      // 低组优先的整包选择
);

	//---------------配置参数区域---------------//
	localparam [511:0]MAILBOX_MAP = 512'h00170017001700170017000600170006007700770015001500770066001100000063006300630063007300620073006200630063000100010077006600110000; // 两组资格和已选包的原子真值表

	//----------------寄存器信号----------------//
	reg [209:0]reg_low = 210'd0;                // 低组冻结音色描述符
	reg [209:0]reg_high = 210'd0;               // 高组等待交付的数据

	//-----------------标志信号-----------------//
	reg [2:0]flag_pending = 3'd0;               // 选择低组位及低高组满空资格

	//-----------------其他信号-----------------//
	// 三个同行控制字段的真值槽
	wire [8:0]wire_selector;                    // 三项资格真值表的位偏移

	//-----------------输出信号-----------------//
	//用户接口
	wire low_ready_o;                           // 捕获低组的资格
	wire high_ready_o;                          // 空邮箱开放高组
	wire valid_o;                               // 任意邮箱存在未取消数据
	wire [209:0]packet_o;                       // 同拍已选择的数据包

	//---------------其他信号连线---------------//
	//其他信号连线
	assign low_ready_o = !flag_pending[1] && !i_control[1]; // 满邮箱不在出队沿重填
	assign high_ready_o = !flag_pending[0] && !i_control[1]; // 高组独立反压
	assign valid_o = (flag_pending[1:0] != 2'd0) && !i_control[1]; // 取消不产生交付
	assign packet_o = flag_pending[2] ? reg_low : reg_high; // 已选整包在反压期间不会被新到达请求替换
	assign wire_selector = {flag_pending, i_valid, i_control, 2'b00}; // 每种状态占四位槽且只用三位

	//---------------输出信号连线---------------//
	//用户接口
	assign o_low_ready = low_ready_o;           // 低组必须等待此资格
	assign o_high_ready = high_ready_o;         // 高组按自身就绪握手
	assign o_valid = valid_o;                   // 接收端同时检查ready
	assign o_packet = packet_o;                 // 所有字段保持同行

	//-------------主要任务处理区域-------------//
	// 低组资格独立捕获与出队，整帧取消优先。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_pending <= 3'd0;               // 复位两个邮箱为空
		end else begin
			flag_pending <= MAILBOX_MAP[wire_selector+:3]; // 更新两路满空资格
		end
	end

	// 空邮箱可预装无资格数据，有效包一经捕获不再随输入变化。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low <= 210'd0;                  // 初始低组样值归零
		end else if(!flag_pending[1])begin
			reg_low <= i_low_packet;            // 锁存低组完整参数
		end
	end

	// 高组参数和样本一起保留至接收或取消。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_high <= 210'd0;                 // 取消初始高组数据
		end else if(!flag_pending[0])begin
			reg_high <= i_high_packet;          // 保存高组原子描述符
		end
	end

endmodule
