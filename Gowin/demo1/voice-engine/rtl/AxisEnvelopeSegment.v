`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         SynthString project
// Engineer:        Codex
//
// Create Date:     2026/11/02 00:00:00
// Design Name:     AxisEnvelopeSegment
// Module Name:     AxisEnvelopeSegment
// Description:     description/AxisEnvelopeSegment_Design.pdf
// Simulations:     testbench/vivado/2021.1/AxisEnvelopeSegment
//
// Referrences:
// File Format      File Name
// 1.Book           spec/rtl/AxisEnvelopeSegment_spec.md
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
// 设计名称:        AxisEnvelopeSegment
// 模块名称:        AxisEnvelopeSegment
// 模块说明:        Description/AxisEnvelopeSegment_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/AxisEnvelopeSegment
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           spec/rtl/AxisEnvelopeSegment_spec.md
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

module AxisEnvelopeSegment
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
	reg signed [31:0]reg_level_first = 32'd0;   // 差分计算同行的旧电平
	reg [31:0]reg_target_first = 32'd0;         // 首级保留的目标值
	reg [31:0]reg_step_first = 32'd0;           // 无符号绝对步长快照
	reg [32:0]reg_distance = 33'd0;             // 当前电平到目标的非负距离
	reg signed [31:0]reg_level_second = 32'd0;  // 候选求和使用的当前电平
	reg [31:0]reg_target_second = 32'd0;        // 距离级的目标对齐
	reg [31:0]reg_step_second = 32'd0;          // 距离级携带的绝对步长
	reg signed [33:0]reg_candidate = 34'd0;     // 可容纳越界试探值的扩展候选
	reg [31:0]reg_target_third = 32'd0;         // 终点限幅时的目标快照

	// 事务身份经过与算术相同的停顿边界
	reg [31:0]reg_user_first = 32'd0;           // 首次接纳的调用者编号
	reg [31:0]reg_user_second = 32'd0;          // 第二计算沿对应的编号
	reg [31:0]reg_user_third = 32'd0;           // 最终量化之前的身份延迟

	//-----------------标志信号-----------------//
	reg flag_descending = 1'd0;                 // 负差要求朝下降方向推进
	reg flag_reached = 1'd0;                    // 本步跨度足以到达终点
	reg flag_stalled = 1'd0;                    // 非终点且步长为零的诊断状态

	// 有效位与整体前进许可
	reg [2:0]flag_pipeline = 3'd0;              // 结果寄存之前各计算级的有效资格
	wire flag_advance;                          // 输出为空或被消费时整体推进

	//-----------------编码信号-----------------//
	// 算术阶段之间保存的独立快照
	reg signed [32:0]enc_level_delta = 33'd0;   // 目标减当前电平的扩展差

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
			m_axis_tvalid_o <= flag_pipeline[2]; // 最末算术资格转为输出有效
		end
	end

	//AXI-Stream总线M--数据通道
	// 与返回字绑定的事务归属。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tuser_o <= 32'd0;            // 初始化对外编号
		end else if(flag_advance == 1'b1)begin
			m_axis_tuser_o <= reg_user_third;   // 提交与结果相同流水深度的编号
		end
	end

	// 被反压时保持完整返回字。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tdata_o <= 64'd0;            // 复位包络返回字
		end else if(flag_advance == 1'b1)begin
			m_axis_tdata_o <= {30'd0, flag_stalled, flag_reached, flag_reached ? reg_target_third : reg_candidate[31:0]}; // 限幅后的电平与状态原子返回
		end
	end

	//-------------主要任务处理区域-------------//
	// 结果寄存之前各计算级的有效资格。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			flag_pipeline <= 3'd0;              // 清空尚未进入输出级的任务
		end else if(flag_advance == 1'b1)begin
			flag_pipeline <= {flag_pipeline[1:0], i_s_axis_tvalid}; // 输入资格跟随每次整体推进
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

	// 最终量化之前的身份延迟。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_user_third <= 32'd0;            // 清除量化级身份记录
		end else if(flag_advance == 1'b1)begin
			reg_user_third <= reg_user_second;  // 标识对齐最终范围判断
		end
	end

	// 负差要求朝下降方向推进。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			flag_descending <= 1'b0;            // 默认使用上升方向
		end else if(flag_advance == 1'b1)begin
			flag_descending <= enc_level_delta[32]; // 差值符号决定运动方向
		end
	end

	// 本步跨度足以到达终点。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			flag_reached <= 1'b0;               // 清除终点比较结果
		end else if(flag_advance == 1'b1)begin
			flag_reached <= {1'b0, reg_step_second} >= reg_distance; // 包含恰好命中与已经处于终点
		end
	end

	// 非终点且步长为零的诊断状态。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			flag_stalled <= 1'b0;               // 初始化零速诊断
		end else if(flag_advance == 1'b1)begin
			flag_stalled <= (reg_step_second == 32'd0) && (reg_distance != 33'd0); // 区分零速停滞和正常终点保持
		end
	end

	// 可容纳越界试探值的扩展候选。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_candidate <= 34'd0;             // 清除可能越界的候选结果
		end else if(flag_advance == 1'b1)begin
			reg_candidate <= flag_descending ? $signed({{2{reg_level_second[31]}}, reg_level_second}) - $signed({2'b00, reg_step_second}) : $signed({{2{reg_level_second[31]}}, reg_level_second}) + $signed({2'b00, reg_step_second}); // 候选用三十四位避免步进中间溢出
		end
	end

	// 目标减当前电平的扩展差。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			enc_level_delta <= 33'd0;           // 清除有符号目标距离
		end else if(flag_advance == 1'b1)begin
			enc_level_delta <= $signed({i_s_axis_tdata[63], i_s_axis_tdata[63:32]}) - $signed({i_s_axis_tdata[31], i_s_axis_tdata[31:0]}); // 符号扩展后保留两端极值之差
		end
	end

	// 当前电平到目标的非负距离。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_distance <= 33'd0;              // 清除绝对距离寄存值
		end else if(flag_advance == 1'b1)begin
			reg_distance <= enc_level_delta[32] ? -enc_level_delta : enc_level_delta; // 距离的绝对值保留三十三位
		end
	end

	// 差分计算同行的旧电平。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_level_first <= 32'd0;           // 初始化差分级电平快照
		end else if(flag_advance == 1'b1)begin
			reg_level_first <= i_s_axis_tdata[31:0]; // 当前电平进入差分级
		end
	end

	// 候选求和使用的当前电平。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_level_second <= 32'd0;          // 复位候选计算的电平
		end else if(flag_advance == 1'b1)begin
			reg_level_second <= reg_level_first; // 电平跟随距离取绝对值
		end
	end

	// 无符号绝对步长快照。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_step_first <= 32'd0;            // 初始化入口步进幅度
		end else if(flag_advance == 1'b1)begin
			reg_step_first <= i_s_axis_tdata[95:64]; // 步长按无符号幅度锁定
		end
	end

	// 距离级携带的绝对步长。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_step_second <= 32'd0;           // 清除距离级步进量
		end else if(flag_advance == 1'b1)begin
			reg_step_second <= reg_step_first;  // 步长对齐绝对距离
		end
	end

	// 首级保留的目标值。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_target_first <= 32'd0;          // 清除入口目标记录
		end else if(flag_advance == 1'b1)begin
			reg_target_first <= i_s_axis_tdata[63:32]; // 目标与当前电平同时采样
		end
	end

	// 距离级的目标对齐。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_target_second <= 32'd0;         // 复位距离级目标
		end else if(flag_advance == 1'b1)begin
			reg_target_second <= reg_target_first; // 目标进入候选运算前一级
		end
	end

	// 终点限幅时的目标快照。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_target_third <= 32'd0;          // 复位最终限幅目标
		end else if(flag_advance == 1'b1)begin
			reg_target_third <= reg_target_second; // 终点跨越时使用同行目标
		end
	end

endmodule
