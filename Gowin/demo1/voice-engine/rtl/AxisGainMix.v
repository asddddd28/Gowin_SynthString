`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         SynthString project
// Engineer:        Codex
//
// Create Date:     2026/11/02 00:00:00
// Design Name:     AxisGainMix
// Module Name:     AxisGainMix
// Description:     description/AxisGainMix_Design.pdf
// Simulations:     testbench/vivado/2021.1/AxisGainMix
//
// Referrences:
// File Format      File Name
// 1.Book           spec/rtl/AxisGainMix_spec.md
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
// 设计名称:        AxisGainMix
// 模块名称:        AxisGainMix
// 模块说明:        Description/AxisGainMix_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/AxisGainMix
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           spec/rtl/AxisGainMix_spec.md
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

module AxisGainMix
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
	reg signed [63:0]reg_product_primary = 64'd0; // 主输入乘主增益的全宽结果
	reg signed [63:0]reg_product_auxiliary = 64'd0; // 辅输入乘辅增益的独立乘积
	reg signed [64:0]reg_sum = 65'd0;           // 两个乘积相加保留进位保护
	reg [31:0]reg_quantized = 32'd0;            // 去除小数后的低位候选

	// 事务身份经过与算术相同的停顿边界
	reg [31:0]reg_user_first = 32'd0;           // 首次接纳的调用者编号
	reg [31:0]reg_user_second = 32'd0;          // 第二计算沿对应的编号
	reg [31:0]reg_user_third = 32'd0;           // 最终量化之前的身份延迟

	//-----------------标志信号-----------------//
	reg flag_overflow_positive = 1'd0;          // 量化结果高于有符号正界
	reg flag_overflow_negative = 1'd0;          // 量化结果低于有符号负界

	// 有效位与整体前进许可
	reg [2:0]flag_pipeline = 3'd0;              // 结果寄存之前各计算级的有效资格
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
			m_axis_tdata_o <= 64'd0;            // 初始化乘加返回值
		end else if(flag_advance == 1'b1)begin
			m_axis_tdata_o <= {31'd0, flag_overflow_positive | flag_overflow_negative, flag_overflow_positive ? 32'h7fffffff : (flag_overflow_negative ? 32'h80000000 : reg_quantized)}; // 返回饱和音频并保留削波事实
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

	// 量化结果低于有符号负界。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			flag_overflow_negative <= 1'b0;     // 清除负饱和检测
		end else if(flag_advance == 1'b1)begin
			flag_overflow_negative <= reg_sum < -65'sd144115188075855872; // 负界对应最小三十二位整数乘Q26比例
		end
	end

	// 量化结果高于有符号正界。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			flag_overflow_positive <= 1'b0;     // 清除正饱和检测
		end else if(flag_advance == 1'b1)begin
			flag_overflow_positive <= reg_sum >= 65'sd144115188075855872; // 仅量化后超过正界才设置削波标志
		end
	end

	// 辅输入乘辅增益的独立乘积。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_product_auxiliary <= 64'd0;     // 清空辅增益乘法级
		end else if(flag_advance == 1'b1)begin
			reg_product_auxiliary <= $signed(i_s_axis_tdata[95:64]) * $signed(i_s_axis_tdata[127:96]); // 辅路可以表示第二声源或偏置
		end
	end

	// 主输入乘主增益的全宽结果。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_product_primary <= 64'd0;       // 清空主增益乘法级
		end else if(flag_advance == 1'b1)begin
			reg_product_primary <= $signed(i_s_axis_tdata[31:0]) * $signed(i_s_axis_tdata[63:32]); // 主路补码乘法不提前截断
		end
	end

	// 去除小数后的低位候选。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_quantized <= 32'd0;             // 清除舍入候选字
		end else if(flag_advance == 1'b1)begin
			reg_quantized <= reg_sum[57:26];    // 负数截去小数等价向负无穷取整
		end
	end

	// 两个乘积相加保留进位保护。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_sum <= 65'd0;                   // 初始化带保护位的累加结果
		end else if(flag_advance == 1'b1)begin
			reg_sum <= $signed({reg_product_primary[63], reg_product_primary}) + $signed({reg_product_auxiliary[63], reg_product_auxiliary}); // 累加宽度覆盖两个最坏乘积
		end
	end

endmodule
