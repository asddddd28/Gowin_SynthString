`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/12 00:11:00
// Design Name:     WavetableMorph
// Module Name:     WavetableMorph
// Description:     description/WavetableMorph_Design.pdf
// Simulations:     testbench/vivado/2021.1/WavetableMorph
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/12 00:11:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/12       V1.0        Codex             Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月12日
// 设计名称:        WavetableMorph
// 模块名称:        WavetableMorph
// 模块说明:        Description/WavetableMorph_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/WavetableMorph
//
// 参考资料:        None
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年10月12日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月12日   V1.0        Codex             创建文件

module WavetableMorph
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 双帧计算时钟
	input i_rstn,                               // 异步低有效复位

	//-----------------用户接口-----------------//
	input i_valid,                              // 本拍四个点和小数有效
	input signed [17:0]i_first_a,               // 前帧周期起点
	input signed [17:0]i_second_a,              // 前帧周期邻点
	input signed [17:0]i_first_b,               // 后帧周期起点
	input signed [17:0]i_second_b,              // 后帧周期邻点
	input [15:0]i_phase_fraction,               // 两帧共同的周期内小数
	input [15:0]i_frame_fraction,               // 两帧之间的渐变小数
	output o_valid,                             // 七个采样沿后的有效标志
	output signed [17:0]o_sample                // 七个采样沿后的双帧结果
);

	//----------------寄存器信号----------------//
	reg signed [18:0]reg_delta_a = 19'd0;       // 前帧邻点差值保留符号扩展
	reg signed [18:0]reg_delta_b = 19'd0;       // 后帧周期跨度
	reg signed [17:0]reg_first_a = 18'd0;       // 前帧起点跟随差值锁存
	reg signed [17:0]reg_first_b = 18'd0;       // 后帧基准样值
	reg [15:0]reg_phase_fraction = 16'd0;       // 两份周期差共同使用的相位小数
	reg [15:0]reg_frame_start = 16'd0;          // 帧间比例的第一拍
	reg signed [35:0]reg_product_a = 36'd0;     // 前帧周期内完整乘积
	reg signed [35:0]reg_product_b = 36'd0;     // 后帧周期内未截断位移
	reg signed [17:0]reg_first_a_delayed = 18'd0; // 前帧起点的乘法对齐
	reg signed [17:0]reg_first_b_delayed = 18'd0; // 后帧基准的一拍延后
	reg [15:0]reg_frame_product = 16'd0;        // 帧间比例跟随周期乘法
	reg signed [17:0]reg_phase_a = 18'd0;       // 前帧完成周期内插值的样值
	reg signed [17:0]reg_phase_b = 18'd0;       // 后帧得到同一相位的音频值
	reg [15:0]reg_frame_sample = 16'd0;         // 与两个相位结果对应的帧间坐标
	reg signed [18:0]reg_delta_frame = 19'd0;   // 两帧同一相位的差值
	reg signed [17:0]reg_first_frame = 18'd0;   // 帧间混合的起点幅度
	reg [15:0]reg_frame_fraction = 16'd0;       // 帧间差值配对的无符号比例
	reg signed [35:0]reg_product_frame = 36'd0; // 完整帧间渐变乘积
	reg signed [17:0]reg_first_frame_delayed = 18'd0; // 帧间起点在乘法结束时的数值
	reg signed [17:0]reg_morphed = 18'd0;       // 双层插值完成后的暂存音频

	//-----------------标志信号-----------------//
	reg [6:0]flag_valid = 7'd0;                 // 七拍事务资格历史

	//-----------------编码信号-----------------//
	wire signed [16:0]enc_phase_fraction;       // 正的小数扩展符号位
	wire signed [16:0]enc_frame_fraction;       // 帧间坐标的正符号解释
	wire signed [19:0]enc_scaled_a;             // 前帧乘积移除十六位小数
	wire signed [19:0]enc_scaled_b;             // 后帧位移向负无穷取整
	wire signed [19:0]enc_scaled_frame;         // 帧间渐变的整数量

	//-----------------其他信号-----------------//
	// 周期与帧间求和
	wire signed [20:0]wire_sum_a;               // 前帧起点叠加周期位移
	wire signed [20:0]wire_sum_b;               // 后帧样值的最终求和
	wire signed [20:0]wire_sum_frame;           // 起点与帧间位移相加

	//-----------------输出信号-----------------//
	//用户接口
	wire valid_o;                               // 当前样值的有效标志
	reg signed [17:0]sample_o = 18'd0;          // 音频输出寄存样值

	//---------------其他信号连线---------------//
	//其他信号连线
	assign valid_o = flag_valid[6];             // 计算资格取最终历史位
	assign enc_phase_fraction = {1'b0, reg_phase_fraction}; // 周期比例保持非负
	assign enc_frame_fraction = {1'b0, reg_frame_fraction}; // 帧间比例补零符号
	assign enc_scaled_a = reg_product_a[35:16]; // 前帧乘积取带符号高位
	assign enc_scaled_b = reg_product_b[35:16]; // 后帧周期位移截去小数
	assign enc_scaled_frame = reg_product_frame[35:16]; // 帧间乘积执行负向取整
	assign wire_sum_a = reg_first_a_delayed + enc_scaled_a; // 还原前帧相位样值
	assign wire_sum_b = reg_first_b_delayed + enc_scaled_b; // 重建后帧当前相位
	assign wire_sum_frame = reg_first_frame_delayed + enc_scaled_frame; // 完成帧间幅度混合

	//---------------输出信号连线---------------//
	//用户接口
	assign o_valid = valid_o;                   // 输出七拍有效标志
	assign o_sample = sample_o;                 // 提交寄存音频

	//-------------输出信号处理区域-------------//
	//用户接口
	// 提交上一拍完整混合值，使计算结果具有固定输出边界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			sample_o <= 18'd0;                  // 清空最终音频边界
		end else begin
			sample_o <= reg_morphed;            // 更新最终音频边界
		end
	end

	//-------------主要任务处理区域-------------//
	// 移动事务标志，七个边沿后最高位成为输出资格。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_valid <= 7'd0;                 // 清空数据有效历史
		end else begin
			flag_valid <= {flag_valid[5:0], i_valid}; // 更新数据有效历史
		end
	end

	// 前帧两端点相减，十九位覆盖正负满幅距离。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_delta_a <= 19'd0;               // 清空前帧邻点差值保留符号扩展
		end else begin
			reg_delta_a <= i_second_a - i_first_a; // 更新前帧邻点差值保留符号扩展
		end
	end

	// 另一个周期独立保存邻点跨度，防止跨帧混用。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_delta_b <= 19'd0;               // 清空后帧周期跨度
		end else begin
			reg_delta_b <= i_second_b - i_first_b; // 更新后帧周期跨度
		end
	end

	// 保留输入基准供之后的乘积恢复绝对幅度。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_first_a <= 18'd0;               // 清空前帧起点跟随差值锁存
		end else begin
			reg_first_a <= i_first_a;           // 更新前帧起点跟随差值锁存
		end
	end

	// 同步缓存另一帧相同相位的起始幅度。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_first_b <= 18'd0;               // 清空后帧基准样值
		end else begin
			reg_first_b <= i_first_b;           // 更新后帧基准样值
		end
	end

	// 捕获无符号周期小数，下一拍扩展成正数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_phase_fraction <= 16'd0;        // 清空两份周期差共同使用的相位小数
		end else begin
			reg_phase_fraction <= i_phase_fraction; // 更新两份周期差共同使用的相位小数
		end
	end

	// 记住与四个样点同时进入的帧坐标。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_frame_start <= 16'd0;           // 清空帧间比例的第一拍
		end else begin
			reg_frame_start <= i_frame_fraction; // 更新帧间比例的第一拍
		end
	end

	// 第二级进行十九乘十七位运算，不丢掉低位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_product_a <= 36'd0;             // 清空前帧周期内完整乘积
		end else begin
			reg_product_a <= reg_delta_a * enc_phase_fraction; // 更新前帧周期内完整乘积
		end
	end

	// 另一周期的差分也在同一时钟完成乘法。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_product_b <= 36'd0;             // 清空后帧周期内未截断位移
		end else begin
			reg_product_b <= reg_delta_b * enc_phase_fraction; // 更新后帧周期内未截断位移
		end
	end

	// 推迟起始幅度一拍用于前一路加法。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_first_a_delayed <= 18'd0;       // 清空前帧起点的乘法对齐
		end else begin
			reg_first_a_delayed <= reg_first_a; // 更新前帧起点的乘法对齐
		end
	end

	// 在第二个乘法结束时送出该路基准。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_first_b_delayed <= 18'd0;       // 清空后帧基准的一拍延后
		end else begin
			reg_first_b_delayed <= reg_first_b; // 更新后帧基准的一拍延后
		end
	end

	// 进一步推迟渐变位置以跟随两路运算。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_frame_product <= 16'd0;         // 清空帧间比例跟随周期乘法
		end else begin
			reg_frame_product <= reg_frame_start; // 更新帧间比例跟随周期乘法
		end
	end

	// 前一路完成截位和加法，写入独立相位结果。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_phase_a <= 18'd0;               // 清空前帧完成周期内插值的样值
		end else begin
			reg_phase_a <= wire_sum_a[17:0];    // 更新前帧完成周期内插值的样值
		end
	end

	// 并行重建第二周期的同相位幅度。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_phase_b <= 18'd0;               // 清空后帧得到同一相位的音频值
		end else begin
			reg_phase_b <= wire_sum_b[17:0];    // 更新后帧得到同一相位的音频值
		end
	end

	// 第三次保存渐变坐标，阻止借用下一事务的数据。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_frame_sample <= 16'd0;          // 清空与两个相位结果对应的帧间坐标
		end else begin
			reg_frame_sample <= reg_frame_product; // 更新与两个相位结果对应的帧间坐标
		end
	end

	// 两份重建幅度相减，额外符号位避免反向端点溢出。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_delta_frame <= 19'd0;           // 清空两帧同一相位的差值
		end else begin
			reg_delta_frame <= reg_phase_b - reg_phase_a; // 更新两帧同一相位的差值
		end
	end

	// 暂存帧混合开始处的绝对参考值。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_first_frame <= 18'd0;           // 清空帧间混合的起点幅度
		end else begin
			reg_first_frame <= reg_phase_a;     // 更新帧间混合的起点幅度
		end
	end

	// 产生帧间跨度时捕获配对的权重。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_frame_fraction <= 16'd0;        // 清空帧间差值配对的无符号比例
		end else begin
			reg_frame_fraction <= reg_frame_sample; // 更新帧间差值配对的无符号比例
		end
	end

	// 十九位帧差乘正权重，保存全部三十六位结果。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_product_frame <= 36'd0;         // 清空完整帧间渐变乘积
		end else begin
			reg_product_frame <= reg_delta_frame * enc_frame_fraction; // 更新完整帧间渐变乘积
		end
	end

	// 将帧混合基准送到最终乘积的输出时刻。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_first_frame_delayed <= 18'd0;   // 清空帧间起点在乘法结束时的数值
		end else begin
			reg_first_frame_delayed <= reg_first_frame; // 更新帧间起点在乘法结束时的数值
		end
	end

	// 负向取整后的帧位移叠加起点，范围仍在端点之间。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_morphed <= 18'd0;               // 清空双层插值完成后的暂存音频
		end else begin
			reg_morphed <= wire_sum_frame[17:0]; // 更新双层插值完成后的暂存音频
		end
	end

endmodule
