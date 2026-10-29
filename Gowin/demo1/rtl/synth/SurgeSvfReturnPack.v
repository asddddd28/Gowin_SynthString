`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/12 20:16:06
// Design Name:     SurgeSvfReturnPack
// Module Name:     SurgeSvfReturnPack
// Description:     description/SurgeSvfReturnPack_Design.pdf
// Simulations:     testbench/vivado/2021.1/SurgeSvfReturnPack
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/12 20:16:06
// History:
// Time             Version     Revised by        Contents
// 2026/10/12       V1.0        Codex              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月12日
// 设计名称:        SurgeSvfReturnPack
// 模块名称:        SurgeSvfReturnPack
// 模块说明:        Description/SurgeSvfReturnPack_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/SurgeSvfReturnPack
//
// 参考资料:        None
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年10月12日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月12日   V1.0        Codex              创建文件

module SurgeSvfReturnPack
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 计算时钟,
	input i_rstn,                               // 异步低有效复位,

	//-----------------用户接口-----------------//
	input i_valid,                              // 核心结果的有效资格,
	input [4:0]i_voice,                         // 刚完成的声部槽地址,
	input [15:0]i_generation,                   // 数学流水携带的私有串号,
	input i_error,                              // 核心模式错误,
	input i_saturated,                          // 核心整数限幅标记,
	input [31:0]i_sample,                       // 滤波输出幅度,
	input [31:0]i_band,                         // 新带通记忆,
	input [31:0]i_low,                          // 新低通轨迹,
	input [31:0]i_damping,                      // 下个采样的能量回授,
	input [28:0]i_low_residue,                  // 低通积分小数尾数,
	input [28:0]i_band_residue,                 // 带通积分补偿,
	output [210:0]o_result                      // 身份和全部数值共同对齐的原子返回包
);

	//----------------寄存器信号----------------//
	reg [20:0]reg_ticket = 21'd0;               // 声部串号组合寄存值
	reg [3:0]reg_qualifier = 4'd0;              // 完成资格编码寄存值
	reg [63:0]reg_audio_band = 64'd0;           // 音频带通二元组寄存值
	reg [63:0]reg_low_damping = 64'd0;          // 低频衰减二元组寄存值
	reg [57:0]reg_residue_pair = 58'd0;         // 两路误差对寄存值
	reg [24:0]reg_identity = 25'd0;             // 完整提交身份寄存值
	reg [185:0]reg_payload = 186'd0;            // 滤波数值集合寄存值

	//-----------------输出信号-----------------//
	//用户接口
	reg [210:0]result_o = 211'd0;               // 广播完成包寄存值

	//---------------输出信号连线---------------//
	//用户接口
	assign o_result = result_o;                 // 原子提交包接至所有声部

	//-------------输出信号处理区域-------------//
	//用户接口
	// 完整广播结果寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			result_o <= 211'd0;                 // 清除完整广播结果旧值
		end else begin
			result_o <= {reg_identity, reg_payload}; // 本拍保存完整广播结果
		end
	end

	//-------------主要任务处理区域-------------//
	// 地址与凭证寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_ticket <= 21'd0;                // 清除地址与凭证旧值
		end else begin
			reg_ticket <= {i_voice, i_generation}; // 本拍保存地址与凭证
		end
	end

	// 有效成功饱和寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_qualifier <= 4'd0;              // 清除有效成功饱和旧值
		end else begin
			reg_qualifier <= {i_valid, i_valid, !i_error, i_saturated}; // 本拍保存有效成功饱和
		end
	end

	// 输出和带通幅度寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_audio_band <= 64'd0;            // 清除输出和带通幅度旧值
		end else begin
			reg_audio_band <= {i_sample, i_band}; // 本拍保存输出和带通幅度
		end
	end

	// 低通及阻尼寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low_damping <= 64'd0;           // 清除低通及阻尼旧值
		end else begin
			reg_low_damping <= {i_low, i_damping}; // 本拍保存低通及阻尼
		end
	end

	// 低带通尾数寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_residue_pair <= 58'd0;          // 清除低带通尾数旧值
		end else begin
			reg_residue_pair <= {i_low_residue, i_band_residue}; // 本拍保存低带通尾数
		end
	end

	// 资格和槽身份寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_identity <= 25'd0;              // 清除资格和槽身份旧值
		end else begin
			reg_identity <= {reg_qualifier, reg_ticket}; // 本拍保存资格和槽身份
		end
	end

	// 连贯数学快照寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_payload <= 186'd0;              // 清除连贯数学快照旧值
		end else begin
			reg_payload <= {reg_audio_band, reg_low_damping, reg_residue_pair}; // 本拍保存连贯数学快照
		end
	end

endmodule
