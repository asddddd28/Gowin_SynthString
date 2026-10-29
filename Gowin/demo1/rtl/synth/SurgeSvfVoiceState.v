`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/12 20:16:06
// Design Name:     SurgeSvfVoiceState
// Module Name:     SurgeSvfVoiceState
// Description:     description/SurgeSvfVoiceState_Design.pdf
// Simulations:     testbench/vivado/2021.1/SurgeSvfVoiceState
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
// 设计名称:        SurgeSvfVoiceState
// 模块名称:        SurgeSvfVoiceState
// 模块说明:        Description/SurgeSvfVoiceState_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/SurgeSvfVoiceState
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

module SurgeSvfVoiceState
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 计算时钟,
	input i_rstn,                               // 异步低有效复位,

	//-----------------用户接口-----------------//
	input [23:0]i_command,                      // 控制字：panic、更新、丢弃状态和二十一位声部事务身份,
	input [15:0]i_generation,                   // 调度端此次采用的参数世代,
	input [210:0]i_result,                      // 三级对齐后的完整返回包,
	output o_ready,                             // 该声部没有尚待完成的采样,
	output [153:0]o_state,                      // 递归幅度和积分误差的连贯读出,
	output o_valid,                             // 当前所有者完成的返回脉冲,
	output [15:0]o_generation,                  // 与音频对齐的参数身份,
	output [31:0]o_sample,                      // 完成本次滤波的二十六位小数音频,
	output o_saturated,                         // 本采样触及整数限幅,
	output o_error                              // 模式非法且数学状态未改写
);

	//----------------寄存器信号----------------//
	reg [23:0]reg_owner = 24'h800000;           // 当前有效声部凭证或无效编码
	reg [153:0]reg_history = 154'd0;            // 已提交的五个数学状态
	reg [15:0]reg_configuration = 16'd0;        // 所有者参数标识
	reg [210:0]reg_return = 211'd0;             // 资格判定同时捕获的结果

	//-----------------标志信号-----------------//
	reg flag_done = 1'b0;                       // 当前事务已结束
	reg flag_known = 1'b0;                      // 历史幅度具有读取资格
	reg flag_match = 1'b0;                      // 返回包仍属于本所有者
	reg flag_store = 1'b0;                      // 数值正确且身份一致
	wire flag_write;                            // 本拍未被新身份取消的数学提交

	//-----------------其他信号-----------------//
	// 身份检查与延后一拍的提交资格
	wire [23:0]wire_return_identity;            // 保留错误返回资格的身份
	wire [23:0]wire_success_identity;           // 只有合法数值才匹配的编码

	//-----------------输出信号-----------------//
	//用户接口
	reg valid_o = 1'd0;                         // 当前所有者完成的返回脉冲输出暂存
	reg [15:0]generation_o = 16'd0;             // 与音频对齐的参数身份输出暂存
	reg [31:0]sample_o = 32'd0;                 // 完成本次滤波的二十六位小数音频输出暂存
	reg saturated_o = 1'd0;                     // 本采样触及整数限幅输出暂存
	reg error_o = 1'd0;                         // 模式非法且数学状态未改写输出暂存

	//---------------其他信号连线---------------//
	//其他信号连线
	assign wire_return_identity = {i_result[210:209], 1'b1, i_result[206:186]}; // 错误也可结束当前事务
	assign wire_success_identity = {i_result[210:208], i_result[206:186]}; // 成功码同时保护数学写回
	assign flag_write = {i_command[22], flag_store} == 2'b01; // 所有者更新优先于幅度回写

	//---------------输出信号连线---------------//
	//用户接口
	assign o_ready = flag_done || !reg_owner[22]; // 空所有者和已结束声部均可再用
	assign o_state = flag_known ? reg_history : 154'd0; // 重用后的未知历史读作零
	assign o_valid = valid_o;                   // 返回资格送往调用者
	assign o_generation = generation_o;         // 配置标签送往调用者
	assign o_sample = sample_o;                 // 滤波音频送往调用者
	assign o_saturated = saturated_o;           // 边界标记送往调用者
	assign o_error = error_o;                   // 模式诊断送往调用者

	//-------------输出信号处理区域-------------//
	//用户接口
	// 已更新的身份不能再输出旧音频。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			valid_o <= 1'b0;                    // 清除完成脉冲
		end else if(i_command[22])begin
			valid_o <= 1'b0;                    // 更新拍取消旧返回
		end else begin
			valid_o <= flag_match;              // 报告本槽匹配结果
		end
	end

	// 对齐后的外部世代寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			generation_o <= 16'd0;              // 清除对齐后的外部世代旧值
		end else begin
			generation_o <= reg_configuration;  // 本拍保存对齐后的外部世代
		end
	end

	// 返回音频寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			sample_o <= 32'd0;                  // 清除返回音频旧值
		end else begin
			sample_o <= reg_return[185:154];    // 本拍保存返回音频
		end
	end

	// 饱和提示寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			saturated_o <= 1'd0;                // 清除饱和提示旧值
		end else begin
			saturated_o <= reg_return[207];     // 本拍保存饱和提示
		end
	end

	// 模式错误寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			error_o <= 1'd0;                    // 清除模式错误旧值
		end else begin
			error_o <= !reg_return[208];        // 本拍保存模式错误
		end
	end

	//-------------主要任务处理区域-------------//
	// 接受新身份的同拍禁止旧事务推进。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_owner <= 24'h800000;            // 无效码不同于空结果码
		end else if(i_command[22])begin
			if(i_command[23])begin
				reg_owner <= 24'h800000;        // panic撤销提交身份
			end else begin
				reg_owner <= {3'b111, i_command[20:0]}; // 安装新的声部事务凭证
			end
		end
	end

	// 凭证更新前后的忙闲边界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_done <= 1'b0;                  // 尚无采样完成
		end else if(i_command[22])begin
			flag_done <= 1'b0;                  // 新所有者需要一次返回
		end else if(flag_match == 1'b1)begin
			flag_done <= 1'b1;                  // 错误或成功均结束本事务
		end
	end

	// 声部复用丢弃旧数值资格。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_known <= 1'b0;                 // 初始化没有递归历史
		end else if(i_command[21])begin
			flag_known <= 1'b0;                 // panic或重用不读取旧音色
		end else if(flag_store == 1'b1)begin
			flag_known <= 1'b1;                 // 合法积分值可以接续
		end
	end

	// 数学回写服从同拍所有者更新优先级。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_history <= 154'd0;              // 五个递归量回到原点
		end else if(flag_write == 1'b1)begin
			reg_history <= reg_return[153:0];   // 存入完成包的幅度和尾数
		end
	end

	// 旧包所有权判定寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_match <= 1'd0;                 // 清除旧包所有权判定旧值
		end else begin
			flag_match <= (reg_owner == wire_return_identity) && !i_command[22]; // 本拍保存旧包所有权判定
		end
	end

	// 合法幅度写入资格寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_store <= 1'd0;                 // 清除合法幅度写入资格旧值
		end else begin
			flag_store <= (reg_owner == wire_success_identity) && !i_command[22]; // 本拍保存合法幅度写入资格
		end
	end

	// 提交前的连贯结果寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_return <= 211'd0;               // 清除提交前的连贯结果旧值
		end else begin
			reg_return <= i_result;             // 本拍保存提交前的连贯结果
		end
	end

	// 参数所有权寄存处理。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_configuration <= 16'd0;         // 清除参数所有权旧值
		end else if(i_command[22])begin
			reg_configuration <= i_generation;  // 本拍保存参数所有权
		end
	end

endmodule
