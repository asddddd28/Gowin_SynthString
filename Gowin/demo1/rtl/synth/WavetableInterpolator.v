`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Erie
// Engineer:        Erie
//
// Create Date:     2026/10/11 22:46:21
// Design Name:     WavetableInterpolator
// Module Name:     WavetableInterpolator
// Description:     description/WavetableInterpolator_Design.pdf
// Simulations:     testbench/vivado/2021.1/WavetableInterpolator
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/11 22:46:21
// History:
// Time             Version     Revised by        Contents
// 2026/10/11       V1.0        Codex             Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Erie
// 开发人员:        Erie
//
// 创建日期:        2026年10月11日
// 设计名称:        WavetableInterpolator
// 模块名称:        WavetableInterpolator
// 模块说明:        Description/WavetableInterpolator_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/WavetableInterpolator
//
// 参考资料:        None
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年10月11日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月11日   V1.0        Codex             创建文件

module WavetableInterpolator
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 插值流水线时钟
	input i_rstn,                               // 异步低有效复位

	//-----------------用户接口-----------------//
	input signed [17:0]i_first,                 // 当前表点
	input signed [17:0]i_second,                // 回绕处理后的相邻表点
	input [15:0]i_fraction,                     // 周期内小数，比例为值除以 65536
	output signed [17:0]o_sample                // 三拍后的插值样值
);

	//----------------寄存器信号----------------//
	reg signed [18:0]reg_delta = 19'd0;         // 端点差值需要额外符号位
	reg signed [17:0]reg_first = 18'd0;         // 与差值一起保存起点
	reg signed [17:0]reg_first_delayed = 18'd0; // 对齐乘积流水级的起点
	reg [15:0]reg_fraction = 16'd0;             // 与端点差值对齐的小数
	reg signed [35:0]reg_product = 36'd0;       // 保留差值与正小数的完整乘积

	//-----------------编码信号-----------------//
	wire signed [16:0]enc_fraction;             // 小数扩展零符号位
	wire signed [19:0]enc_scaled;               // 截取算术右移的小数乘积

	//-----------------其他信号-----------------//
	// 周期样值求和
	wire signed [20:0]wire_sum;                 // 起点与插值位移之和

	//-----------------输出信号-----------------//
	//用户接口
	reg signed [17:0]sample_o = 18'd0;          // 输出寄存样值

	//---------------其他信号连线---------------//
	//其他信号连线
	assign enc_fraction = {1'b0, reg_fraction}; // 插值比例解释为非负数
	assign enc_scaled = reg_product[35:16];     // 保留符号并去掉十六位小数
	assign wire_sum = reg_first_delayed + enc_scaled; // 对齐起点并叠加插值位移

	//---------------输出信号连线---------------//
	//用户接口
	assign o_sample = sample_o;                 // 提交已寄存的插值样值

	//-------------输出信号处理区域-------------//
	//用户接口
	// 输出周期内插值结果，数学范围保证适合十八位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			sample_o <= 18'd0;                  // 复位时输出静音样值
		end else begin
			sample_o <= wire_sum[17:0];         // 输出已完成的周期插值
		end
	end

	//-------------主要任务处理区域-------------//
	// 扩展后的端点差可覆盖正负满幅跳变。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_delta <= 19'd0;                 // 端点差值初始为零
		end else begin
			reg_delta <= i_second - i_first;    // 计算带符号的相邻点差
		end
	end

	// 保存第一拍的周期起点。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_first <= 18'd0;                 // 清空第一拍锁存的起点
		end else begin
			reg_first <= i_first;               // 锁存与差值对应的起点
		end
	end

	// 起点延迟到乘积完成的同一拍。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_first_delayed <= 18'd0;         // 撤销起点的乘法对齐延迟
		end else begin
			reg_first_delayed <= reg_first;     // 对齐插值乘积的起点
		end
	end

	// 小数和端点差保持同拍对齐。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_fraction <= 16'd0;              // 复位后选择周期起点位置
		end else begin
			reg_fraction <= i_fraction;         // 锁存本周期内小数
		end
	end

	// 计算完整的有符号位移乘积。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_product <= 36'd0;               // 清空乘积避免复位前位移泄漏
		end else begin
			reg_product <= reg_delta * enc_fraction; // 乘法完整精度进入下一流水级
		end
	end

endmodule
