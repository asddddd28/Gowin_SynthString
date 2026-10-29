`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/13 01:28:13
// Design Name:     WavetablePairRead
// Module Name:     WavetablePairRead
// Description:     description/WavetablePairRead_Design.pdf
// Simulations:     testbench/vivado/2021.1/WavetablePairRead
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/13 01:28:13
// History:
// Time             Version     Revised by        Contents
// 2026/10/13       V1.0        Codex              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月13日
// 设计名称:        WavetablePairRead
// 模块名称:        WavetablePairRead
// 模块说明:        Description/WavetablePairRead_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/WavetablePairRead
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

module WavetablePairRead
(
	//-----------------全局信号-----------------//
	input i_clk,                                // 波表计算时钟
	input i_rstn,                               // 异步清空读取流水

	//-----------------用户接口-----------------//
	input i_valid,                              // 同拍描述符资格
	input [53:0]i_query,                        // 比例双帧资源银行波形相位的原子读取描述符
	input [31:0]i_pair_a,                       // 外部同步缓存前帧的本点及邻点
	input [31:0]i_pair_b,                       // 后帧已经排序的有符号十六位端点
	input [35:0]i_sine_pair,                    // 外部同步ROM的两个十八位正弦邻点
	output o_valid,                             // 第八采样沿完成的读取资格
	output signed [17:0]o_sample                // 两次负向取整后的音频
);

	//---------------配置参数区域---------------//
	localparam [63:0]SOURCE_MAP = 64'h4444446044332200; // 四位槽中保存源类别和锯齿选择

	//----------------寄存器信号----------------//
	reg [35:0]reg_linear = 36'd0;               // 方波及锯齿候选幅度
	reg [4:0]reg_route = 5'd0;                  // 当前源类别和资源标志
	reg signed [17:0]reg_triangle = 18'd0;      // 同拍三角候选幅度
	reg [15:0]reg_phase = 16'd0;                // 请求携带的周期内比例
	reg [15:0]reg_frame = 16'd0;                // 该请求的渐变坐标
	reg [35:0]reg_standard = 36'd0;             // 正弦或线性标准源的邻点
	reg [35:0]reg_custom_a = 36'd0;             // 前帧用户点或三角候选
	reg [35:0]reg_custom_b = 36'd0;             // 后帧用户点或确定的非表候选
	reg [4:0]reg_selected = 5'd0;               // 候选幅度配对的路由
	reg [15:0]reg_phase_align = 16'd0;          // 第二沿的周期内位置
	reg [15:0]reg_frame_align = 16'd0;          // 单帧时强制为零的帧权重
	reg [35:0]reg_points_a = 36'd0;             // 第三沿交付的前帧排序端点
	reg [35:0]reg_points_b = 36'd0;             // 第三沿交付的后帧排序端点
	reg [31:0]reg_fraction = 32'd0;             // 与最终端点同行的两个小数
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
	reg signed [35:0]reg_product_frame = 36'd0; // 完整帧间渐变乘积
	reg signed [17:0]reg_first_frame_delayed = 18'd0; // 帧间起点在乘法结束时的数值

	//-----------------标志信号-----------------//
	reg [2:0]flag_valid = 3'd0;                 // 三沿查表资格历史
	reg [4:0]flag_morph_valid = 5'd0;           // 五拍事务资格历史

	//-----------------编码信号-----------------//
	wire [5:0]enc_source;                       // 四位源槽的无乘法偏移
	wire signed [17:0]enc_positive;             // 非负折返幅度扩展符号
	wire [7:0]enc_fold_byte;                    // 同一反射位构成八位掩码组
	wire signed [16:0]enc_fold_mask;            // 折返符号自然扩展成全零或全一

	// 端点分量的补码解释
	wire signed [17:0]enc_first_a;              // 初始帧本点的有符号解释
	wire signed [17:0]enc_second_a;             // 初始帧后续幅度
	wire signed [17:0]enc_first_b;              // 目标帧基准点
	wire signed [17:0]enc_second_b;             // 目标帧周期末端点
	wire signed [16:0]enc_phase_fraction;       // 正的小数扩展符号位
	wire signed [16:0]enc_frame_fraction;       // 帧间坐标的正符号解释
	wire signed [19:0]enc_scaled_a;             // 前帧乘积移除十六位小数
	wire signed [19:0]enc_scaled_b;             // 后帧位移向负无穷取整
	wire signed [19:0]enc_scaled_frame;         // 帧间渐变的整数量

	//-----------------其他信号-----------------//
	// 波形折返和源描述符
	wire [16:0]wire_fold;                       // 三角折返幅度的十七个有效位
	wire signed [0:0]wire_reflect;              // 一位补码将折返位解释为零或负一
	wire signed [17:0]wire_triangle;            // 三角幅度的正负极性
	wire signed [17:0]wire_triangle_sample;     // 已寄存的三角候选
	wire [4:0]wire_route;                       // 同行类别与端点奇偶

	// 帧间差分
	wire signed [18:0]wire_delta_frame;         // 帧差直接进入全宽乘法

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
	assign enc_source = {i_query[34:32], i_query[36], 2'b00}; // 源槽步长为四位
	assign wire_reflect = i_query[30];          // 最高折返位用作一位补码
	assign enc_fold_byte = {wire_reflect, wire_reflect, wire_reflect, wire_reflect, wire_reflect, wire_reflect, wire_reflect, wire_reflect}; // 显式复制一个掩码字节
	assign enc_fold_mask = {wire_reflect, enc_fold_byte, enc_fold_byte}; // 两个字节和符号位组成十七位反射掩码
	assign wire_fold = i_query[29:13] ^ enc_fold_mask; // 半周期反射形成三角轮廓
	assign enc_positive = {1'b0, wire_fold};    // 折返值保持非负解释
	assign wire_triangle = i_query[31] ? -enc_positive : enc_positive; // 极性选择不占用硬件乘法器
	assign wire_triangle_sample = reg_triangle; // 恢复同行三角幅度
	assign wire_route = reg_route;              // 提取已经锁存的源资格
	assign enc_first_a = reg_points_a[35:18];   // 解释前帧基准补码
	assign enc_second_a = reg_points_a[17:0];   // 保留相邻幅度符号
	assign enc_first_b = reg_points_b[35:18];   // 取后帧当前周期点
	assign enc_second_b = reg_points_b[17:0];   // 读取渐变目标邻点
	assign valid_o = flag_morph_valid[4];       // 计算资格取最终历史位
	assign enc_phase_fraction = {1'b0, reg_phase_fraction}; // 周期比例保持非负
	assign enc_frame_fraction = {1'b0, reg_frame_sample}; // 帧间比例补零符号
	assign enc_scaled_a = reg_product_a[35:16]; // 前帧乘积取带符号高位
	assign enc_scaled_b = reg_product_b[35:16]; // 后帧周期位移截去小数
	assign enc_scaled_frame = reg_product_frame[35:16]; // 帧间乘积执行负向取整
	assign wire_delta_frame = reg_phase_b - reg_phase_a; // 帧间减法不提前截位
	assign wire_sum_a = reg_first_a_delayed + enc_scaled_a; // 还原前帧相位样值
	assign wire_sum_b = reg_first_b_delayed + enc_scaled_b; // 重建后帧当前相位
	assign wire_sum_frame = reg_first_frame_delayed + enc_scaled_frame; // 完成帧间幅度混合

	//---------------输出信号连线---------------//
	//用户接口
	assign o_valid = valid_o;                   // 提交八沿事务
	assign o_sample = sample_o;                 // 输出寄存的双线性音频

	//-------------输出信号处理区域-------------//
	//用户接口
	// 直接寄存帧间最终求和，省去仅复制结果的一拍。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			sample_o <= 18'd0;                  // 清空最终音频边界
		end else begin
			sample_o <= wire_sum_frame[17:0];   // 更新最终音频边界
		end
	end

	//-------------主要任务处理区域-------------//
	// 同沿保存方波与锯齿两个简单候选。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_linear <= 36'd0;                // 清零线性幅度
		end else begin
			reg_linear <= {(i_query[31] ? 18'b100000000000000001 : 18'b011111111111111111), {~i_query[31], i_query[30:14]}}; // 寄存线性幅度
		end
	end

	// 保存与外部存储查询同沿的路由。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_route <= 5'd0;                  // 清零源类别
		end else begin
			reg_route <= {i_query[22], i_query[37], SOURCE_MAP[enc_source+:3]}; // 寄存源类别
		end
	end

	// 三角候选在第一采样沿完成符号变换。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_triangle <= 18'd0;              // 清零三角候选
		end else begin
			reg_triangle <= wire_triangle[17:0]; // 寄存三角候选
		end
	end

	// 保存周期内十六位小数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_phase <= 16'd0;                 // 清零周期坐标
		end else begin
			reg_phase <= i_query[21:6];         // 寄存周期坐标
		end
	end

	// 捕获独立的帧坐标。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_frame <= 16'd0;                 // 清零渐变位置
		end else begin
			reg_frame <= i_query[53:38];        // 寄存渐变位置
		end
	end

	// 在正弦与两个线性波候选之间做注册选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_standard <= 36'd0;              // 清零标准邻点
		end else begin
			reg_standard <= wire_route[2:1] == 2'b00 ? i_sine_pair : (wire_route[0] ? {reg_linear[17:0], reg_linear[17:0]} : {reg_linear[35:18], reg_linear[35:18]}); // 寄存标准邻点
		end
	end

	// 选择前帧公开邻点或三角幅度候选。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_custom_a <= 36'd0;              // 清零前帧候选
		end else begin
			reg_custom_a <= wire_route[2:1] == 2'b11 ? {i_pair_a[31:16], 2'b00, i_pair_a[15:0], 2'b00} : {wire_triangle_sample, wire_triangle_sample}; // 寄存前帧候选
		end
	end

	// 后帧单帧资格关闭时不传播未知存储内容。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_custom_b <= 36'd0;              // 清零后帧候选
		end else begin
			reg_custom_b <= wire_route[1] ? (wire_route[3] ? {i_pair_b[31:16], 2'b00, i_pair_b[15:0], 2'b00} : 36'd0) : {wire_triangle_sample, wire_triangle_sample}; // 寄存后帧候选
		end
	end

	// 将路由推迟到候选幅度生成时刻。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_selected <= 5'd0;               // 清零源类别路由
		end else begin
			reg_selected <= wire_route;         // 寄存源类别路由
		end
	end

	// 周期比例跟随第二级候选。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_phase_align <= 16'd0;           // 清零延后相位
		end else begin
			reg_phase_align <= reg_phase;       // 寄存延后相位
		end
	end

	// 仅真正双帧用户源使用非零帧间权重。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_frame_align <= 16'd0;           // 清零有效帧比例
		end else begin
			reg_frame_align <= wire_route[3:1] == 3'b111 ? reg_frame : 16'd0; // 寄存有效帧比例
		end
	end

	// 最终前帧在标准源和表/三角源间选择。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_points_a <= 36'd0;              // 清零起始帧端点
		end else begin
			reg_points_a <= reg_selected[2] ? reg_custom_a : reg_standard; // 寄存起始帧端点
		end
	end

	// 后帧使用同一已寄存的源类别。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_points_b <= 36'd0;              // 清零目标帧幅度
		end else begin
			reg_points_b <= reg_selected[2] ? reg_custom_b : reg_standard; // 寄存目标帧幅度
		end
	end

	// 把两个小数锁定到第三沿端点。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_fraction <= 32'd0;              // 清零同行小数
		end else begin
			reg_fraction <= {reg_phase_align, reg_frame_align}; // 寄存同行小数
		end
	end

	// 每沿推进资格，复位清除所有在途读取。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_valid <= 3'd0;                 // 清零查表资格
		end else begin
			flag_valid <= {flag_valid[1:0], i_valid}; // 寄存查表资格
		end
	end

	// 移动事务标志，五个边沿后最高位成为输出资格。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_morph_valid <= 5'd0;           // 清空数据有效历史
		end else begin
			flag_morph_valid <= {flag_morph_valid[3:0], flag_valid[2]}; // 更新数据有效历史
		end
	end

	// 前帧两端点相减，十九位覆盖正负满幅距离。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_delta_a <= 19'd0;               // 清空前帧邻点差值保留符号扩展
		end else begin
			reg_delta_a <= enc_second_a - enc_first_a; // 更新前帧邻点差值保留符号扩展
		end
	end

	// 另一个周期独立保存邻点跨度，防止跨帧混用。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_delta_b <= 19'd0;               // 清空后帧周期跨度
		end else begin
			reg_delta_b <= enc_second_b - enc_first_b; // 更新后帧周期跨度
		end
	end

	// 保留输入基准供之后的乘积恢复绝对幅度。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_first_a <= 18'd0;               // 清空前帧起点跟随差值锁存
		end else begin
			reg_first_a <= enc_first_a;         // 更新前帧起点跟随差值锁存
		end
	end

	// 同步缓存另一帧相同相位的起始幅度。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_first_b <= 18'd0;               // 清空后帧基准样值
		end else begin
			reg_first_b <= enc_first_b;         // 更新后帧基准样值
		end
	end

	// 捕获无符号周期小数，下一拍扩展成正数。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_phase_fraction <= 16'd0;        // 清空两份周期差共同使用的相位小数
		end else begin
			reg_phase_fraction <= reg_fraction[31:16]; // 更新两份周期差共同使用的相位小数
		end
	end

	// 记住与四个样点同时进入的帧坐标。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_frame_start <= 16'd0;           // 清空帧间比例的第一拍
		end else begin
			reg_frame_start <= reg_fraction[15:0]; // 更新帧间比例的第一拍
		end
	end

	// 第二级进行十九乘十六位运算，不丢掉低位。
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

	// 十九位帧差乘正权重，保存全部三十六位结果。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_product_frame <= 36'd0;         // 清空完整帧间渐变乘积
		end else begin
			reg_product_frame <= wire_delta_frame * enc_frame_fraction; // 更新完整帧间渐变乘积
		end
	end

	// 将帧混合基准送到最终乘积的输出时刻。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_first_frame_delayed <= 18'd0;   // 清空帧间起点在乘法结束时的数值
		end else begin
			reg_first_frame_delayed <= reg_phase_a; // 更新帧间起点在乘法结束时的数值
		end
	end

endmodule
