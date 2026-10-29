`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/13 10:41:53
// Design Name:     SurgePcmOutput
// Module Name:     SurgePcmOutput
// Description:     description/SurgePcmOutput_Design.pdf
// Simulations:     testbench/vivado/2021.1/SurgePcmOutput
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/13 10:41:53
// History:
// Time             Version     Revised by        Contents
// 2026/10/13       V1.0        Codex              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月13日
// 设计名称:        SurgePcmOutput
// 模块名称:        SurgePcmOutput
// 模块说明:        Description/SurgePcmOutput_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/SurgePcmOutput
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

module SurgePcmOutput
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 完整帧和的输出计算时钟
	input i_rstn,                               // 撤销主增益及所有输出流水

	//-----------------用户接口-----------------//
	input [17:0]i_control,                      // 取消启动和帧号的原子命令
	input [20:0]i_gain,                         // 新帧开始时捕获的非负主增益
	input [81:0]i_return,                       // 双份有效码帧号与完整有符号帧和
	output o_valid,                             // 当前所有者对应的PCM提交资格
	output [40:0]o_payload                      // 削波标志帧号和二十四位补码音频
);

	//----------------寄存器信号----------------//
	reg [38:0]reg_owner = 39'b100000000000000000000000000000000000000; // 不可匹配所有者及锁定主增益
	reg signed [85:0]reg_product = 86'd0;       // 完整主增益乘积
	reg [15:0]reg_product_tag = 16'd0;          // 首沿的结果所属帧
	reg [86:0]reg_magnitude = 87'd0;            // 扩展绝对值不丢最负数
	reg [16:0]reg_polarity_tag = 17'd0;         // 符号和帧号同行
	reg [87:0]reg_biased = 88'd0;               // 半值偏置后的完整幅度
	reg [16:0]reg_bias_tag = 17'd0;             // 第三沿的补码身份
	reg [77:0]reg_rounded = 78'd0;              // 移位后尚未限幅的幅度
	reg [16:0]reg_round_tag = 17'd0;            // 舍入幅度所属身份
	reg [23:0]reg_low = 24'd0;                  // 合法范围的候选低位
	reg [16:0]reg_limit_tag = 17'd0;            // 限幅前的符号和帧号
	reg [23:0]reg_selected = 24'd0;             // 已限制到合法补码幅度
	reg [17:0]reg_output_tag = 18'd0;           // 削波帧号与最终符号
	reg [17:0]reg_completion = 18'd0;           // 双份完成码和当前帧号

	//-----------------标志信号-----------------//
	reg [1:0]flag_bounds = 2'd0;                // 负端和正端的越界判断
	reg flag_launch = 1'b0;                     // 第一乘法沿的请求资格
	reg [4:0]flag_waiting = 5'd0;               // 中间五个边界的有效资格
	wire flag_current;                          // 合法完整帧和属于当前主增益
	wire flag_limit_sign;                       // 当前限幅幅度的原始符号

	//-----------------编码信号-----------------//
	wire signed [63:0]enc_sum;                  // 不截断的补码混音值
	wire signed [21:0]enc_gain;                 // 正号扩展的二十一位增益
	wire signed [86:0]enc_product;              // 乘积求绝对值前扩展一位

	//-----------------其他信号-----------------//
	// 原子所有权及完整有符号操作数
	wire [17:0]wire_identity;                   // 输入的重复资格和帧号
	wire [87:0]wire_bias;                       // 保留偏置进位的幅度候选

	//-----------------输出信号-----------------//
	//用户接口
	wire valid_o;                               // 新命令同拍关闭旧提交
	reg [40:0]payload_o = 41'd0;                // 音频及所属帧的完整输出包

	//---------------其他信号连线---------------//
	//其他信号连线
	assign wire_identity = i_return[81:64];     // 连续字段进行原子匹配
	assign flag_current = {i_control[17:16], wire_identity} == {2'b00, reg_owner[38:21]}; // 当前帧和不跨主增益边界
	assign enc_sum = i_return[63:0];            // 保留完整六十四位动态范围
	assign enc_gain = {1'b0, reg_owner[20:0]};  // 无符号参数作为正补码相乘
	assign enc_product = {reg_product[85], reg_product}; // 最负数求幅度仍有保护位
	assign wire_bias = {1'b0, reg_magnitude} + 10'd512; // 正负半值使用同一舍入距离
	assign flag_limit_sign = reg_limit_tag[16]; // 简单索引选择正负边界
	assign valid_o = {i_control[17:16], reg_completion} == {2'b00, reg_owner[38:21]}; // 完成帧号与当前所有者匹配

	//---------------输出信号连线---------------//
	//用户接口
	assign o_valid = valid_o;                   // 播放端只采纳有效完整样本
	assign o_payload = payload_o;               // 提供削波事件和二十四位音频

	//-------------输出信号处理区域-------------//
	//用户接口
	// 最终恢复符号并提交完整PCM包。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			payload_o <= 41'd0;                 // PCM及事件归零
		end else begin
			payload_o <= {reg_output_tag[17:1], (reg_output_tag[0] ? -reg_selected : reg_selected)}; // 发布对称舍入后的补码样本
		end
	end

	//-------------主要任务处理区域-------------//
	// 新帧原子锁定增益，取消优先于启动。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_owner <= 39'b100000000000000000000000000000000000000; // 初始不存在可匹配的帧
		end else if(i_control[17:16] != 2'b00)begin
			reg_owner <= i_control[17] ? 39'b100000000000000000000000000000000000000 : {2'b11, i_control[15:0], i_gain}; // 活动增益不会覆盖已捕获参数
		end
	end

	// 首沿保留主增益全宽积。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_product <= 86'd0;               // 乘积历史清零
		end else begin
			reg_product <= enc_sum * enc_gain;  // 寄存完整的幅度缩放
		end
	end

	// 结果帧号随乘法进入流水。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_product_tag <= 16'd0;           // 首级帧号清零
		end else begin
			reg_product_tag <= i_return[79:64]; // 保留当前输入身份
		end
	end

	// 第一沿确认完整帧所有权。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_launch <= 1'd0;                // 无有效请求待推进
		end else begin
			flag_launch <= flag_current;        // 锁存主增益请求资格
		end
	end

	// 第二沿在扩展宽度上求绝对值。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_magnitude <= 87'd0;             // 幅度从零开始
		end else begin
			reg_magnitude <= reg_product[85] ? -enc_product : enc_product; // 保留最负数的绝对幅度
		end
	end

	// 原始符号不参与后续无符号舍入。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_polarity_tag <= 17'd0;          // 第二沿身份清零
		end else begin
			reg_polarity_tag <= {reg_product[85], reg_product_tag}; // 将补码符号与帧号同行
		end
	end

	// 中间有效历史可被原子命令撤销。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_waiting <= 5'd0;               // 取消全部待提交事务
		end else begin
			flag_waiting <= i_control[17:16] != 2'b00 ? 5'd0 : {flag_waiting[3:0], flag_launch}; // 清命令或推进输入资格
		end
	end

	// 第三沿加半个量化单位。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_biased <= 88'd0;                // 舍入偏置历史清零
		end else begin
			reg_biased <= wire_bias;            // 保存保护进位后的偏置幅度
		end
	end

	// 帧号和符号经过偏置边界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_bias_tag <= 17'd0;              // 第三沿身份清零
		end else begin
			reg_bias_tag <= reg_polarity_tag;   // 传递舍入前的身份
		end
	end

	// 第四沿完成固定小数位转换。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_rounded <= 78'd0;               // 舍入候选归零
		end else begin
			reg_rounded <= reg_biased[87:10];   // 去掉十位小数形成整数幅度
		end
	end

	// 舍入结果不改变原始符号。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_round_tag <= 17'd0;             // 舍入帧号清零
		end else begin
			reg_round_tag <= reg_bias_tag;      // 保持整数幅度所属身份
		end
	end

	// 第五沿分别判断正负满幅。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_bounds <= 2'd0;                // 初始不存在饱和候选
		end else begin
			flag_bounds <= {reg_rounded > {54'd0, 24'd8388608}, reg_rounded > {55'd0, 23'd8388607}}; // 寄存非对称补码上下界
		end
	end

	// 低位只有通过范围检查才可直接使用。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_low <= 24'd0;                   // 合法低位候选清零
		end else begin
			reg_low <= reg_rounded[23:0];       // 保存未越界时的整数低位
		end
	end

	// 补码身份进入限幅选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_limit_tag <= 17'd0;             // 限幅身份从零开始
		end else begin
			reg_limit_tag <= reg_round_tag;     // 推进上下界对应符号
		end
	end

	// 第六沿选择合法幅度或饱和值。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_selected <= 24'd0;              // 输出幅度候选清零
		end else begin
			reg_selected <= flag_bounds[flag_limit_sign] ? (flag_limit_sign ? 24'h800000 : 24'h7fffff) : reg_low; // 按原始符号采用正确满幅
		end
	end

	// 削波标记随结果进入提交边界。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_output_tag <= 18'd0;            // 最终身份清零
		end else begin
			reg_output_tag <= {flag_bounds[flag_limit_sign], reg_limit_tag[15:0], reg_limit_tag[16]}; // 锁定饱和事件与原始符号
		end
	end

	// 第七沿建立与音频同行的完成资格。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_completion <= 18'd0;            // 不存在完成通知
		end else begin
			reg_completion <= {flag_waiting[4], flag_waiting[4], reg_output_tag[16:1]}; // 登记重复有效码及输出帧号
		end
	end

endmodule
