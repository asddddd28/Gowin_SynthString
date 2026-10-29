`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/27 22:16:40
// Design Name:     AxisSvfSample
// Module Name:     AxisSvfSample
// Description:     description/AxisSvfSample_Design.pdf
// Simulations:     testbench/vivado/2021.1/AxisSvfSample
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
// 设计名称:        AxisSvfSample
// 模块名称:        AxisSvfSample
// 模块说明:        Description/AxisSvfSample_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/AxisSvfSample
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

module AxisSvfSample
#(
	parameter C_USER_WIDTH = 21,                // 发射者携带的完整事务身份
	parameter C_ADDR_WIDTH = 6                  // 为长滤波流水保留的信用地址位数
)
(
	//-----------------全局信号-----------------//
	input i_axis_aclk,                          // 适配器和SVF使用同一计算时钟
	input i_axis_arstn,                         // 一起清除SVF流水及全部返回资格

	//-------------AXI-Stream总线S--------------//
	//数据通道
	input [319:0]i_s_axis_tdata,                // 音频、旧状态、四系数、模式及清状态标记
	input [C_USER_WIDTH - 1:0]i_s_axis_tuser,   // 本次调用的拥有者和附带上下文

	//控制通道
	input i_s_axis_tvalid,                      // 源端持有完整滤波事务
	output o_s_axis_tready,                     // 有足够空间容纳未来返回

	//-------------AXI-Stream总线M--------------//
	//数据通道
	output [191:0]o_m_axis_tdata,               // Q26音频、新状态、饱和标记和模式错误
	output [C_USER_WIDTH - 1:0]o_m_axis_tuser,  // 本次结果对应的原调用身份

	//控制通道
	input i_m_axis_tready,                      // 后继处理接收当前滤波结果
	output o_m_axis_tvalid                      // 队首滤波结果已经完成
);

	//--------------模块实例化信号--------------//
	//AxisFixedCore--CORE接口
	wire [319:0]wire_snapshot;                  // 发射沿送入SVF的完整快照

	//-----------------标志信号-----------------//
	wire flag_launch;                           // 信用预留后允许核心开始计算
	wire flag_return;                           // 固定流水末级的完成资格

	//-----------------其他信号-----------------//
	wire [191:0]wire_result;                    // 核心返回的有序计算字段

	//-----------------输出信号-----------------//
	//AXI-Stream总线S--控制通道
	wire s_axis_tready_o;                       // 滤波信用环提供的接纳状态

	//AXI-Stream总线M--数据通道
	wire [191:0]m_axis_tdata_o;                 // 包含新递归状态的滤波整包返回
	wire [C_USER_WIDTH - 1:0]m_axis_tuser_o;    // 队首任务的原始所有权

	//AXI-Stream总线M--控制通道
	wire m_axis_tvalid_o;                       // 可见队首已经完成数值计算

	//---------------其他信号连线---------------//
	//其他信号连线
	assign wire_result[191:188] = 4'd0;         // 返回保留位始终为零

	//---------------输出信号连线---------------//
	//AXI-Stream总线S--控制通道
	assign o_s_axis_tready = s_axis_tready_o;   // 有预留空间时接收完整滤波快照

	//AXI-Stream总线M--数据通道
	assign o_m_axis_tdata = m_axis_tdata_o;     // 把计算后的状态和音频一起交付
	assign o_m_axis_tuser = m_axis_tuser_o;     // 输出发射时保存的上下文

	//AXI-Stream总线M--控制通道
	assign o_m_axis_tvalid = m_axis_tvalid_o;   // 通知后继模块可接收结果

	//--------------模块实例化区域--------------//
	// 每个发射占用返回槽，因此固定流水无需支持内部暂停。
	AxisFixedCore #(
		.C_INPUT_WIDTH(320),                    // C_INPUT_WIDTH参数映射为320
		.C_OUTPUT_WIDTH(192),                   // C_OUTPUT_WIDTH参数映射为192
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
		.i_core_data(wire_result)               // i_core_data端口连接wire_result
	);

	// 原SVF实现负责数值，状态所有权留给流外的调度层。
	SurgeSvfSample SurgeSvfSample_Inst(
		.i_clk(i_axis_aclk),                    // i_clk端口连接i_axis_aclk
		.i_rstn(i_axis_arstn),                  // i_rstn端口连接i_axis_arstn
		.i_valid(flag_launch),                  // i_valid端口连接flag_launch
		.i_voice(5'd0),                         // i_voice端口连接5'd0
		.i_generation(16'd0),                   // i_generation端口连接16'd0
		.i_sample(wire_snapshot[31:0]),         // i_sample端口连接wire_snapshot[31:0]
		.i_band(wire_snapshot[63:32]),          // i_band端口连接wire_snapshot[63:32]
		.i_low(wire_snapshot[95:64]),           // i_low端口连接wire_snapshot[95:64]
		.i_damping(wire_snapshot[127:96]),      // i_damping端口连接wire_snapshot[127:96]
		.i_low_residue(wire_snapshot[156:128]), // i_low_residue端口连接wire_snapshot[156:128]
		.i_band_residue(wire_snapshot[185:157]), // i_band_residue端口连接wire_snapshot[185:157]
		.i_frequency(wire_snapshot[217:186]),   // i_frequency端口连接wire_snapshot[217:186]
		.i_resonance(wire_snapshot[249:218]),   // i_resonance端口连接wire_snapshot[249:218]
		.i_clip(wire_snapshot[281:250]),        // i_clip端口连接wire_snapshot[281:250]
		.i_gain(wire_snapshot[313:282]),        // i_gain端口连接wire_snapshot[313:282]
		.i_mode(wire_snapshot[316:314]),        // i_mode端口连接wire_snapshot[316:314]
		.i_clear(wire_snapshot[317]),           // i_clear端口连接wire_snapshot[317]
		.o_valid(flag_return),                  // o_valid端口连接flag_return
		.o_voice(),                             // o_voice端口预留连接
		.o_generation(),                        // o_generation端口预留连接
		.o_sample(wire_result[31:0]),           // o_sample端口连接wire_result[31:0]
		.o_band(wire_result[63:32]),            // o_band端口连接wire_result[63:32]
		.o_low(wire_result[95:64]),             // o_low端口连接wire_result[95:64]
		.o_damping(wire_result[127:96]),        // o_damping端口连接wire_result[127:96]
		.o_low_residue(wire_result[156:128]),   // o_low_residue端口连接wire_result[156:128]
		.o_band_residue(wire_result[185:157]),  // o_band_residue端口连接wire_result[185:157]
		.o_saturated(wire_result[186]),         // o_saturated端口连接wire_result[186]
		.o_error(wire_result[187])              // o_error端口连接wire_result[187]
	);

endmodule
