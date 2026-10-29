`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/27 22:16:51
// Design Name:     AxisVoiceVca
// Module Name:     AxisVoiceVca
// Description:     description/AxisVoiceVca_Design.pdf
// Simulations:     testbench/vivado/2021.1/AxisVoiceVca
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/27 22:16:51
// History:
// Time             Version     Revised by        Contents
// 2026/10/27       V1.0        Codex              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月27日
// 设计名称:        AxisVoiceVca
// 模块名称:        AxisVoiceVca
// 模块说明:        Description/AxisVoiceVca_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/AxisVoiceVca
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

module AxisVoiceVca
#(
	parameter C_USER_WIDTH = 21,                // 随数值事务保存的任意身份字段
	parameter C_ADDR_WIDTH = 6                  // 包括计算中任务的返回容量地址宽度
)
(
	//-----------------全局信号-----------------//
	input i_axis_aclk,                          // 统一的音频计算时钟
	input i_axis_arstn,                         // 同时复位适配器和音量流水

	//-------------AXI-Stream总线S--------------//
	//数据通道
	input [63:0]i_s_axis_tdata,                 // 保留七位、Q26样值、Q18音量、七位力度
	input [C_USER_WIDTH - 1:0]i_s_axis_tuser,   // 返回时原样携带的任务身份

	//控制通道
	input i_s_axis_tvalid,                      // 源端声明完整音量快照
	output o_s_axis_tready,                     // 适配器已经为返回腾出位置

	//-------------AXI-Stream总线M--------------//
	//数据通道
	output [31:0]o_m_axis_tdata,                // 向负无穷取整后的有符号Q17样值
	output [C_USER_WIDTH - 1:0]o_m_axis_tuser,  // 与缩放结果绑定的原始标签

	//控制通道
	input i_m_axis_tready,                      // 下游本拍消费缩放结果
	output o_m_axis_tvalid                      // 已完成缩放结果可以被接收
);

	//--------------模块实例化信号--------------//
	//AxisFixedCore--CORE接口
	wire [63:0]wire_snapshot;                   // 仅在发射时有意义的完整任务字

	//SurgeVoiceVca--用户接口
	wire [52:0]wire_result;                     // 原核心返回的零标签及缩放数值

	//-----------------标志信号-----------------//
	wire flag_launch;                           // 返回槽预留成功后的发射资格
	wire flag_return;                           // 原核心产生有效数值的单拍标记

	//-----------------输出信号-----------------//
	//AXI-Stream总线S--控制通道
	wire s_axis_tready_o;                       // 音量计算的信用接纳状态

	//AXI-Stream总线M--数据通道
	wire [31:0]m_axis_tdata_o;                  // 返回队首的缩放音频
	wire [C_USER_WIDTH - 1:0]m_axis_tuser_o;    // 返回槽保留的调用身份

	//AXI-Stream总线M--控制通道
	wire m_axis_tvalid_o;                       // 可被消费的音量结果资格

	//---------------输出信号连线---------------//
	//AXI-Stream总线S--控制通道
	assign o_s_axis_tready = s_axis_tready_o;   // 反馈能够预留的返回位置

	//AXI-Stream总线M--数据通道
	assign o_m_axis_tdata = m_axis_tdata_o;     // 将Q17样值交给后继模块
	assign o_m_axis_tuser = m_axis_tuser_o;     // 原样恢复对应任务标签

	//AXI-Stream总线M--控制通道
	assign o_m_axis_tvalid = m_axis_tvalid_o;   // 只有队首完成才声明有效

	//--------------模块实例化区域--------------//
	// 信用适配器持有身份，避免扩宽原算术核心的标签流水。
	AxisFixedCore #(
		.C_INPUT_WIDTH(64),                     // C_INPUT_WIDTH参数映射为64
		.C_OUTPUT_WIDTH(32),                    // C_OUTPUT_WIDTH参数映射为32
		.C_USER_WIDTH(C_USER_WIDTH),            // C_USER_WIDTH参数映射为C_USER_WIDTH
		.C_ADDR_WIDTH(C_ADDR_WIDTH)             // C_ADDR_WIDTH参数映射为C_ADDR_WIDTH
	)AxisFixedCore_Inst(
		.i_axis_aclk(i_axis_aclk),              // i_axis_aclk端口连接i_axis_aclk
		.i_axis_arstn(i_axis_arstn),            // i_axis_arstn端口连接i_axis_arstn
		.i_s_axis_tdata(i_s_axis_tdata),        // i_s_axis_tdata端口连接i_s_axis_tdata
		.i_s_axis_tuser(i_s_axis_tuser),        // i_s_axis_tuser端口连接i_s_axis_tuser
		.i_s_axis_tvalid(i_s_axis_tvalid),      // i_s_axis_tvalid端口连接i_s_axis_tvalid
		.o_s_axis_tready(s_axis_tready_o),      // o_s_axis_tready端口连接s_axis_tready_o
		.o_m_axis_tdata(m_axis_tdata_o),        // o_m_axis_tdata端口连接m_axis_tdata_o
		.o_m_axis_tuser(m_axis_tuser_o),        // o_m_axis_tuser端口连接m_axis_tuser_o
		.o_m_axis_tvalid(m_axis_tvalid_o),      // o_m_axis_tvalid端口连接m_axis_tvalid_o
		.i_m_axis_tready(i_m_axis_tready),      // i_m_axis_tready端口连接i_m_axis_tready
		.o_core_valid(flag_launch),             // o_core_valid端口连接flag_launch
		.o_core_data(wire_snapshot),            // o_core_data端口连接wire_snapshot
		.i_core_valid(flag_return),             // i_core_valid端口连接flag_return
		.i_core_data(wire_result[31:0])         // i_core_data端口连接wire_result[31:0]
	);

	// 旧量化和乘法位宽保持原样，不把活动参数接到返回路径。
	SurgeVoiceVca SurgeVoiceVca_Inst(
		.i_clk(i_axis_aclk),                    // i_clk端口连接i_axis_aclk
		.i_rstn(i_axis_arstn),                  // i_rstn端口连接i_axis_arstn
		.i_control({1'b0, flag_launch}),        // i_control端口连接{1'b0, flag_launch}
		.i_payload({21'd0, wire_snapshot[56:0]}), // i_payload端口连接{21'd0, wire_snapshot[56:0]}
		.o_valid(flag_return),                  // o_valid端口连接flag_return
		.o_payload(wire_result)                 // o_payload端口连接wire_result
	);

endmodule
