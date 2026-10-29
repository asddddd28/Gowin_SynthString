`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/13 03:49:42
// Design Name:     WavetableFrameGuard
// Module Name:     WavetableFrameGuard
// Description:     description/WavetableFrameGuard_Design.pdf
// Simulations:     testbench/vivado/2021.1/WavetableFrameGuard
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
// 设计名称:        WavetableFrameGuard
// 模块名称:        WavetableFrameGuard
// 模块说明:        Description/WavetableFrameGuard_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/WavetableFrameGuard
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

module WavetableFrameGuard
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 同域帧管理时钟
	input i_rstn,                               // 清除全部帧资格

	//-----------------用户接口-----------------//
	input [1:0]i_control,                       // 取消位和启动申请
	input [1:0]i_status,                        // 退役和遍历完成的同拍资格
	output o_start,                             // 空闲时的启动握手
	output o_run,                               // 持续遍历授权
	output o_abort,                             // 同拍撤销阶段资格
	output [1:0]o_qualification,                // 帧占用与遍历的原子状态
	output [15:0]o_epoch,                       // 模十六位帧标签
	output o_fault                              // 重复启动提示
);

	//---------------配置参数区域---------------//
	localparam [127:0]LIFECYCLE_MAP = 128'h00000b0b00000a0a0000ff010000ff00; // 三个原子字段决定两项生命期资格

	//-----------------其他信号-----------------//
	// 标签扩展加法
	wire [16:0]wire_successor;                  // 帧标签加一保留进位

	//-----------------输出信号-----------------//
	//用户接口
	wire start_o;                               // 本拍接受的空闲申请
	wire run_o;                                 // 取消同时掩蔽运行
	reg [1:0]qualification_o = 2'd0;            // 高位占用低位遍历的并行标志
	reg [15:0]epoch_o = 16'd0;                  // 已接受帧的代号
	reg fault_o = 1'b0;                         // 忙时错误请求的脉冲

	//---------------其他信号连线---------------//
	//其他信号连线
	assign start_o = {qualification_o[1], i_control} == 3'b001; // 取消和忙时均拒绝启动
	assign run_o = qualification_o[0] && !i_control[1]; // 在取消沿之前关闭阶段执行
	assign wire_successor = epoch_o + 1'b1;     // 扩展宽度后再取低位

	//---------------输出信号连线---------------//
	//用户接口
	assign o_start = start_o;                   // 外部阶段器采用此握手
	assign o_run = run_o;                       // 完成后不会计数回绕重启
	assign o_abort = i_control[1];              // 帧取消直接到达阶段端
	assign o_qualification = qualification_o;   // 所有返回完成前高位仍保持占用
	assign o_epoch = epoch_o;                   // 提供同行代号
	assign o_fault = fault_o;                   // 通知被拒绝的忙时申请

	//-------------输出信号处理区域-------------//
	//用户接口
	// 整帧生命期涵盖遍历及后续滤波。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			qualification_o <= 2'd0;            // 清除整帧授权
		end else begin
			qualification_o <= LIFECYCLE_MAP[{qualification_o,i_control,i_status,1'b0}+:2]; // 保存占用及遍历标志
		end
	end

	// 只有真正启动才能推进帧标签。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			epoch_o <= 16'd0;                   // 帧标签从零开始
		end else begin
			epoch_o <= start_o ? wire_successor[15:0] : epoch_o; // 推进已接受帧代号
		end
	end

	// 忙时的启动冲突不打断当前音频。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			fault_o <= 1'b0;                    // 撤销冲突通知
		end else begin
			fault_o <= {qualification_o[1], i_control} == 3'b101; // 记录忙时启动冲突
		end
	end

endmodule
