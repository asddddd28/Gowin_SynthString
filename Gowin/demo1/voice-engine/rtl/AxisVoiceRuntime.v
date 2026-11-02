`timescale 1ns / 1ps
////////////////////////////////////English///////////////////////////////////////
// Company:         SynthString project
// Engineer:        Codex
// Create Date:     2026/11/02
// Design Name:     AxisVoiceRuntime
// Module Name:     AxisVoiceRuntime
// Description:     Resident operator state and exact last-request replay.
// Simulations:     sim/tb_voice_context.v
// Referrences:     spec/AxisVoiceRuntime_spec.md
// Dependencies:    AxisVoiceFabric
// Version:         V1.0
// Revision Date:   2026/11/02
// History:         2026/11/02 V1.0 Codex Create context runtime.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        SynthString project
// 开发人员:        Codex
// 创建日期:        2026年11月02日
// 设计名称:        AxisVoiceRuntime
// 模块名称:        AxisVoiceRuntime
// 模块说明:        参数驻留、独立状态与最近执行结果重放。
// 仿真工程:        sim/tb_voice_context.v
// 参考资料:        spec/AxisVoiceRuntime_spec.md
// 依赖文件:        AxisVoiceFabric
// 当前版本:        V1.0
// 修订日期:        2026年11月02日
// 修订历史:        2026年11月02日 V1.0 Codex 创建上下文运行时。

module AxisVoiceRuntime(
	// 全局信号：存储和计算处于同一时钟域。
	input i_axis_aclk,
	input i_axis_arstn,
	// AXI-Stream输入：高六十四位为上下文代号和执行序号。
	input [383:0] i_s_axis_tdata,
	input [31:0] i_s_axis_tuser,
	input [7:0] i_s_axis_tdest,
	input i_s_axis_tlast,
	input i_s_axis_tvalid,
	output o_s_axis_tready,
	// AXI-Stream输出：任务tag不承担去重身份，完整透传。
	output [127:0] o_m_axis_tdata,
	output [31:0] o_m_axis_tuser,
	output [7:0] o_m_axis_tdest,
	output o_m_axis_tlast,
	output o_m_axis_tvalid,
	input i_m_axis_tready,
	// 用户接口：区分实际运算、重放、拒绝与参数绑定。
	output [31:0] o_count_executed,
	output [31:0] o_count_replayed,
	output [31:0] o_count_rejected,
	output [31:0] o_count_bound
);
	localparam [3:0] ST_IDLE = 4'd0; // raw流保持并发，等待缓存请求取得所有权
	localparam [3:0] ST_LOAD = 4'd1; // 从上下文存储同步读取完整快照
	localparam [3:0] ST_CHECK = 4'd2; // 检查代号、序号、内容和格式
	localparam [3:0] ST_BIND = 4'd3; // 新绑定原子建立参数与初始状态
	localparam [3:0] ST_PREPARE = 4'd4; // 将驻留参数和实时操作数组装为核心输入
	localparam [3:0] ST_ISSUE = 4'd5; // 等待共享核心接受本次计算
	localparam [3:0] ST_WAIT = 4'd6; // 等待唯一缓存任务的核心返回
	localparam [3:0] ST_REPLY = 4'd7; // 持有完成结果，不再次修改状态
	reg [3:0] state_current = ST_IDLE; // 当前缓存访问阶段
	reg [3:0] state_next = ST_IDLE; // 下一缓存访问阶段

	// 不复位存储数据；两个有效位图防止复位后读到旧上下文。
	reg [319:0] mem_image [0:31]; // 不可变初始镜像，供精确BIND比较
	reg [34:0] mem_state [0:31]; // 每实例的当前相位/电平与包络阶段
	reg [23:0] mem_generation [0:31]; // 上下文重用时递增的所有者代号
	reg [2:0] mem_opcode [0:31]; // 该上下文绑定的基础核心类型
	reg [31:0] mem_sequence [0:31]; // 最近已提交的执行序号
	reg [65:0] mem_signature [0:31]; // 最近执行的精确实时输入，不用有碰撞的摘要
	reg [63:0] mem_result [0:31]; // 最近计算结果，重复包直接回放
	reg [31:0] reg_present = 32'd0; // 参数镜像有效位图
	reg [31:0] reg_history = 32'd0; // 最近执行历史有效位图

	reg [319:0] reg_image = 320'd0; // 当前命令读取的参数快照
	reg [34:0] reg_state = 35'd0; // 当前命令读取的递归状态
	reg [23:0] reg_generation = 24'd0; // 缓存中的所有者代号
	reg [2:0] reg_opcode = 3'd0; // 缓存中的核心选择
	reg [31:0] reg_sequence = 32'd0; // 缓存中的最近执行序号
	reg [65:0] reg_signature = 66'd0; // 缓存中的最近实时输入
	reg [63:0] reg_result = 64'd0; // 缓存中的最近运算结果
	reg flag_present = 1'b0; // 同步读出的绑定资格
	reg flag_history = 1'b0; // 同步读出的历史资格

	reg [319:0] reg_request_payload = 320'd0; // 调用参数或实时输入
	reg [7:0] reg_request_context = 8'd0; // 未截断的索引，先检查范围再访问
	reg [23:0] reg_request_generation = 24'd0; // 调用者宣称的上下文所有者
	reg [31:0] reg_request_sequence = 32'd0; // 本次执行身份，与传输tag分开
	reg [31:0] reg_request_tag = 32'd0; // 透明传输身份
	reg [7:0] reg_request_opcode = 8'd0; // 绑定、执行或观察操作
	reg [319:0] reg_execute_payload = 320'd0; // 已组装并保持的核心输入
	reg [127:0] reg_reply = 128'd0; // 缓存路径完成寄存器
	reg [7:0] dec_error = 8'd0; // 检查失败码，零表示允许操作
	reg flag_replay = 1'b0; // 精确匹配的BIND或RUN重发
	reg [127:0] dec_reply = 128'd0; // 检查阶段即可生成的结果
	reg [319:0] dec_execute_payload = 320'd0; // 当前状态与实时值组装
	reg [7:0] cnt_raw_pending = 8'd0; // raw包头与已消费完成之间的差额
	reg flag_raw_drain = 1'b0; // 多拍错误包尾部仍由原Fabric排空
	reg [31:0] cnt_executed_o = 32'd0; // 真正进入有效计算的数量
	reg [31:0] cnt_replayed_o = 32'd0; // 缓存完成数量
	reg [31:0] cnt_rejected_o = 32'd0; // 错误完成数量
	reg [31:0] cnt_bound_o = 32'd0; // 新镜像装载数量

	wire flag_context_select; // 本拍是受支持的完整缓存命令
	wire flag_context_accept; // 已取得上下文存储独占权
	wire flag_raw_input; // 此拍以原有ABI交给Fabric
	wire flag_raw_accept; // raw拍输入握手
	wire flag_raw_head; // 一个新的raw事务而非被排空尾拍
	wire flag_raw_return; // raw完成被外部消费
	wire flag_core_ready; // 共享Fabric可接纳请求
	wire flag_core_valid; // 共享Fabric持有计算结果
	wire flag_core_accept; // 缓存任务实际进入Fabric
	wire flag_core_complete; // 缓存任务结果被运行时接收
	wire [127:0] wire_core_result; // 共享Fabric结果和错误码
	wire [31:0] wire_core_tag; // raw响应仍使用Fabric原tag
	wire [7:0] wire_core_opcode; // raw响应的原目的端
	wire flag_core_last; // Fabric输出均为单拍完成
	wire [319:0] wire_fabric_payload; // raw和缓存执行共享一套计算单元
	wire [31:0] wire_fabric_tag; // 被选中请求的完整身份
	wire [7:0] wire_fabric_opcode; // 被选中请求的基础操作
	wire flag_fabric_valid; // 有效资格不依赖核心READY
	wire flag_fabric_last; // raw错误包边界保持原值
	wire flag_fabric_return_ready; // 缓存执行期间结果进入本地提交点

	assign flag_context_select = !flag_raw_drain && i_s_axis_tlast &&
		((i_s_axis_tdest >= 8'h80 && i_s_axis_tdest <= 8'h84) ||
		 i_s_axis_tdest == 8'h90 || i_s_axis_tdest == 8'h91); // 不让坏包尾部建立上下文
	assign flag_raw_input = state_current == ST_IDLE && !flag_context_select; // raw路径无需经过缓存状态机
	assign o_s_axis_tready = i_axis_arstn && state_current == ST_IDLE &&
		(flag_context_select ? cnt_raw_pending == 8'd0 : flag_core_ready); // 所有raw结果收齐后才能修改缓存
	assign flag_context_accept = i_s_axis_tvalid && o_s_axis_tready && flag_context_select;
	assign flag_raw_accept = i_s_axis_tvalid && o_s_axis_tready && !flag_context_select;
	assign flag_raw_head = flag_raw_accept && !flag_raw_drain;
	assign flag_raw_return = state_current == ST_IDLE && flag_core_valid && i_m_axis_tready;
	assign flag_core_accept = state_current == ST_ISSUE && flag_core_ready;
	assign flag_core_complete = state_current == ST_WAIT && flag_core_valid;
	assign wire_fabric_payload = state_current == ST_ISSUE ? reg_execute_payload : i_s_axis_tdata[319:0];
	assign wire_fabric_tag = state_current == ST_ISSUE ? reg_request_tag : i_s_axis_tuser;
	assign wire_fabric_opcode = state_current == ST_ISSUE ? {5'd0,reg_opcode} : i_s_axis_tdest;
	assign flag_fabric_valid = state_current == ST_ISSUE || (flag_raw_input && i_s_axis_tvalid);
	assign flag_fabric_last = state_current == ST_ISSUE ? 1'b1 : i_s_axis_tlast;
	assign flag_fabric_return_ready = state_current == ST_WAIT || (state_current == ST_IDLE && i_m_axis_tready);
	assign o_m_axis_tdata = state_current == ST_REPLY ? reg_reply : wire_core_result;
	assign o_m_axis_tuser = state_current == ST_REPLY ? reg_request_tag : wire_core_tag;
	assign o_m_axis_tdest = state_current == ST_REPLY ? reg_request_opcode : wire_core_opcode;
	assign o_m_axis_tlast = state_current == ST_REPLY ? 1'b1 : flag_core_last;
	assign o_m_axis_tvalid = state_current == ST_REPLY || (state_current == ST_IDLE && flag_core_valid);
	assign o_count_executed = cnt_executed_o;
	assign o_count_replayed = cnt_replayed_o;
	assign o_count_rejected = cnt_rejected_o;
	assign o_count_bound = cnt_bound_o;

	// 下一阶段只依赖已锁存请求和同步读取的上下文。
	always @(*) begin
		state_next = state_current;
		case(state_current)
			ST_IDLE:begin
				if(flag_context_accept)begin state_next = ST_LOAD; end
			end
			ST_LOAD:begin state_next = ST_CHECK; end
			ST_CHECK:begin
				if(dec_error != 8'd0 || flag_replay || reg_request_opcode == 8'h91)begin
					state_next = ST_REPLY;
				end else if(reg_request_opcode == 8'h90)begin
					state_next = ST_PREPARE;
				end else begin
					state_next = ST_BIND;
				end
			end
			ST_BIND:begin state_next = ST_REPLY; end
			ST_PREPARE:begin state_next = ST_ISSUE; end
			ST_ISSUE:begin
				if(flag_core_ready)begin state_next = ST_WAIT; end
			end
			ST_WAIT:begin
				if(flag_core_valid)begin state_next = ST_REPLY; end
			end
			ST_REPLY:begin
				if(i_m_axis_tready)begin state_next = ST_IDLE; end
			end
			default:begin state_next = ST_IDLE; end
		endcase
	end

	// 状态寄存与任务输出过程分离，复位取消未完成请求。
	always @(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(!i_axis_arstn)begin
			state_current <= ST_IDLE;
		end else begin
			state_current <= state_next;
		end
	end

	// raw路径只按包头记账；多拍错误包尾部不制造额外等待项。
	always @(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(!i_axis_arstn)begin
			cnt_raw_pending <= 8'd0;
			flag_raw_drain <= 1'b0;
		end else begin
			case({flag_raw_head,flag_raw_return})
				2'b10:begin cnt_raw_pending <= cnt_raw_pending + 8'd1; end
				2'b01:begin cnt_raw_pending <= cnt_raw_pending - 8'd1; end
				default:begin cnt_raw_pending <= cnt_raw_pending; end
			endcase
			if(flag_raw_accept)begin flag_raw_drain <= !i_s_axis_tlast; end
		end
	end

	// 捕获全部请求身份；后续改变输入不会影响正在检查的事务。
	always @(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(!i_axis_arstn)begin
			reg_request_payload <= 320'd0;
			reg_request_context <= 8'd0;
			reg_request_generation <= 24'd0;
			reg_request_sequence <= 32'd0;
			reg_request_tag <= 32'd0;
			reg_request_opcode <= 8'd0;
		end else if(flag_context_accept)begin
			reg_request_payload <= i_s_axis_tdata[319:0];
			reg_request_context <= i_s_axis_tdata[327:320];
			reg_request_generation <= i_s_axis_tdata[351:328];
			reg_request_sequence <= i_s_axis_tdata[383:352];
			reg_request_tag <= i_s_axis_tuser;
			reg_request_opcode <= i_s_axis_tdest;
		end
	end

	// 一拍同步读；非法索引的快照绝不进入写回，范围检查先于业务检查。
	always @(posedge i_axis_aclk)begin
		if(state_current == ST_LOAD)begin
			reg_image <= mem_image[reg_request_context[4:0]];
			reg_state <= mem_state[reg_request_context[4:0]];
			reg_generation <= mem_generation[reg_request_context[4:0]];
			reg_opcode <= mem_opcode[reg_request_context[4:0]];
			reg_sequence <= mem_sequence[reg_request_context[4:0]];
			reg_signature <= mem_signature[reg_request_context[4:0]];
			reg_result <= mem_result[reg_request_context[4:0]];
			flag_present <= reg_present[reg_request_context[4:0]];
			flag_history <= reg_history[reg_request_context[4:0]];
		end
	end

	// 重放仅比较执行身份与精确输入，不能以数值相同替代新采样计算。
	always @(*)begin
		dec_error = 8'd0;
		flag_replay = 1'b0;
		if(reg_request_context >= 8'd32)begin
			dec_error = 8'd3;
		end else if(reg_request_opcode >= 8'h80 && reg_request_opcode <= 8'h84)begin
			if(flag_present)begin
				if(reg_request_generation < reg_generation)begin
					dec_error = 8'd4;
				end else if(reg_request_generation == reg_generation)begin
					if(reg_request_payload != reg_image || reg_request_opcode[2:0] != reg_opcode)begin
						dec_error = 8'd5;
					end else begin
						flag_replay = 1'b1;
					end
				end
			end
		end else if(!flag_present)begin
			dec_error = 8'd3;
		end else if(reg_request_generation != reg_generation)begin
			dec_error = 8'd4;
		end else if(reg_request_opcode == 8'h91)begin
			if(reg_request_payload != 320'd0)begin dec_error = 8'd8; end
		end else if(reg_request_payload[319:66] != 254'd0)begin
			dec_error = 8'd8;
		end else if(!flag_history)begin
			if(reg_request_sequence != 32'd0)begin dec_error = 8'd7; end
		end else if(reg_request_sequence == reg_sequence)begin
			if(reg_request_payload[65:0] != reg_signature)begin
				dec_error = 8'd5;
			end else begin
				flag_replay = 1'b1;
			end
		end else if(reg_request_sequence < reg_sequence)begin
			dec_error = 8'd6;
		end else if(reg_request_sequence != reg_sequence + 32'd1)begin
			dec_error = 8'd7;
		end
	end

	// 不访问核心即可生成错误、重复响应与只读观察结果。
	always @(*)begin
		dec_reply = 128'd0;
		dec_reply[71:64] = dec_error;
		if(dec_error == 8'd0)begin
			if(flag_replay)begin
				dec_reply[72] = 1'b1;
				if(reg_request_opcode == 8'h90)begin dec_reply[63:0] = reg_result; end
			end else if(reg_request_opcode == 8'h91)begin
				dec_reply[34:0] = reg_state;
				dec_reply[73] = flag_history;
				dec_reply[78:76] = reg_opcode;
				dec_reply[111:80] = flag_history ? reg_sequence : 32'd0;
			end
		end
	end

	// 驻留参数保持不变，仅替换递归状态及本次实时操作数。
	always @(*)begin
		dec_execute_payload = reg_image;
		case(reg_opcode)
			3'd0:begin
				dec_execute_payload[31:0] = reg_state[31:0];
				dec_execute_payload[95:64] = reg_request_payload[31:0];
			end
			3'd1,3'd3:begin dec_execute_payload[31:0] = reg_state[31:0]; end
			3'd2:begin
				dec_execute_payload[31:0] = reg_request_payload[31:0];
				dec_execute_payload[95:64] = reg_request_payload[63:32];
			end
			3'd4:begin
				dec_execute_payload[31:0] = reg_state[31:0];
				dec_execute_payload[34:32] = reg_state[34:32];
				dec_execute_payload[36:35] = reg_request_payload[65:64];
			end
			default:begin dec_execute_payload = reg_image; end
		endcase
	end

	// 核心输入和输出均寄存，计算完成只在WAIT状态被消费一次。
	always @(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(!i_axis_arstn)begin
			reg_execute_payload <= 320'd0;
			reg_reply <= 128'd0;
		end else begin
			case(state_current)
				ST_CHECK:begin reg_reply <= dec_reply; end
				ST_PREPARE:begin reg_execute_payload <= dec_execute_payload; end
				ST_WAIT:begin
					if(flag_core_complete)begin reg_reply <= wire_core_result; end
				end
				default:begin
					reg_execute_payload <= reg_execute_payload;
					reg_reply <= reg_reply;
				end
			endcase
		end
	end

	// 缓存写入与核心完成原子对应；不逐项复位大块数据存储。
	always @(posedge i_axis_aclk)begin
		if(i_axis_arstn)begin
			if(state_current == ST_BIND)begin
				mem_image[reg_request_context[4:0]] <= reg_request_payload;
				mem_generation[reg_request_context[4:0]] <= reg_request_generation;
				mem_opcode[reg_request_context[4:0]] <= reg_request_opcode[2:0];
				mem_state[reg_request_context[4:0]] <= reg_request_opcode == 8'h84 ?
					reg_request_payload[34:0] : {3'd0,reg_request_payload[31:0]};
			end else if(flag_core_complete && wire_core_result[71:64] == 8'd0)begin
				if(reg_opcode != 3'd2)begin
					mem_state[reg_request_context[4:0]] <= reg_opcode == 3'd4 ?
						wire_core_result[34:0] : {3'd0,wire_core_result[31:0]};
				end
				mem_sequence[reg_request_context[4:0]] <= reg_request_sequence;
				mem_signature[reg_request_context[4:0]] <= reg_request_payload[65:0];
				mem_result[reg_request_context[4:0]] <= wire_core_result[63:0];
			end
		end
	end

	// 只有新代号绑定会清除执行历史；同代号重复BIND到不了此处。
	always @(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(!i_axis_arstn)begin
			reg_present <= 32'd0;
			reg_history <= 32'd0;
		end else if(state_current == ST_BIND)begin
			reg_present[reg_request_context[4:0]] <= 1'b1;
			reg_history[reg_request_context[4:0]] <= 1'b0;
		end else if(flag_core_complete && wire_core_result[71:64] == 8'd0)begin
			reg_history[reg_request_context[4:0]] <= 1'b1;
		end
	end

	// 计数用于证明重复输入没有再次消耗算力，所有计数自然回绕。
	always @(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(!i_axis_arstn)begin
			cnt_executed_o <= 32'd0;
			cnt_replayed_o <= 32'd0;
			cnt_rejected_o <= 32'd0;
			cnt_bound_o <= 32'd0;
		end else begin
			if(flag_core_accept || (flag_raw_head && i_s_axis_tlast && i_s_axis_tdest < 8'd5))begin
				cnt_executed_o <= cnt_executed_o + 32'd1;
			end
			if(state_current == ST_CHECK && dec_error == 8'd0 && flag_replay)begin
				cnt_replayed_o <= cnt_replayed_o + 32'd1;
			end
			if((state_current == ST_CHECK && dec_error != 8'd0) ||
				(flag_raw_return && wire_core_result[71:64] != 8'd0) ||
				(flag_core_complete && wire_core_result[71:64] != 8'd0))begin
				cnt_rejected_o <= cnt_rejected_o + 32'd1;
			end
			if(state_current == ST_BIND)begin cnt_bound_o <= cnt_bound_o + 32'd1; end
		end
	end

	// raw任务与缓存任务共用原有五个端点，不复制一套计算池。
	AxisVoiceFabric Fabric_Inst(
		.i_axis_aclk(i_axis_aclk),
		.i_axis_arstn(i_axis_arstn),
		.i_s_axis_tdata(wire_fabric_payload),
		.i_s_axis_tuser(wire_fabric_tag),
		.i_s_axis_tdest(wire_fabric_opcode),
		.i_s_axis_tlast(flag_fabric_last),
		.i_s_axis_tvalid(flag_fabric_valid),
		.o_s_axis_tready(flag_core_ready),
		.o_m_axis_tdata(wire_core_result),
		.o_m_axis_tuser(wire_core_tag),
		.o_m_axis_tdest(wire_core_opcode),
		.o_m_axis_tlast(flag_core_last),
		.o_m_axis_tvalid(flag_core_valid),
		.i_m_axis_tready(flag_fabric_return_ready)
	);
endmodule
