`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         SynthString project
// Engineer:        Codex
//
// Create Date:     2026/11/02 00:00:00
// Design Name:     AxisVoiceFabric
// Module Name:     AxisVoiceFabric
// Description:     spec/AxisVoiceFabric_spec.md
// Simulations:     sim/tb_voice_fabric.v
//
// Referrences:
// File Format      File Name
// 1.Book           spec/AxisVoiceFabric_spec.md
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
// 设计名称:        AxisVoiceFabric
// 模块名称:        AxisVoiceFabric
// 模块说明:        spec/AxisVoiceFabric_spec.md
// 仿真工程:        sim/tb_voice_fabric.v
//
// 参考资料:
// 文件格式         文件名称
// 1.Book           spec/AxisVoiceFabric_spec.md
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

module AxisVoiceFabric
(
	//-----------------全局信号-----------------//
	input i_axis_aclk,                          // 共用计算时钟
	input i_axis_arstn,                         // 异步清除资格，外部同步释放

	//-------------AXI-Stream总线S--------------//
	//数据通道
	input [319:0]i_s_axis_tdata,                // 本次任务的状态与参数
	input [31:0]i_s_axis_tuser,                 // 透明事务编号
	input [7:0]i_s_axis_tdest,                  // 操作码路由

	//控制通道
	input i_s_axis_tvalid,                      // 源端有效资格
	input i_s_axis_tlast,                       // 完整任务必须为单拍包
	output o_s_axis_tready,                     // 入口可接纳

	//-------------AXI-Stream总线M--------------//
	//数据通道
	output [127:0]o_m_axis_tdata,               // 完成结果
	output [31:0]o_m_axis_tuser,                // 原请求编号
	output [7:0]o_m_axis_tdest,                 // 返回原操作码

	//控制通道
	input i_m_axis_tready,                      // 下游接受完成
	output o_m_axis_tvalid,                     // 完成资格
	output o_m_axis_tlast                       // 每个完成为单拍包
);

	//---------------状态参数区域---------------//
	localparam ST_RUN = 1'b0;                   // 接收独立任务包头
	localparam ST_DRAIN = 1'b1;                 // 排空不支持的多拍任务尾部

	//----------------状态机信号----------------//
	reg state_current = ST_RUN;                 // 输入包恢复状态
	reg state_next = 0;                         // 下一包恢复状态

	//----------------寄存器信号----------------//
	reg [319:0]reg_payload = 320'd0;            // 单个待分发快照
	reg [31:0]reg_tag = 32'd0;                  // 待分发事务身份
	reg [7:0]reg_opcode = 8'd0;                 // 目标算子编号
	reg [7:0]reg_error = 8'd0;                  // 错误包的完成状态
	reg [2:0]reg_priority = 3'd0;               // 下轮仲裁起始端口

	//-----------------标志信号-----------------//
	reg flag_head_valid = 1'b0;                 // 入口寄存占用
	reg flag_dispatch_ready = 0;                // 当前目的端是否可接受
	wire flag_dispatch;                         // 入口旧任务被目标接纳
	wire flag_head_accept;                      // 新包头完成握手
	wire flag_input_transfer;                   // 包头或排空拍完成握手
	wire flag_output_advance;                   // 返回寄存器可以替换
	reg flag_winner_valid = 0;                  // 本轮是否有返回可用

	//-----------------译码信号-----------------//
	reg [2:0]dec_winner = 0;                    // 当前首个可返回端口
	reg [167:0]dec_completion = 0;              // 选择出的opcode、tag与结果

	//-----------------其他信号-----------------//
	wire [4:0]wire_core_ready;                  // 五个计算核心的接纳条件
	wire [4:0]wire_core_valid;                  // 五个正常结果资格
	wire [319:0]wire_core_results;              // 五份六十四位结果
	wire [159:0]wire_core_tags;                 // 每个结果的完整身份
	wire [5:0]wire_lane_valid;                  // 正常核心及错误通道资格
	wire [5:0]wire_lane_ready;                  // 每次只允许一个结果被取走

	//-----------------输出信号-----------------//
	//AXI-Stream总线M--数据通道
	reg [127:0]m_axis_tdata_o = 128'd0;         // 外部停顿期间保持的完整返回
	reg [31:0]m_axis_tuser_o = 32'd0;           // 返回事务标识
	reg [7:0]m_axis_tdest_o = 8'd0;             // 返回所属算子

	//AXI-Stream总线M--控制通道
	reg m_axis_tvalid_o = 1'b0;                 // 返回寄存器资格

	//---------------其他信号连线---------------//
	//其他信号连线
	assign flag_output_advance = !m_axis_tvalid_o || i_m_axis_tready; // 队尾有空位时允许核心提交
	assign flag_input_transfer = i_s_axis_tvalid && o_s_axis_tready; // 外部所有权移交条件
	assign flag_head_accept = flag_input_transfer && (state_current == ST_RUN); // 仅包头建立一条运算
	assign flag_dispatch = flag_head_valid && flag_dispatch_ready; // 源槽被正常或错误端口取走
	assign wire_lane_valid = {flag_head_valid && reg_error != 8'd0, wire_core_valid}; // 错误与正常结果参与同一仲裁
	assign wire_lane_ready[0] = flag_output_advance && flag_winner_valid && dec_winner == 3'd0; // 只确认仲裁选中的返回端口
	assign wire_lane_ready[1] = flag_output_advance && flag_winner_valid && dec_winner == 3'd1; // 只确认仲裁选中的返回端口
	assign wire_lane_ready[2] = flag_output_advance && flag_winner_valid && dec_winner == 3'd2; // 只确认仲裁选中的返回端口
	assign wire_lane_ready[3] = flag_output_advance && flag_winner_valid && dec_winner == 3'd3; // 只确认仲裁选中的返回端口
	assign wire_lane_ready[4] = flag_output_advance && flag_winner_valid && dec_winner == 3'd4; // 只确认仲裁选中的返回端口
	assign wire_lane_ready[5] = flag_output_advance && flag_winner_valid && dec_winner == 3'd5; // 只确认仲裁选中的返回端口

	//---------------输出信号连线---------------//
	//AXI-Stream总线S--控制通道
	assign o_s_axis_tready = i_axis_arstn && ((state_current == ST_DRAIN) || !flag_head_valid || flag_dispatch_ready); // 排空拍不进入命令槽

	//AXI-Stream总线M--数据通道
	assign o_m_axis_tdata = m_axis_tdata_o;     // 返回结果与状态字
	assign o_m_axis_tuser = m_axis_tuser_o;     // 不截断调用者标签
	assign o_m_axis_tdest = m_axis_tdest_o;     // 反馈原目标编号

	//AXI-Stream总线M--控制通道
	assign o_m_axis_tvalid = m_axis_tvalid_o;   // 结果等待READY而不依赖READY产生
	assign o_m_axis_tlast = 1'b1;               // 每个完成响应独立成包

	//-------------输出信号处理区域-------------//
	//AXI-Stream总线M--数据通道
	// 输出寄存隔离组合仲裁，任何反压都不会改变可见包。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tdata_o <= 128'd0;
		end else if(flag_output_advance == 1'b1)begin
			if(flag_winner_valid == 1'b1)begin
				m_axis_tdata_o <= dec_completion[127:0];
			end
		end
	end

	// 输出寄存隔离组合仲裁，任何反压都不会改变可见包。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tdest_o <= 8'd0;
		end else if(flag_output_advance == 1'b1)begin
			if(flag_winner_valid == 1'b1)begin
				m_axis_tdest_o <= dec_completion[167:160];
			end
		end
	end

	// 输出寄存隔离组合仲裁，任何反压都不会改变可见包。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tuser_o <= 32'd0;
		end else if(flag_output_advance == 1'b1)begin
			if(flag_winner_valid == 1'b1)begin
				m_axis_tuser_o <= dec_completion[159:128];
			end
		end
	end

	//AXI-Stream总线M--控制通道
	// 输出寄存隔离组合仲裁，任何反压都不会改变可见包。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			m_axis_tvalid_o <= 1'b0;
		end else if(flag_output_advance == 1'b1)begin
			m_axis_tvalid_o <= flag_winner_valid;
		end
	end

	//----------------状态机区域----------------//
	// 不支持多拍任务时只返回一次格式错误，并丢弃该包剩余拍。
	always@(*)begin
		state_next = state_current;             // 没有握手时保持包状态
		case(state_current)
			ST_RUN:begin
				if(flag_input_transfer == 1'b1 && i_s_axis_tlast == 1'b0)begin
					state_next = ST_DRAIN;
				end
			end
			ST_DRAIN:begin
				if(flag_input_transfer == 1'b1 && i_s_axis_tlast == 1'b1)begin
					state_next = ST_RUN;
				end
			end
			default:begin
				state_next = ST_RUN;
			end
		endcase
	end

	// 复位同时取消正在排空的错误包。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			state_current <= ST_RUN;
		end else begin
			state_current <= state_next;
		end
	end

	//-------------主要任务处理区域-------------//
	// 源槽在有效握手时才被更新，计算核心阻塞时内容不变。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			flag_head_valid <= 1'b0;
		end else begin
			if(flag_head_accept == 1'b1)begin
				flag_head_valid <= 1'b1;
			end else if(flag_dispatch == 1'b1)begin
				flag_head_valid <= 1'b0;
			end
		end
	end

	// 源槽在有效握手时才被更新，计算核心阻塞时内容不变。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_error <= 8'd0;
		end else begin
			if(flag_head_accept == 1'b1)begin
				reg_error <= !i_s_axis_tlast ? 8'd2 : (i_s_axis_tdest > 8'd4 ? 8'd1 : 8'd0);
			end else begin
				reg_error <= reg_error;
			end
		end
	end

	// 源槽在有效握手时才被更新，计算核心阻塞时内容不变。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_opcode <= 8'd0;
		end else begin
			if(flag_head_accept == 1'b1)begin
				reg_opcode <= i_s_axis_tdest;
			end else begin
				reg_opcode <= reg_opcode;
			end
		end
	end

	// 源槽在有效握手时才被更新，计算核心阻塞时内容不变。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_payload <= 320'd0;
		end else begin
			if(flag_head_accept == 1'b1)begin
				reg_payload <= i_s_axis_tdata;
			end else begin
				reg_payload <= reg_payload;
			end
		end
	end

	// 源槽在有效握手时才被更新，计算核心阻塞时内容不变。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_tag <= 32'd0;
		end else begin
			if(flag_head_accept == 1'b1)begin
				reg_tag <= i_s_axis_tuser;
			end else begin
				reg_tag <= reg_tag;
			end
		end
	end

	// 分发READY按锁定后的目的端选择，未知操作走错误返回通道。
	always@(*)begin
		flag_dispatch_ready = 1'b0;
		if(reg_error != 8'd0)begin
			flag_dispatch_ready = wire_lane_ready[5];
		end else begin
			case(reg_opcode)
				8'd0:begin
					flag_dispatch_ready = wire_core_ready[0];
				end
				8'd1:begin
					flag_dispatch_ready = wire_core_ready[1];
				end
				8'd2:begin
					flag_dispatch_ready = wire_core_ready[2];
				end
				8'd3:begin
					flag_dispatch_ready = wire_core_ready[3];
				end
				8'd4:begin
					flag_dispatch_ready = wire_core_ready[4];
				end
				default:begin
					flag_dispatch_ready = 1'b0;
				end
			endcase
		end
	end

	// 旋转优先级在每次核心返回被缓存后前进。
	always@(*)begin
		dec_winner = 3'd0;
		case(reg_priority)
			3'd0:begin
				if(wire_lane_valid[0])begin
					dec_winner = 3'd0;
				end else if(wire_lane_valid[1])begin
					dec_winner = 3'd1;
				end else if(wire_lane_valid[2])begin
					dec_winner = 3'd2;
				end else if(wire_lane_valid[3])begin
					dec_winner = 3'd3;
				end else if(wire_lane_valid[4])begin
					dec_winner = 3'd4;
				end else if(wire_lane_valid[5])begin
					dec_winner = 3'd5;
				end
			end
			3'd1:begin
				if(wire_lane_valid[1])begin
					dec_winner = 3'd1;
				end else if(wire_lane_valid[2])begin
					dec_winner = 3'd2;
				end else if(wire_lane_valid[3])begin
					dec_winner = 3'd3;
				end else if(wire_lane_valid[4])begin
					dec_winner = 3'd4;
				end else if(wire_lane_valid[5])begin
					dec_winner = 3'd5;
				end else if(wire_lane_valid[0])begin
					dec_winner = 3'd0;
				end
			end
			3'd2:begin
				if(wire_lane_valid[2])begin
					dec_winner = 3'd2;
				end else if(wire_lane_valid[3])begin
					dec_winner = 3'd3;
				end else if(wire_lane_valid[4])begin
					dec_winner = 3'd4;
				end else if(wire_lane_valid[5])begin
					dec_winner = 3'd5;
				end else if(wire_lane_valid[0])begin
					dec_winner = 3'd0;
				end else if(wire_lane_valid[1])begin
					dec_winner = 3'd1;
				end
			end
			3'd3:begin
				if(wire_lane_valid[3])begin
					dec_winner = 3'd3;
				end else if(wire_lane_valid[4])begin
					dec_winner = 3'd4;
				end else if(wire_lane_valid[5])begin
					dec_winner = 3'd5;
				end else if(wire_lane_valid[0])begin
					dec_winner = 3'd0;
				end else if(wire_lane_valid[1])begin
					dec_winner = 3'd1;
				end else if(wire_lane_valid[2])begin
					dec_winner = 3'd2;
				end
			end
			3'd4:begin
				if(wire_lane_valid[4])begin
					dec_winner = 3'd4;
				end else if(wire_lane_valid[5])begin
					dec_winner = 3'd5;
				end else if(wire_lane_valid[0])begin
					dec_winner = 3'd0;
				end else if(wire_lane_valid[1])begin
					dec_winner = 3'd1;
				end else if(wire_lane_valid[2])begin
					dec_winner = 3'd2;
				end else if(wire_lane_valid[3])begin
					dec_winner = 3'd3;
				end
			end
			3'd5:begin
				if(wire_lane_valid[5])begin
					dec_winner = 3'd5;
				end else if(wire_lane_valid[0])begin
					dec_winner = 3'd0;
				end else if(wire_lane_valid[1])begin
					dec_winner = 3'd1;
				end else if(wire_lane_valid[2])begin
					dec_winner = 3'd2;
				end else if(wire_lane_valid[3])begin
					dec_winner = 3'd3;
				end else if(wire_lane_valid[4])begin
					dec_winner = 3'd4;
				end
			end
			default:begin
				dec_winner = 3'd0;
			end
		endcase
	end

	// 旋转优先级在每次核心返回被缓存后前进。
	always@(*)begin
		flag_winner_valid = 1'b0;
		case(reg_priority)
			3'd0:begin
				if(wire_lane_valid[0])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[1])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[2])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[3])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[4])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[5])begin
					flag_winner_valid = 1'b1;
				end
			end
			3'd1:begin
				if(wire_lane_valid[1])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[2])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[3])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[4])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[5])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[0])begin
					flag_winner_valid = 1'b1;
				end
			end
			3'd2:begin
				if(wire_lane_valid[2])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[3])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[4])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[5])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[0])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[1])begin
					flag_winner_valid = 1'b1;
				end
			end
			3'd3:begin
				if(wire_lane_valid[3])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[4])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[5])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[0])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[1])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[2])begin
					flag_winner_valid = 1'b1;
				end
			end
			3'd4:begin
				if(wire_lane_valid[4])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[5])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[0])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[1])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[2])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[3])begin
					flag_winner_valid = 1'b1;
				end
			end
			3'd5:begin
				if(wire_lane_valid[5])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[0])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[1])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[2])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[3])begin
					flag_winner_valid = 1'b1;
				end else if(wire_lane_valid[4])begin
					flag_winner_valid = 1'b1;
				end
			end
			default:begin
				flag_winner_valid = wire_lane_valid[0];
			end
		endcase
	end

	// 统一返回格式低六十四位是算子值，高字节为任务状态。
	always@(*)begin
		dec_completion = 168'd0;
		case(dec_winner)
			3'd0:begin
				dec_completion = {8'd0, wire_core_tags[31:0], 64'd0, wire_core_results[63:0]};
			end
			3'd1:begin
				dec_completion = {8'd1, wire_core_tags[63:32], 64'd0, wire_core_results[127:64]};
			end
			3'd2:begin
				dec_completion = {8'd2, wire_core_tags[95:64], 64'd0, wire_core_results[191:128]};
			end
			3'd3:begin
				dec_completion = {8'd3, wire_core_tags[127:96], 64'd0, wire_core_results[255:192]};
			end
			3'd4:begin
				dec_completion = {8'd4, wire_core_tags[159:128], 64'd0, wire_core_results[319:256]};
			end
			default:begin
				dec_completion = {reg_opcode, reg_tag, 56'd0, reg_error, 64'd0};
			end
		endcase
	end

	// 输出寄存隔离组合仲裁，任何反压都不会改变可见包。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_priority <= 3'd0;
		end else if(flag_output_advance == 1'b1)begin
			if(flag_winner_valid == 1'b1)begin
				reg_priority <= dec_winner == 3'd5 ? 3'd0 : dec_winner + 3'd1;
			end
		end
	end

	//--------------模块实例化区域--------------//
	// AxisPhasePm独立保存流水快照，持久声部状态由调用者管理。
	AxisPhasePm Core0_Inst(
		.i_axis_aclk(i_axis_aclk),              // i_axis_aclk端口连接i_axis_aclk
		.i_axis_arstn(i_axis_arstn),            // i_axis_arstn端口连接i_axis_arstn
		.i_s_axis_tdata(reg_payload[127:0]),    // i_s_axis_tdata端口连接reg_payload[127:0]
		.i_s_axis_tuser(reg_tag),               // i_s_axis_tuser端口连接reg_tag
		.i_s_axis_tvalid(flag_head_valid && reg_error == 8'd0 && reg_opcode == 8'd0), // i_s_axis_tvalid端口连接flag_head_valid && reg_error == 8'd0 && reg_opcode == 8'd0
		.o_s_axis_tready(wire_core_ready[0]),   // o_s_axis_tready端口连接wire_core_ready[0]
		.o_m_axis_tdata(wire_core_results[63:0]), // o_m_axis_tdata端口连接wire_core_results[63:0]
		.o_m_axis_tuser(wire_core_tags[31:0]),  // o_m_axis_tuser端口连接wire_core_tags[31:0]
		.o_m_axis_tvalid(wire_core_valid[0]),   // o_m_axis_tvalid端口连接wire_core_valid[0]
		.i_m_axis_tready(wire_lane_ready[0])    // i_m_axis_tready端口连接wire_lane_ready[0]
	);

	// AxisEnvelopeSegment独立保存流水快照，持久声部状态由调用者管理。
	AxisEnvelopeSegment Core1_Inst(
		.i_axis_aclk(i_axis_aclk),              // i_axis_aclk端口连接i_axis_aclk
		.i_axis_arstn(i_axis_arstn),            // i_axis_arstn端口连接i_axis_arstn
		.i_s_axis_tdata(reg_payload[127:0]),    // i_s_axis_tdata端口连接reg_payload[127:0]
		.i_s_axis_tuser(reg_tag),               // i_s_axis_tuser端口连接reg_tag
		.i_s_axis_tvalid(flag_head_valid && reg_error == 8'd0 && reg_opcode == 8'd1), // i_s_axis_tvalid端口连接flag_head_valid && reg_error == 8'd0 && reg_opcode == 8'd1
		.o_s_axis_tready(wire_core_ready[1]),   // o_s_axis_tready端口连接wire_core_ready[1]
		.o_m_axis_tdata(wire_core_results[127:64]), // o_m_axis_tdata端口连接wire_core_results[127:64]
		.o_m_axis_tuser(wire_core_tags[63:32]), // o_m_axis_tuser端口连接wire_core_tags[63:32]
		.o_m_axis_tvalid(wire_core_valid[1]),   // o_m_axis_tvalid端口连接wire_core_valid[1]
		.i_m_axis_tready(wire_lane_ready[1])    // i_m_axis_tready端口连接wire_lane_ready[1]
	);

	// AxisGainMix独立保存流水快照，持久声部状态由调用者管理。
	AxisGainMix Core2_Inst(
		.i_axis_aclk(i_axis_aclk),              // i_axis_aclk端口连接i_axis_aclk
		.i_axis_arstn(i_axis_arstn),            // i_axis_arstn端口连接i_axis_arstn
		.i_s_axis_tdata(reg_payload[127:0]),    // i_s_axis_tdata端口连接reg_payload[127:0]
		.i_s_axis_tuser(reg_tag),               // i_s_axis_tuser端口连接reg_tag
		.i_s_axis_tvalid(flag_head_valid && reg_error == 8'd0 && reg_opcode == 8'd2), // i_s_axis_tvalid端口连接flag_head_valid && reg_error == 8'd0 && reg_opcode == 8'd2
		.o_s_axis_tready(wire_core_ready[2]),   // o_s_axis_tready端口连接wire_core_ready[2]
		.o_m_axis_tdata(wire_core_results[191:128]), // o_m_axis_tdata端口连接wire_core_results[191:128]
		.o_m_axis_tuser(wire_core_tags[95:64]), // o_m_axis_tuser端口连接wire_core_tags[95:64]
		.o_m_axis_tvalid(wire_core_valid[2]),   // o_m_axis_tvalid端口连接wire_core_valid[2]
		.i_m_axis_tready(wire_lane_ready[2])    // i_m_axis_tready端口连接wire_lane_ready[2]
	);

	// AxisNoiseStep独立保存流水快照，持久声部状态由调用者管理。
	AxisNoiseStep Core3_Inst(
		.i_axis_aclk(i_axis_aclk),              // i_axis_aclk端口连接i_axis_aclk
		.i_axis_arstn(i_axis_arstn),            // i_axis_arstn端口连接i_axis_arstn
		.i_s_axis_tdata(reg_payload[127:0]),    // i_s_axis_tdata端口连接reg_payload[127:0]
		.i_s_axis_tuser(reg_tag),               // i_s_axis_tuser端口连接reg_tag
		.i_s_axis_tvalid(flag_head_valid && reg_error == 8'd0 && reg_opcode == 8'd3), // i_s_axis_tvalid端口连接flag_head_valid && reg_error == 8'd0 && reg_opcode == 8'd3
		.o_s_axis_tready(wire_core_ready[3]),   // o_s_axis_tready端口连接wire_core_ready[3]
		.o_m_axis_tdata(wire_core_results[255:192]), // o_m_axis_tdata端口连接wire_core_results[255:192]
		.o_m_axis_tuser(wire_core_tags[127:96]), // o_m_axis_tuser端口连接wire_core_tags[127:96]
		.o_m_axis_tvalid(wire_core_valid[3]),   // o_m_axis_tvalid端口连接wire_core_valid[3]
		.i_m_axis_tready(wire_lane_ready[3])    // i_m_axis_tready端口连接wire_lane_ready[3]
	);

	// AxisEnvelopeMulti独立保存流水快照，持久声部状态由调用者管理。
	AxisEnvelopeMulti Core4_Inst(
		.i_axis_aclk(i_axis_aclk),              // i_axis_aclk端口连接i_axis_aclk
		.i_axis_arstn(i_axis_arstn),            // i_axis_arstn端口连接i_axis_arstn
		.i_s_axis_tdata(reg_payload[319:0]),    // i_s_axis_tdata端口连接reg_payload[319:0]
		.i_s_axis_tuser(reg_tag),               // i_s_axis_tuser端口连接reg_tag
		.i_s_axis_tvalid(flag_head_valid && reg_error == 8'd0 && reg_opcode == 8'd4), // i_s_axis_tvalid端口连接flag_head_valid && reg_error == 8'd0 && reg_opcode == 8'd4
		.o_s_axis_tready(wire_core_ready[4]),   // o_s_axis_tready端口连接wire_core_ready[4]
		.o_m_axis_tdata(wire_core_results[319:256]), // o_m_axis_tdata端口连接wire_core_results[319:256]
		.o_m_axis_tuser(wire_core_tags[159:128]), // o_m_axis_tuser端口连接wire_core_tags[159:128]
		.o_m_axis_tvalid(wire_core_valid[4]),   // o_m_axis_tvalid端口连接wire_core_valid[4]
		.i_m_axis_tready(wire_lane_ready[4])    // i_m_axis_tready端口连接wire_lane_ready[4]
	);

endmodule
