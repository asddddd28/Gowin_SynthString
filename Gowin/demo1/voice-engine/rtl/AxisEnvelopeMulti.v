`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         SynthString project
// Engineer:        Codex
//
// Create Date:     2026/11/02 00:00:00
// Design Name:     AxisEnvelopeMulti
// Module Name:     AxisEnvelopeMulti
// Description:     spec/AxisEnvelopeMulti_spec.md
// Simulations:     sim/tb_voice_fabric.v
//
// Referrences:
// File Format      File Name
// 1.Book           spec/AxisEnvelopeMulti_spec.md
//
// Dependencies:
// Module Name      Version
// See sources.f
// sources.f
//
// Version:         V1.0
// Revision Date:   2026/11/02 00:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/11/02       V1.0        Codex              Create subsystem.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        SynthString project
// 开发人员:        Codex
//
// 创建日期:        2026年11月02日
// 设计名称:        AxisEnvelopeMulti
// 模块名称:        AxisEnvelopeMulti
// 模块说明:        spec/AxisEnvelopeMulti_spec.md
// 仿真工程:        sim/tb_voice_fabric.v
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           spec/AxisEnvelopeMulti_spec.md
//
// 依赖文件:
// 模块名称         版本
// See sources.f
// sources.f
//
// 当前版本:        V1.0
// 修订日期:        2026年11月02日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年11月02日   V1.0        Codex              创建子系统

module AxisEnvelopeMulti
(
	//-----------------全局信号-----------------//
	input i_axis_aclk,                          // 共用计算时钟
	input i_axis_arstn,                         // 异步清除资格，外部同步释放

	//-------------AXI-Stream总线S--------------//
	//数据通道
	input [319:0]i_s_axis_tdata,                // 本次任务的状态与参数
	input [31:0]i_s_axis_tuser,                 // 透明事务编号

	//控制通道
	input i_s_axis_tvalid,                      // 源端有效资格
	output o_s_axis_tready,                     // 入口可接纳

	//-------------AXI-Stream总线M--------------//
	//数据通道
	output [63:0]o_m_axis_tdata,                // 完成结果
	output [31:0]o_m_axis_tuser,                // 原请求编号

	//控制通道
	input i_m_axis_tready,                      // 下游接受完成
	output o_m_axis_tvalid                      // 完成资格
);

	//--------------模块实例化信号--------------//
	//AxisEnvelopeSegment--AXI-Stream总线M--数据通道
	wire [63:0]wire_segment_result;             // 段电平与到达标志
	wire [31:0]wire_segment_user;               // 同行的原事务标签

	//----------------寄存器信号----------------//
	reg [127:0]reg_segment = 128'd0;            // 已锁存的段运算快照
	reg [31:0]reg_identity = 32'd0;             // 入口标签
	reg [4:0]reg_metadata = 5'd0;               // 入口阶段与诊断
	reg [4:0]reg_meta_first = 5'd0;             // 算术差分沿的阶段信息
	reg [4:0]reg_meta_second = 5'd0;            // 绝对距离沿的阶段信息
	reg [4:0]reg_meta_third = 5'd0;             // 候选计算沿的阶段信息
	reg [4:0]reg_meta_fourth = 5'd0;            // 段返回沿的阶段信息

	//-----------------标志信号-----------------//
	reg flag_bad_stage = 0;                     // 无法解释的外部阶段状态
	reg flag_bypass = 0;                        // 保持和闲置阶段不报告运动完成
	reg flag_input_valid = 1'b0;                // 段核心之前的弹性缓冲
	wire flag_input_advance;                    // 入口可替换条件
	wire flag_segment_ready;                    // 段核心入口信用
	wire flag_segment_valid;                    // 段核心结果有效
	wire flag_output_advance;                   // 终端结果寄存器可以替换

	//-----------------译码信号-----------------//
	// 入口解码只选择本采样需要的一段。
	reg [2:0]dec_stage = 0;                     // 事件作用后的阶段
	reg [31:0]dec_level = 0;                    // 重触发规则作用后的起点
	reg [31:0]dec_target = 0;                   // 所选分段的目的电平
	reg [31:0]dec_step = 0;                     // 所选分段的非负步进量
	reg [2:0]dec_next_stage = 0;                // 完成本步后交还调用者的阶段

	//-----------------输出信号-----------------//
	//AXI-Stream总线M--数据通道
	reg [63:0]m_axis_tdata_o = 64'd0;           // 最终包络状态及诊断
	reg [31:0]m_axis_tuser_o = 32'd0;           // 返回所属事务

	//AXI-Stream总线M--控制通道
	reg m_axis_tvalid_o = 1'b0;                 // 已封装完成的包络结果

	//---------------其他信号连线---------------//
	//其他信号连线
	assign flag_input_advance = !flag_input_valid || flag_segment_ready; // 空入口或旧任务移交时可接纳
	assign flag_output_advance = !m_axis_tvalid_o || i_m_axis_tready; // 输出反压冻结完成封装

	//---------------输出信号连线---------------//
	//AXI-Stream总线S--控制通道
	assign o_s_axis_tready = i_axis_arstn && flag_input_advance; // 复位期间不转移输入所有权

	//AXI-Stream总线M--数据通道
	assign o_m_axis_tdata = m_axis_tdata_o;     // 返回电平和阶段
	assign o_m_axis_tuser = m_axis_tuser_o;     // 保留完整标签

	//AXI-Stream总线M--控制通道
	assign o_m_axis_tvalid = m_axis_tvalid_o;   // 有效位不依赖下游READY

	//-------------输出信号处理区域-------------//
	//AXI-Stream总线M--数据通道
	// 结果槽与下游握手，内部段完成并不等于外部已经消费。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tdata_o <= 64'd0;
		end else if(flag_output_advance == 1'b1)begin
			m_axis_tdata_o <= {25'd0,reg_meta_fourth[3],wire_segment_result[33] && !reg_meta_fourth[4],
			wire_segment_result[32] && !reg_meta_fourth[4],dec_next_stage != 3'd0,dec_next_stage,wire_segment_result[31:0]}; // 原子封装状态
		end
	end

	// 结果槽与下游握手，内部段完成并不等于外部已经消费。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tuser_o <= 32'd0;
		end else if(flag_output_advance == 1'b1)begin
			m_axis_tuser_o <= wire_segment_user; // 带回原标签
		end
	end

	//AXI-Stream总线M--控制通道
	// 结果槽与下游握手，内部段完成并不等于外部已经消费。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tvalid_o <= 1'b0;
		end else if(flag_output_advance == 1'b1)begin
			m_axis_tvalid_o <= flag_segment_valid; // 缓存已完成段的资格
		end
	end

	//-------------主要任务处理区域-------------//
	// NoteOn/Kill可恢复非法旧阶段，NoteOff只作用于活动包络。
	always@(*)begin
		dec_stage = i_s_axis_tdata[34:32];      // 默认继续调用者传入的阶段
		case(i_s_axis_tdata[36:35])
			2'd1:begin
				dec_stage = 3'd1;               // 起音从首段执行
			end
			2'd3:begin
				dec_stage = 3'd0;               // 强制停止取消所有后续段
			end
			default:begin
				if(i_s_axis_tdata[34:32] > 3'd5)begin
					dec_stage = 3'd0;           // 非法阶段停止推进并返回诊断
				end else if(i_s_axis_tdata[36:35] == 2'd2 && i_s_axis_tdata[34:32] != 3'd0)begin
					dec_stage = 3'd5;           // 释音从当前电平进入第四段
				end
			end
		endcase
	end

	// 硬重触发与强制停止使用显式第四电平，其余事件保持连续。
	always@(*)begin
		dec_level = i_s_axis_tdata[31:0];
		case(i_s_axis_tdata[36:35])
			2'd1:begin
				if(i_s_axis_tdata[37])begin
					dec_level = i_s_axis_tdata[191:160];
				end
			end
			2'd3:begin
				dec_level = i_s_axis_tdata[191:160];
			end
			default:begin
				dec_level = i_s_axis_tdata[31:0];
			end
		endcase
	end

	// 恢复事件抹去旧阶段错误，普通Tick与NoteOff返回诊断。
	always@(*)begin
		flag_bad_stage = i_s_axis_tdata[34:32] > 3'd5;
		case(i_s_axis_tdata[36:35])
			2'd1,2'd3:begin
				flag_bad_stage = 1'b0;
			end
			default:begin
				flag_bad_stage = i_s_axis_tdata[34:32] > 3'd5;
			end
		endcase
	end

	// 阶段只选择对应目标，不在同一任务中迭代下一段。
	always@(*)begin
		dec_target = dec_level;                 // 闲置和保持返回原值
		case(dec_stage)
			3'd1:begin
				dec_target = i_s_axis_tdata[95:64];
			end
			3'd2:begin
				dec_target = i_s_axis_tdata[127:96];
			end
			3'd3:begin
				dec_target = i_s_axis_tdata[159:128];
			end
			3'd5:begin
				dec_target = i_s_axis_tdata[191:160];
			end
			default:begin
				dec_target = dec_level;
			end
		endcase
	end

	// 非运动阶段送零步长，运动阶段使用各自的无符号增量。
	always@(*)begin
		dec_step = 32'd0;
		case(dec_stage)
			3'd1:begin
				dec_step = i_s_axis_tdata[223:192];
			end
			3'd2:begin
				dec_step = i_s_axis_tdata[255:224];
			end
			3'd3:begin
				dec_step = i_s_axis_tdata[287:256];
			end
			3'd5:begin
				dec_step = i_s_axis_tdata[319:288];
			end
			default:begin
				dec_step = 32'd0;
			end
		endcase
	end

	// 闲置和保持不发布到达/停滞事件。
	always@(*)begin
		flag_bypass = 1'b1;
		case(dec_stage)
			3'd1,3'd2,3'd3,3'd5:begin
				flag_bypass = 1'b0;
			end
			default:begin
				flag_bypass = 1'b1;
			end
		endcase
	end

	// 入口寄存隔离外部包的复杂阶段选择。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			flag_input_valid <= 1'b0;
		end else if(flag_input_advance == 1'b1)begin
			flag_input_valid <= i_s_axis_tvalid; // 空拍传播为无效入口
		end
	end

	// 入口寄存隔离外部包的复杂阶段选择。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_identity <= 32'd0;
		end else if(flag_input_advance == 1'b1)begin
			reg_identity <= i_s_axis_tuser;     // 标签与段参数同时寄存
		end
	end

	// 入口寄存隔离外部包的复杂阶段选择。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_metadata <= 5'd0;
		end else if(flag_input_advance == 1'b1)begin
			reg_metadata <= {flag_bypass, flag_bad_stage, dec_stage}; // 记录回写规则
		end
	end

	// 入口寄存隔离外部包的复杂阶段选择。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_segment <= 128'd0;
		end else if(flag_input_advance == 1'b1)begin
			reg_segment <= {32'd0, dec_step, dec_target, dec_level}; // 锁定本段的全部数值
		end
	end

	// 四级元数据与段核心的全局推进使能完全一致。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_meta_first <= 5'd0;
		end else if(flag_segment_ready == 1'b1)begin
			reg_meta_first <= reg_metadata;     // 首级对应本次段请求
		end
	end

	// 四级元数据与段核心的全局推进使能完全一致。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_meta_fourth <= 5'd0;
		end else if(flag_segment_ready == 1'b1)begin
			reg_meta_fourth <= reg_meta_third;  // 对齐段结果输出
		end
	end

	// 四级元数据与段核心的全局推进使能完全一致。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_meta_second <= 5'd0;
		end else if(flag_segment_ready == 1'b1)begin
			reg_meta_second <= reg_meta_first;  // 对齐距离绝对值
		end
	end

	// 四级元数据与段核心的全局推进使能完全一致。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_meta_third <= 5'd0;
		end else if(flag_segment_ready == 1'b1)begin
			reg_meta_third <= reg_meta_second;  // 对齐候选步进
		end
	end

	// 每次任务最多切换一次阶段，避免等值目标造成组合环。
	always@(*)begin
		dec_next_stage = reg_meta_fourth[2:0];  // 默认保留当前阶段
		if(wire_segment_result[32] && !reg_meta_fourth[4])begin
			case(reg_meta_fourth[2:0])
				3'd1:begin
					dec_next_stage = 3'd2;
				end
				3'd2:begin
					dec_next_stage = 3'd3;
				end
				3'd3:begin
					dec_next_stage = 3'd4;
				end
				3'd5:begin
					dec_next_stage = 3'd0;
				end
				default:begin
					dec_next_stage = reg_meta_fourth[2:0];
				end
			endcase
		end
	end

	//--------------模块实例化区域--------------//
	// 基础段核心保持数值语义，外层只负责事件与阶段。
	AxisEnvelopeSegment Segment_Inst(
		.i_axis_aclk(i_axis_aclk),              // i_axis_aclk端口连接i_axis_aclk
		.i_axis_arstn(i_axis_arstn),            // i_axis_arstn端口连接i_axis_arstn
		.i_s_axis_tdata(reg_segment),           // i_s_axis_tdata端口连接reg_segment
		.i_s_axis_tuser(reg_identity),          // i_s_axis_tuser端口连接reg_identity
		.i_s_axis_tvalid(flag_input_valid),     // i_s_axis_tvalid端口连接flag_input_valid
		.o_s_axis_tready(flag_segment_ready),   // o_s_axis_tready端口连接flag_segment_ready
		.o_m_axis_tdata(wire_segment_result),   // o_m_axis_tdata端口连接wire_segment_result
		.o_m_axis_tuser(wire_segment_user),     // o_m_axis_tuser端口连接wire_segment_user
		.o_m_axis_tvalid(flag_segment_valid),   // o_m_axis_tvalid端口连接flag_segment_valid
		.i_m_axis_tready(flag_output_advance)   // i_m_axis_tready端口连接flag_output_advance
	);

endmodule
