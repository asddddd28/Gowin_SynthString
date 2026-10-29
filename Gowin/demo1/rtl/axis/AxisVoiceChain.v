`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/27 22:16:40
// Design Name:     AxisVoiceChain
// Module Name:     AxisVoiceChain
// Description:     description/AxisVoiceChain_Design.pdf
// Simulations:     testbench/vivado/2021.1/AxisVoiceChain
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/27 22:16:40
// History:
// Time             Version     Revised by        Contents
// 2026/10/27       V1.0        Codex              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月27日
// 设计名称:        AxisVoiceChain
// 模块名称:        AxisVoiceChain
// 模块说明:        Description/AxisVoiceChain_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/AxisVoiceChain
//
// 参考资料:        None
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年10月27日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月27日   V1.0        Codex              创建文件

module AxisVoiceChain
#(
	parameter C_ADDR_WIDTH = 6                  // 每段独立返回槽的地址宽度
)
(
	//-----------------全局信号-----------------//
	input i_axis_aclk,                          // 整条链路的唯一时钟
	input i_axis_arstn,                         // 清空所有在途计算和返回

	//-------------AXI-Stream总线S--------------//
	//数据通道
	input [351:0]i_s_axis_tdata,                // 320位滤波快照、18位音量、七位力度及保留位
	input [20:0]i_s_axis_tuser,                 // 调度器分配的不可解释事务标识

	//控制通道
	input i_s_axis_tvalid,                      // 当前完整链路请求有效
	output o_s_axis_tready,                     // 滤波段能够接受新任务

	//-------------AXI-Stream总线M--------------//
	//数据通道
	output [191:0]o_m_axis_tdata,               // Q17音频及原位置的新滤波状态和错误标记
	output [20:0]o_m_axis_tuser,                // 最终完成结果的原请求标识

	//控制通道
	input i_m_axis_tready,                      // 状态提交端愿意接收本次返回
	output o_m_axis_tvalid                      // 完整链路返回已就绪
);

	//--------------模块实例化信号--------------//
	//AxisSvfSample--AXI-Stream总线M--数据通道
	wire [191:0]wire_filter_result;             // 滤波返回的音频与154位状态及两位状态码
	wire [45:0]wire_filter_user;                // 原身份和25位音量/力度沿滤波同行

	//AxisVoiceVca--AXI-Stream总线M--数据通道
	wire [31:0]wire_volume_result;              // 完成音量缩放的有符号样值

	//-----------------标志信号-----------------//
	wire flag_filter_valid;                     // 滤波段已完成一个有序请求
	wire flag_filter_ready;                     // 音量段为后继运算预留了位置

	//-----------------输出信号-----------------//
	//AXI-Stream总线S--控制通道
	wire s_axis_tready_o;                       // 滤波入口提供的接纳资格

	//AXI-Stream总线M--数据通道
	wire [176:0]wire_volume_user;               // 原身份加滤波新状态和状态码

	//AXI-Stream总线M--控制通道
	wire m_axis_tvalid_o;                       // 音量出口提供的完整完成标记

	//---------------输出信号连线---------------//
	//AXI-Stream总线S--控制通道
	assign o_s_axis_tready = s_axis_tready_o;   // 向上游传递滤波段可用信用

	//AXI-Stream总线M--数据通道
	assign o_m_axis_tdata = {4'd0, wire_volume_user[155:0], wire_volume_result}; // 保持状态布局，仅替换音频量纲
	assign o_m_axis_tuser = wire_volume_user[176:156]; // 移除内部上下文，恢复外部身份

	//AXI-Stream总线M--控制通道
	assign o_m_axis_tvalid = m_axis_tvalid_o;   // 发布音频与状态共同完成的资格

	//--------------模块实例化区域--------------//
	// 第一段锁定参数，后续输入即使改变也不会影响已接受的任务。
	AxisSvfSample #(
		.C_USER_WIDTH(46),                      // C_USER_WIDTH参数映射为46
		.C_ADDR_WIDTH(C_ADDR_WIDTH)             // C_ADDR_WIDTH参数映射为C_ADDR_WIDTH
	)AxisSvfSample_Inst(
		.i_axis_aclk(i_axis_aclk),              // i_axis_aclk端口连接i_axis_aclk
		.i_axis_arstn(i_axis_arstn),            // i_axis_arstn端口连接i_axis_arstn
		.i_s_axis_tdata(i_s_axis_tdata[319:0]), // i_s_axis_tdata端口连接i_s_axis_tdata[319:0]
		.i_s_axis_tuser({i_s_axis_tuser, i_s_axis_tdata[337:320], i_s_axis_tdata[344:338]}), // 标签后按VCA顺序排列音量与力度
		.i_s_axis_tvalid(i_s_axis_tvalid),      // i_s_axis_tvalid端口连接i_s_axis_tvalid
		.o_s_axis_tready(s_axis_tready_o),      // o_s_axis_tready端口连接s_axis_tready_o
		.o_m_axis_tdata(wire_filter_result),    // o_m_axis_tdata端口连接wire_filter_result
		.o_m_axis_tuser(wire_filter_user),      // o_m_axis_tuser端口连接wire_filter_user
		.o_m_axis_tvalid(flag_filter_valid),    // o_m_axis_tvalid端口连接flag_filter_valid
		.i_m_axis_tready(flag_filter_ready)     // i_m_axis_tready端口连接flag_filter_ready
	);

	// 第二段沿AXIS握手接收，同时将滤波新状态作为同行上下文保存。
	AxisVoiceVca #(
		.C_USER_WIDTH(177),                     // C_USER_WIDTH参数映射为177
		.C_ADDR_WIDTH(C_ADDR_WIDTH)             // C_ADDR_WIDTH参数映射为C_ADDR_WIDTH
	)AxisVoiceVca_Inst(
		.i_axis_aclk(i_axis_aclk),              // i_axis_aclk端口连接i_axis_aclk
		.i_axis_arstn(i_axis_arstn),            // i_axis_arstn端口连接i_axis_arstn
		.i_s_axis_tdata({7'd0, wire_filter_result[31:0], wire_filter_user[24:0]}), // i_s_axis_tdata端口连接{7'd0, wire_filter_result[31:0], wire_filter_user[24:0]}
		.i_s_axis_tuser({wire_filter_user[45:25], wire_filter_result[187:32]}), // i_s_axis_tuser端口连接{wire_filter_user[45:25], wire_filter_result[187:32]}
		.i_s_axis_tvalid(flag_filter_valid),    // i_s_axis_tvalid端口连接flag_filter_valid
		.o_s_axis_tready(flag_filter_ready),    // o_s_axis_tready端口连接flag_filter_ready
		.o_m_axis_tdata(wire_volume_result),    // o_m_axis_tdata端口连接wire_volume_result
		.o_m_axis_tuser(wire_volume_user),      // o_m_axis_tuser端口连接wire_volume_user
		.o_m_axis_tvalid(m_axis_tvalid_o),      // o_m_axis_tvalid端口连接m_axis_tvalid_o
		.i_m_axis_tready(i_m_axis_tready)       // i_m_axis_tready端口连接i_m_axis_tready
	);

endmodule
