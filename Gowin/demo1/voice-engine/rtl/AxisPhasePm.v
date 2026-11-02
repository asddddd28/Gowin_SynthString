`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         SynthString project
// Engineer:        Codex
//
// Create Date:     2026/11/02 00:00:00
// Design Name:     AxisPhasePm
// Module Name:     AxisPhasePm
// Description:     description/AxisPhasePm_Design.pdf
// Simulations:     testbench/vivado/2021.1/AxisPhasePm
//
// Referrences:
// File Format      File Name
// 1.Book           spec/rtl/AxisPhasePm_spec.md
//
// Dependencies:
// Module Name      Version
// 无外部计算模块
//
// Version:         V1.0
// Revision Date:   2026/11/02 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/11/02       V1.0        Codex              Create operator.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        SynthString project
// 开发人员:        Codex
//
// 创建日期:        2026年11月02日
// 设计名称:        AxisPhasePm
// 模块名称:        AxisPhasePm
// 模块说明:        Description/AxisPhasePm_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/AxisPhasePm
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           spec/rtl/AxisPhasePm_spec.md
//
// 依赖文件:
// 模块名称         版本
// 无外部计算模块
//
// 当前版本:        V1.0
// 修订日期:        2026年11月02日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年11月02日   V1.0        Codex              创建算子

module AxisPhasePm
(
	//-----------------全局信号-----------------//
	input i_axis_aclk,                          // 算术与事务资格的共用时钟
	input i_axis_arstn,                         // 低有效复位取消全部在途结果

	//-------------AXI-Stream总线S--------------//
	//数据通道
	input [127:0]i_s_axis_tdata,                // 发射沿锁定操作数及调用者状态
	input [31:0]i_s_axis_tuser,                 // 不参与算术的事务标识

	//控制通道
	input i_s_axis_tvalid,                      // 等待接纳的完整输入资格
	output o_s_axis_tready,                     // 输出可推进时准许新输入

	//-------------AXI-Stream总线M--------------//
	//数据通道
	output [63:0]o_m_axis_tdata,                // 计算结果与需要回写的状态
	output [31:0]o_m_axis_tuser,                // 原请求标识随数值一同返回

	//控制通道
	input i_m_axis_tready,                      // 下游愿意消费输出寄存器
	output o_m_axis_tvalid                      // 队尾已经产生可交付结果
);

	//----------------寄存器信号----------------//
	// 算术阶段之间保存的独立快照
	reg signed [63:0]reg_product = 64'd0;       // 调制音频乘相位深度的完整补码积
	reg [31:0]reg_accumulator = 32'd0;          // 只包含基础频率的下一相位
	reg [31:0]reg_phase_delayed = 32'd0;        // 等待调制量缩放的积分状态
	reg [31:0]reg_offset = 32'd0;               // Q26 去小数后模三十二位的查表偏移

	// 事务身份经过与算术相同的停顿边界
	reg [31:0]reg_user_first = 32'd0;           // 首次接纳的调用者编号
	reg [31:0]reg_user_second = 32'd0;          // 第二计算沿对应的编号

	//-----------------标志信号-----------------//
	// 有效位与整体前进许可
	reg [1:0]flag_pipeline = 2'd0;              // 结果寄存之前各计算级的有效资格
	wire flag_advance;                          // 输出为空或被消费时整体推进

	//-----------------输出信号-----------------//
	//AXI-Stream总线S--控制通道
	wire s_axis_tready_o;                       // 复位抑制后的入口接纳能力

	//AXI-Stream总线M--数据通道
	// 数据与标签的输出寄存边界
	reg [63:0]m_axis_tdata_o = 64'd0;           // 被反压时保持完整返回字
	reg [31:0]m_axis_tuser_o = 32'd0;           // 与返回字绑定的事务归属

	//AXI-Stream总线M--控制通道
	reg m_axis_tvalid_o = 1'd0;                 // 复位后不发布任何旧任务

	//---------------其他信号连线---------------//
	//其他信号连线
	// 单个算子的停顿传播
	assign flag_advance = !m_axis_tvalid_o || i_m_axis_tready; // 队尾未占用或即将腾出时允许移位
	assign s_axis_tready_o = i_axis_arstn && flag_advance; // 清零期间不接收新快照

	//---------------输出信号连线---------------//
	//AXI-Stream总线S--控制通道
	// AXIS 结果和资格桥接
	assign o_s_axis_tready = s_axis_tready_o;   // 将接纳条件交付源端

	//AXI-Stream总线M--数据通道
	assign o_m_axis_tdata = m_axis_tdata_o;     // 数值和状态通过寄存边界输出
	assign o_m_axis_tuser = m_axis_tuser_o;     // 下游用原标识定位状态所有者

	//AXI-Stream总线M--控制通道
	assign o_m_axis_tvalid = m_axis_tvalid_o;   // 只有同行资格有效时结果可读

	//-------------输出信号处理区域-------------//
	//AXI-Stream总线M--控制通道
	// 复位后不发布任何旧任务。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tvalid_o <= 1'b0;            // 撤销输出事务的消费资格
		end else if(flag_advance == 1'b1)begin
			m_axis_tvalid_o <= flag_pipeline[1]; // 最末算术资格转为输出有效
		end
	end

	//AXI-Stream总线M--数据通道
	// 与返回字绑定的事务归属。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tuser_o <= 32'd0;            // 初始化对外编号
		end else if(flag_advance == 1'b1)begin
			m_axis_tuser_o <= reg_user_second;  // 提交与结果相同流水深度的编号
		end
	end

	// 被反压时保持完整返回字。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tdata_o <= 64'd0;            // 清除对外相位结果
		end else if(flag_advance == 1'b1)begin
			m_axis_tdata_o <= {reg_phase_delayed + reg_offset, reg_phase_delayed}; // 同时返回查表相位和未调制的积分状态
		end
	end

	//-------------主要任务处理区域-------------//
	// 结果寄存之前各计算级的有效资格。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			flag_pipeline <= 2'd0;              // 清空尚未进入输出级的任务
		end else if(flag_advance == 1'b1)begin
			flag_pipeline <= {flag_pipeline[0:0], i_s_axis_tvalid}; // 输入资格跟随每次整体推进
		end
	end

	// 首次接纳的调用者编号。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_user_first <= 32'd0;            // 清除入口身份快照
		end else if(flag_advance == 1'b1)begin
			reg_user_first <= i_s_axis_tuser;   // 本拍标识进入首个计算级
		end
	end

	// 第二计算沿对应的编号。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_user_second <= 32'd0;           // 清除中间身份延迟
		end else if(flag_advance == 1'b1)begin
			reg_user_second <= reg_user_first;  // 标识对齐第二级运算
		end
	end

	// 只包含基础频率的下一相位。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_accumulator <= 32'd0;           // 初始化基础相位计算
		end else if(flag_advance == 1'b1)begin
			reg_accumulator <= i_s_axis_tdata[31:0] + i_s_axis_tdata[63:32]; // 相位按模数自然回绕
		end
	end

	// Q26 去小数后模三十二位的查表偏移。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_offset <= 32'd0;                // 初始化查表偏移量
		end else if(flag_advance == 1'b1)begin
			reg_offset <= reg_product[57:26];   // 取相位模数所需的低三十二个整数位
		end
	end

	// 等待调制量缩放的积分状态。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_phase_delayed <= 32'd0;         // 清除同行积分状态延迟
		end else if(flag_advance == 1'b1)begin
			reg_phase_delayed <= reg_accumulator; // 基础状态等待乘法量化完成
		end
	end

	// 调制音频乘相位深度的完整补码积。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_product <= 64'd0;               // 清除调制乘积级
		end else if(flag_advance == 1'b1)begin
			reg_product <= $signed(i_s_axis_tdata[95:64]) * $signed(i_s_axis_tdata[127:96]); // 两个有符号操作数保留乘积全宽
		end
	end

endmodule
