`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/13 09:56:41
// Design Name:     SurgeFrameAccumulator
// Module Name:     SurgeFrameAccumulator
// Description:     description/SurgeFrameAccumulator_Design.pdf
// Simulations:     testbench/vivado/2021.1/SurgeFrameAccumulator
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
// 设计名称:        SurgeFrameAccumulator
// 模块名称:        SurgeFrameAccumulator
// 模块说明:        Description/SurgeFrameAccumulator_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/SurgeFrameAccumulator
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

module SurgeFrameAccumulator
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 唯一声部提交的计算时钟
	input i_rstn,                               // 撤销所有帧与累加历史

	//-----------------用户接口-----------------//
	input [17:0]i_control,                      // 取消新帧和新帧代号
	input [54:0]i_result,                       // 双份有效码帧号声部地址与样值
	output o_valid,                             // 三十二个独立槽完成的脉冲
	output [15:0]o_epoch,                       // 完整帧的代号
	output signed [63:0]o_sum                   // 未限幅的整帧有符号和
);

	//-----------------计数信号-----------------//
	reg [5:0]cnt_voice = 6'd0;                  // 当前帧已提交的唯一槽数

	//----------------寄存器信号----------------//
	reg [17:0]reg_owner = 18'b100000000000000000; // 双资格编码与活动帧号
	reg [54:0]reg_work = 55'd0;                 // 初始化资格地址帧号及音频
	reg [31:0]reg_onehot = 32'd0;               // 入口声部对应的单一位掩码
	reg [31:0]reg_seen = 32'd0;                 // 已采纳的声部集合
	reg [47:0]reg_commit_data = 48'd0;          // 累加前一沿的帧号与音频
	reg [17:0]reg_completion = 18'd0;           // 双份完成脉冲与输出所属帧

	//-----------------标志信号-----------------//
	reg [1:0]flag_commit = 2'd0;                // 初始化和唯一样值资格

	// 入口资格和有符号累加候选
	wire flag_initialize;                       // 命令沿形成有序清理事件
	wire flag_current;                          // 单个返回属于活动帧
	wire flag_complete;                         // 最后唯一声部提交

	//-----------------编码信号-----------------//
	wire signed [63:0]enc_sample;               // 三十二位样值带符号扩展
	wire [7:0]enc_sign_byte;                    // 单字节符号扩展组

	//-----------------其他信号-----------------//
	// 返回身份和扩展累加
	wire [17:0]wire_identity;                   // 双有效码与返回所属帧
	wire signed [64:0]wire_sum;                 // 帧和加法保留进位
	wire [6:0]wire_successor;                   // 槽计数扩展一位

	//-----------------输出信号-----------------//
	//用户接口
	wire valid_o;                               // 当前所有权允许完成通知
	reg [15:0]epoch_o = 16'd0;                  // 初始化流水设置的帧标签
	reg signed [63:0]sum_o = 64'd0;             // 完整保护位累加结果

	//---------------其他信号连线---------------//
	//其他信号连线
	assign flag_initialize = i_control[17:16] != 2'b00; // 清理事件不能和数据事件并存
	assign wire_identity = i_result[54:37];     // 返回身份的连续原子字段
	assign flag_current = {i_control[17:16], wire_identity} == {2'b00, reg_owner}; // 双份资格与帧号原子匹配
	assign enc_sign_byte = {reg_commit_data[31], reg_commit_data[31], reg_commit_data[31], reg_commit_data[31], reg_commit_data[31], reg_commit_data[31], reg_commit_data[31], reg_commit_data[31]}; // 显式保留一个符号字节
	assign enc_sample = {enc_sign_byte, enc_sign_byte, enc_sign_byte, enc_sign_byte, reg_commit_data[31:0]}; // 完整六十四位补码解释
	assign wire_sum = sum_o + enc_sample;       // 六十五位候选避免窄表达式
	assign wire_successor = cnt_voice + 1'b1;   // 最后一次增至三十二
	assign flag_complete = {flag_commit, cnt_voice} == 8'b01011111; // 初始化关闭时第三十二项成立
	assign valid_o = {i_control[17:16], reg_completion} == {2'b00, reg_owner}; // 新命令和旧帧均不能释放当前帧

	//---------------输出信号连线---------------//
	//用户接口
	assign o_valid = valid_o;                   // 消费者采用完整帧脉冲
	assign o_epoch = epoch_o;                   // 只在完成时读取所属代号
	assign o_sum = sum_o;                       // 保持全部三十二项的精确和

	//-------------输出信号处理区域-------------//
	//用户接口
	// 有序初始化设定输出帧标签。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			epoch_o <= 16'd0;                   // 输出所属帧复位为零
		end else begin
			epoch_o <= flag_commit[1] ? reg_commit_data[47:32] : epoch_o; // 登记当前输出所属帧
		end
	end

	// 第三沿清理或加入唯一音频。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			sum_o <= 64'd0;                     // 帧和从精确零开始
		end else begin
			sum_o <= flag_commit[1] ? 64'd0 : (flag_commit[0] ? wire_sum[63:0] : sum_o); // 更新完整保护位帧和
		end
	end

	//-------------主要任务处理区域-------------//
	// 命令立即改变外部所有权，数值初始化随后按输入沿排序。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_owner <= 18'b100000000000000000; // 无帧时不匹配零有效返回
		end else if(i_control[17:16] != 2'b00)begin
			reg_owner <= i_control[17] ? 18'b100000000000000000 : {2'b11, i_control[15:0]}; // 取消优先于新标签登记
		end
	end

	// 第一沿锁存有序命令或样值。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_work <= 55'd0;                  // 建立空事件流水
		end else begin
			reg_work <= {flag_initialize, flag_current, i_result[36:32], (flag_initialize ? i_control[15:0] : i_result[52:37]), i_result[31:0]}; // 存入当前入口事件
		end
	end

	// 声部单一位掩码与入口事件同行。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_onehot <= 32'd0;                // 复位声部位标记
		end else begin
			reg_onehot <= 32'b00000000000000000000000000000001 << i_result[36:32]; // 锁存单声部掩码
		end
	end

	// 第二沿更新唯一声部集合。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_seen <= 32'd0;                  // 清除全部已见槽
		end else begin
			reg_seen <= reg_work[54] ? 32'd0 : (reg_work[53] ? (reg_seen | reg_onehot) : reg_seen); // 形成新的已见集合
		end
	end

	// 首次出现的有效声部进入提交。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_commit <= 2'd0;                // 无任何候选可以提交
		end else begin
			flag_commit <= {reg_work[54], ({reg_work[53], reg_seen[reg_work[52:48]]} == 2'b10)}; // 登记待提交资格
		end
	end

	// 帧号与幅度推迟到累加沿。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_commit_data <= 48'd0;           // 初始提交样值清零
		end else begin
			reg_commit_data <= reg_work[47:0];  // 保留提交音频和代号
		end
	end

	// 唯一声部提交数跟随帧和。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			cnt_voice <= 6'd0;                  // 撤销累计槽数量
		end else begin
			cnt_voice <= flag_commit[1] ? 6'd0 : (flag_commit[0] ? wire_successor[5:0] : cnt_voice); // 推进唯一声部计数
		end
	end

	// 完成资格只在最后提交沿产生。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_completion <= 18'd0;            // 初始不存在完成帧
		end else begin
			reg_completion <= {flag_complete, flag_complete, epoch_o}; // 寄存完整帧资格
		end
	end

endmodule
