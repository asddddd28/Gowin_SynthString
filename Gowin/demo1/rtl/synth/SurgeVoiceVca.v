`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/13 09:56:41
// Design Name:     SurgeVoiceVca
// Module Name:     SurgeVoiceVca
// Description:     description/SurgeVoiceVca_Design.pdf
// Simulations:     testbench/vivado/2021.1/SurgeVoiceVca
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
// 设计名称:        SurgeVoiceVca
// 模块名称:        SurgeVoiceVca
// 模块说明:        Description/SurgeVoiceVca_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/SurgeVoiceVca
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

module SurgeVoiceVca
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 共享声部缩放时钟
	input i_rstn,                               // 清空算术与资格流水

	//-----------------用户接口-----------------//
	input [1:0]i_control,                       // 整体取消及输入事务资格
	input [77:0]i_payload,                      // 声部帧号样值音量及力度
	output o_valid,                             // 第三采样沿的声部完成资格
	output [52:0]o_payload                      // 同行地址世代和缩放结果
);

	//----------------寄存器信号----------------//
	reg signed [41:0]reg_envelope = 42'd0;      // 首次幅度缩放的完整积
	reg [27:0]reg_velocity_tag = 28'd0;         // 首沿声部帧号与七位力度
	reg signed [31:0]reg_velocity = 32'd0;      // 力度缩放不截断的乘积
	reg [20:0]reg_identity = 21'd0;             // 第二沿的地址与代号

	//-----------------标志信号-----------------//
	reg [2:0]flag_valid = 3'd0;                 // 三沿音频资格

	//-----------------编码信号-----------------//
	// 正数系数与有符号幅度
	wire signed [22:0]enc_audio;                // Q26向下取整为Q17
	wire signed [18:0]enc_level;                // 非负音量的补码解释
	wire signed [23:0]enc_envelope;             // 第一积向下取整十八位
	wire signed [7:0]enc_velocity;              // 力度扩展正符号
	wire [6:0]enc_polarity;                     // 算术取整的七位符号组

	//-----------------其他信号-----------------//
	// 第三沿的取整幅度
	wire signed [31:0]wire_scaled;              // 力度积向下取整七位

	//-----------------输出信号-----------------//
	//用户接口
	wire valid_o;                               // 当前取消遮蔽旧资格
	reg [52:0]payload_o = 53'd0;                // 最终标签与有符号幅度

	//---------------其他信号连线---------------//
	//其他信号连线
	assign enc_audio = i_payload[56:34];        // 负数丢低九位等同算术右移
	assign enc_level = {1'b0, i_payload[24:7]}; // 音量全十八位保持非负
	assign enc_envelope = reg_envelope[41:18];  // 第二个负向取整边界
	assign enc_velocity = {1'b0, reg_velocity_tag[6:0]}; // 力度最大一百二十七
	assign enc_polarity = {reg_velocity[31], reg_velocity[31], reg_velocity[31], reg_velocity[31], reg_velocity[31], reg_velocity[31], reg_velocity[31]}; // 七个符号位维持负幅度
	assign wire_scaled = {enc_polarity, reg_velocity[31:7]}; // 负样值保持算术取整方向
	assign valid_o = flag_valid[2] && !i_control[1]; // 取消当拍禁止输出

	//---------------输出信号连线---------------//
	//用户接口
	assign o_valid = valid_o;                   // 每拍至多一个已缩放声部
	assign o_payload = payload_o;               // 提供完整音频和帧身份

	//-------------输出信号处理区域-------------//
	//用户接口
	// 第三沿提交向下取整的声部音频。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			payload_o <= 53'd0;                 // 输出幅度及身份归零
		end else begin
			payload_o <= {reg_identity, wire_scaled}; // 发布缩放后的整包
		end
	end

	//-------------主要任务处理区域-------------//
	// 寄存音量乘法全宽积。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_envelope <= 42'd0;              // 清除初始包络幅度
		end else begin
			reg_envelope <= enc_audio * enc_level; // 保留完整的幅度积
		end
	end

	// 首沿参数标签跟随包络乘积。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_velocity_tag <= 28'd0;          // 首级标记从零开始
		end else begin
			reg_velocity_tag <= {i_payload[77:57], i_payload[6:0]}; // 锁定力度及声部身份
		end
	end

	// 第二沿完成力度乘法。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_velocity <= 32'd0;              // 清空尚未就绪的力度积
		end else begin
			reg_velocity <= enc_envelope * enc_velocity; // 寄存力度计算值
		end
	end

	// 地址和帧号推进至力度级。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_identity <= 21'd0;              // 撤销初始输出标签
		end else begin
			reg_identity <= reg_velocity_tag[27:7]; // 保存同行返回标记
		end
	end

	// 事务资格与三层算术同行。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_valid <= 3'd0;                 // 复位撤销全部在途事务
		end else begin
			flag_valid <= i_control[1] ? 3'd0 : {flag_valid[1:0], i_control[0]}; // 沿算术通路推进资格
		end
	end

endmodule
