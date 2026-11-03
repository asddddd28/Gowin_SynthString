`timescale 1ns / 1ps
////////////////////////////////////English///////////////////////////////////////
// Company:         SynthString project
// Engineer:        Codex
// Create Date:     2026/11/02
// Design Name:     AxiVoiceEndpoint
// Module Name:     AxiVoiceEndpoint
// Description:     AXI4 memory-mapped command and completion queues for Voice Engine.
// Simulations:     sim/tb_axi_voice_endpoint.v
// Referrences:     spec/AxiVoiceEndpoint_spec.md
// Dependencies:    See sources.f
// Version:         V1.0
// Revision Date:   2026/11/02
// History:
// 2026/11/02       V1.0        Codex              Create subsystem.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        SynthString project
// 开发人员:        Codex
// 创建日期:        2026年11月02日
// 设计名称:        AxiVoiceEndpoint
// 模块名称:        AxiVoiceEndpoint
// 模块说明:        AXI4 memory-mapped command and completion queues for Voice Engine.
// 仿真工程:        sim/tb_axi_voice_endpoint.v
// 参考资料:        spec/AxiVoiceEndpoint_spec.md
// 依赖文件:        sources.f
// 当前版本:        V1.0
// 修订日期:        2026年11月02日
// 修订历史:
// 2026年11月02日   V1.0        Codex              创建子系统

module AxiVoiceEndpoint #(
	parameter LEGACY_ENABLE=1,
	parameter C_TOUCH_ENABLE=0,parameter C_FX_ENABLE=1,
	parameter C_DELAY_ADDR_BITS=15
)(
	    input [17:0] i_touch_gain,input [31:0] i_touch_pitch,input [19:0] i_touch_cutoff,input i_touch_cutoff_active,
input i_axi_aclk, // AXI与内部计算共用时钟
	input i_axi_arstn, // 清除总线事务与队列
	input [3:0]i_s_axi_awid, // 请求awid
	input [15:0]i_s_axi_awaddr, // 请求awaddr
	input [7:0]i_s_axi_awlen, // 请求awlen
	input [2:0]i_s_axi_awsize, // 请求awsize
	input [1:0]i_s_axi_awburst, // 请求awburst
	input i_s_axi_awlock, // 请求awlock
	input i_s_axi_awvalid, // 请求awvalid
	output o_s_axi_awready, // 接纳aw通道
	input [3:0]i_s_axi_arid, // 请求arid
	input [15:0]i_s_axi_araddr, // 请求araddr
	input [7:0]i_s_axi_arlen, // 请求arlen
	input [2:0]i_s_axi_arsize, // 请求arsize
	input [1:0]i_s_axi_arburst, // 请求arburst
	input i_s_axi_arlock, // 请求arlock
	input i_s_axi_arvalid, // 请求arvalid
	output o_s_axi_arready, // 接纳ar通道
	input [31:0]i_s_axi_wdata, // AXI wdata事务字段
	input [3:0]i_s_axi_wstrb, // AXI wstrb事务字段
	input i_s_axi_wlast, // AXI wlast事务字段
	input i_s_axi_wvalid, // AXI wvalid事务字段
	output o_s_axi_wready, // AXI wready事务字段
	output [3:0]o_s_axi_bid, // AXI bid事务字段
	output [1:0]o_s_axi_bresp, // AXI bresp事务字段
	output o_s_axi_bvalid, // AXI bvalid事务字段
	input i_s_axi_bready, // AXI bready事务字段
	output [3:0]o_s_axi_rid, // AXI rid事务字段
	output [31:0]o_s_axi_rdata, // AXI rdata事务字段
	output [1:0]o_s_axi_rresp, // AXI rresp事务字段
	output o_s_axi_rlast, // AXI rlast事务字段
	output o_s_axi_rvalid, // AXI rvalid事务字段
	input i_s_axi_rready, // AXI rready事务字段
	output o_pcm_valid, // 独立音频队列，主机停止读完成也不会冻结渲染
	input i_pcm_ready, // 下游音频消费者
	output [63:0] o_pcm_data, // 低32位左声道，高32位右声道，signed Q26
	output [31:0] o_pcm_frame // 采样帧编号
);

	// 允许一条读事务和一条写事务独立在途。
	reg flag_write_active = 1'b0; // 已接受AW等待W
	reg [15:0]reg_write_address = 16'd0; // 当前写拍字节地址
	reg [7:0]reg_write_remaining = 8'd0; // 期望还剩多少后续拍
	reg [3:0]reg_write_id = 4'd0; // 写响应所属ID
	reg [1:0]reg_write_burst = 2'd0; // 固定或递增模式
	reg flag_write_single = 1'b0; // 副作用寄存器只接受单拍写
	reg flag_write_bad = 1'b0; // AW属性不被本外设支持
	reg flag_write_error = 1'b0; // 本突发之前的错误
	reg flag_read_active = 1'b0; // 已接受AR尚有结果待生成
	reg [15:0]reg_read_address = 16'd0; // 下一读拍地址
	reg [7:0]reg_read_remaining = 8'd0; // 下一读拍之后的剩余数
	reg [3:0]reg_read_id = 4'd0; // 同一突发的读ID
	reg [1:0]reg_read_burst = 2'd0; // 读地址演进规则
	reg flag_read_bad = 1'b0; // AR属性非法
	reg [167:0]reg_read_snapshot = 168'd0; // 在AR沿冻结的完成队首
	reg flag_snapshot_valid = 1'b0; // AR时队首是否存在

	reg [31:0]reg_stage [0:9]; // 十个参数/状态字的暂存区
	reg [7:0]reg_stage_opcode = 8'd0; // 待提交的算子类型
	reg [31:0]reg_stage_tag = 32'd0; // 待提交的任务标签
	reg [31:0]reg_stage_context = 32'd0; // 高二十四位代号、低八位上下文编号
	reg [31:0]reg_stage_sequence = 32'd0; // 缓存执行序号，与传输tag分开
	reg [423:0]reg_command [0:3] /* synthesis syn_ramstyle = "registers" */; // 四项浅队列用触发器，避免宽口切片占满块RAM
	reg [167:0]reg_completion [0:3]; // 带标签的完整结果
	reg [1:0]reg_command_write = 2'd0; // 命令队列写指针
	reg [1:0]reg_command_read = 2'd0; // 命令队列读指针
	reg [2:0]cnt_command = 3'd0; // 等待进入计算域的命令数
	reg [423:0]reg_command_head = 424'd0; // 队首读选择与运行时译码之间的寄存边界
	reg flag_command_head_valid = 1'b0; // 快照保持至运行时真正接纳
	reg [1:0]reg_completion_write = 2'd0; // 完成队列尾部
	reg [1:0]reg_completion_read = 2'd0; // 完成队列头部
	reg [2:0]cnt_completion = 3'd0; // 等待主控读取的结果数
	reg [31:0]cnt_submitted = 32'd0; // 已成功敲门提交总数
	reg [31:0]cnt_completed = 32'd0; // 已写入完成队列总数
	reg [31:0]cnt_popped = 32'd0; // 已被主控显式释放总数
	integer idx_byte; // 字节写使能展开
	integer idx_reset; // 小暂存区复位遍历

	wire [12:0]wire_write_end; // INCR最后一个字节的页内扩展位置
	wire [12:0]wire_read_end; // 读突发最后一个字节
	wire flag_aw_accept; // 写地址握手
	wire flag_w_accept; // 写数据握手
	wire flag_ar_accept; // 读地址握手
	wire flag_r_advance; // 读响应寄存器可装载
	wire flag_write_base_error; // 地址属性或写包长度错误
	reg dec_write_error; // 当前写拍是否允许产生副作用
	reg [31:0]dec_read_data; // 当前读地址的数据
	reg [1:0]dec_read_response; // 当前读地址的响应
	wire flag_submit; // 原子命令提交
	wire flag_pop; // 显式完成队首释放
	wire flag_command_take; // 内部流式执行器接收队首
	wire flag_completion_put; // 内部结果进入完成队列
	wire [423:0]wire_command_head; // 当前完整命令
	wire [167:0]wire_completion_head; // 当前完整结果
	wire flag_engine_ready; // 内部执行入口接纳能力
	wire [127:0]wire_engine_result; // 内部完成数据
	wire [31:0]wire_engine_tag; // 内部完成身份
	wire [7:0]wire_engine_opcode; // 内部完成类型
	wire flag_engine_valid; // 内部完成资格
	wire flag_engine_last; // 内部单拍结果边界
	wire [31:0]wire_count_executed; // 排除重放的有效计算次数
	wire [31:0]wire_count_replayed; // 运行时缓存命中次数
	wire [31:0]wire_count_rejected; // 被拒绝的任务次数
	wire [31:0]wire_count_bound; // 新参数镜像绑定次数
	wire [31:0]wire_overruns, wire_render_cycles, wire_pcm_dropped;
	wire [31:0] wire_fx_frames, wire_fx_clipped, wire_fx_dropped, wire_fx_cycles;
	wire [7:0]wire_active;
	reg [96:0]reg_pcm_snapshot; // AR 时原子锁存 FIFO 队首和有效资格

	reg [3:0]s_axi_bid_o = 4'd0; // 输出写响应身份
	reg [1:0]s_axi_bresp_o = 2'd0; // 输出写响应状态
	reg s_axi_bvalid_o = 1'b0; // 写响应保持寄存器
	reg [3:0]s_axi_rid_o = 4'd0; // 输出读响应身份
	reg [31:0]s_axi_rdata_o = 32'd0; // 输出读数据
	reg [1:0]s_axi_rresp_o = 2'd0; // 输出读响应状态
	reg s_axi_rlast_o = 1'b0; // 输出读突发末拍
	reg s_axi_rvalid_o = 1'b0; // 读数据保持寄存器

	assign o_s_axi_awready = i_axi_arstn && !flag_write_active && !s_axi_bvalid_o; // B未收走前不接下一个AW
	assign o_s_axi_wready = i_axi_arstn && flag_write_active; // 允许W早于AW出现，但AW之前不接受W
	assign o_s_axi_arready = i_axi_arstn && !flag_read_active && !s_axi_rvalid_o; // 最后读拍消费后再接新AR
	assign o_s_axi_bid = s_axi_bid_o; // 返回AW的ID
	assign o_s_axi_bresp = s_axi_bresp_o; // 写响应与实际入队语义分开
	assign o_s_axi_bvalid = s_axi_bvalid_o; // B反压时保持
	assign o_s_axi_rid = s_axi_rid_o; // 每个读拍保留AR的ID
	assign o_s_axi_rdata = s_axi_rdata_o; // 读数据经过寄存边界
	assign o_s_axi_rresp = s_axi_rresp_o; // 不支持的请求返回SLVERR
	assign o_s_axi_rlast = s_axi_rlast_o; // 确切标记ARLEN指定末拍
	assign o_s_axi_rvalid = s_axi_rvalid_o; // 不因RREADY低撤销结果
	assign flag_aw_accept = i_s_axi_awvalid && o_s_axi_awready; // AW独立移交
	assign flag_w_accept = i_s_axi_wvalid && o_s_axi_wready; // W独立移交
	assign flag_ar_accept = i_s_axi_arvalid && o_s_axi_arready; // AR独立移交
	assign flag_r_advance = !s_axi_rvalid_o || i_s_axi_rready; // 空槽或消费时生成下一读拍
	assign flag_write_base_error = flag_write_bad || flag_write_error || (i_s_axi_wlast != (reg_write_remaining == 8'd0)); // 写拍检查的默认错误
	assign wire_write_end = {1'b0,i_s_axi_awaddr[11:0]} + {3'd0,i_s_axi_awlen,2'b00} + 13'd3; // 以最后字节检查4KiB
	assign wire_read_end = {1'b0,i_s_axi_araddr[11:0]} + {3'd0,i_s_axi_arlen,2'b00} + 13'd3; // 对读突发执行同样边界检查
	assign wire_command_head = reg_command_head; // 反压期间整条命令保持不变
	assign wire_completion_head = reg_completion[reg_completion_read]; // 只有非空时可对外快照
	assign flag_command_take = flag_command_head_valid && flag_engine_ready; // 一次握手只弹出一个命令
	assign flag_completion_put = flag_engine_valid && cnt_completion < 3'd4; // 完成FIFO满时反压内部核心
	assign flag_submit = flag_w_accept && !dec_write_error && reg_write_address == 16'h0130 && i_s_axi_wstrb[0] && i_s_axi_wdata[0]; // 有效敲门原子复制暂存区
	assign flag_pop = flag_w_accept && !dec_write_error && reg_write_address == 16'h0218 && i_s_axi_wstrb[0] && i_s_axi_wdata[0]; // 读完成记录本身不弹出

	// 写拍验证在产生任何该拍副作用之前完成。
	always@(*)begin
		dec_write_error = flag_write_base_error;
		if(reg_write_address >= 16'h0100 && reg_write_address <= 16'h0124)begin
			dec_write_error = flag_write_base_error; // 参数暂存地址允许部分字节写
		end else begin
			case(reg_write_address)
				16'h0128,16'h012c,16'h0134,16'h0138:begin
					dec_write_error = flag_write_base_error;
					end
				16'h0130:begin
					if(!flag_write_single || (i_s_axi_wstrb[0] && i_s_axi_wdata[0] && cnt_command == 3'd4))begin
						dec_write_error = 1'b1;
						end
				end
				16'h0218:begin
					if(!flag_write_single || (i_s_axi_wstrb[0] && i_s_axi_wdata[0] && cnt_completion == 3'd0))begin
						dec_write_error = 1'b1;
						end
				end
				default:begin
					dec_write_error = 1'b1;
					end
			endcase
		end
	end

	// AW只描述后续写拍，B等到真实WLAST被接受才发布。
	always@(posedge i_axi_aclk or negedge i_axi_arstn)begin
		if(!i_axi_arstn)begin
			flag_write_active <= 1'b0;
				reg_write_address <= 16'd0;
				reg_write_remaining <= 8'd0;
				reg_write_id <= 4'd0;
			reg_write_burst <= 2'd0;
				flag_write_single <= 1'b0;
				flag_write_bad <= 1'b0;
				flag_write_error <= 1'b0;
			s_axi_bid_o <= 4'd0;
				s_axi_bresp_o <= 2'd0;
				s_axi_bvalid_o <= 1'b0;
		end else begin
			if(s_axi_bvalid_o && i_s_axi_bready)begin
				s_axi_bvalid_o <= 1'b0;
				end
			if(flag_aw_accept)begin
				flag_write_active <= 1'b1;
					reg_write_address <= i_s_axi_awaddr;
					reg_write_remaining <= i_s_axi_awlen;
				reg_write_id <= i_s_axi_awid;
					reg_write_burst <= i_s_axi_awburst;
					flag_write_single <= i_s_axi_awlen == 8'd0;
				flag_write_error <= 1'b0;
				flag_write_bad <= i_s_axi_awsize != 3'd2 || i_s_axi_awaddr[1:0] != 2'd0 || i_s_axi_awlock ||
					i_s_axi_awburst > 2'd1 || (i_s_axi_awburst == 2'd0 && i_s_axi_awlen > 8'd15) ||
					(i_s_axi_awburst == 2'd1 && wire_write_end[12]);
			end
			if(flag_w_accept)begin
				flag_write_error <= dec_write_error; // 错误持续到整个写包结束
				if(i_s_axi_wlast)begin
					flag_write_active <= 1'b0;
						s_axi_bvalid_o <= 1'b1;
						s_axi_bid_o <= reg_write_id;
					s_axi_bresp_o <= dec_write_error ? 2'b10 : 2'b00;
				end else begin
					if(reg_write_remaining != 8'd0)begin
						reg_write_remaining <= reg_write_remaining - 8'd1;
						end
					if(reg_write_burst == 2'd1)begin
						reg_write_address <= reg_write_address + 16'd4;
						end
				end
			end
		end
	end

	// 参数暂存只在合法写拍改变，入队后队列持有独立副本。
	always@(posedge i_axi_aclk or negedge i_axi_arstn)begin
		if(!i_axi_arstn)begin
			reg_stage_opcode <= 8'd0;
				reg_stage_tag <= 32'd0;
			reg_stage_context <= 32'd0;
			reg_stage_sequence <= 32'd0;
			for(idx_reset=0;idx_reset<10;idx_reset=idx_reset+1)begin reg_stage[idx_reset] <= 32'd0; end
		end else if(flag_w_accept && !dec_write_error)begin
			if(reg_write_address >= 16'h0100 && reg_write_address <= 16'h0124)begin
				for(idx_byte=0;idx_byte<4;idx_byte=idx_byte+1)begin
					if(i_s_axi_wstrb[idx_byte])begin
						reg_stage[reg_write_address[5:2]][idx_byte*8+:8] <= i_s_axi_wdata[idx_byte*8+:8];
						end
				end
			end else if(reg_write_address == 16'h0128)begin
				if(i_s_axi_wstrb[0])begin
					reg_stage_opcode <= i_s_axi_wdata[7:0];
					end
			end else if(reg_write_address == 16'h012c)begin
				for(idx_byte=0;idx_byte<4;idx_byte=idx_byte+1)begin
					if(i_s_axi_wstrb[idx_byte])begin
						reg_stage_tag[idx_byte*8+:8] <= i_s_axi_wdata[idx_byte*8+:8];
						end
				end
			end else if(reg_write_address == 16'h0134)begin
				for(idx_byte=0;idx_byte<4;idx_byte=idx_byte+1)begin
					if(i_s_axi_wstrb[idx_byte])begin
						reg_stage_context[idx_byte*8+:8] <= i_s_axi_wdata[idx_byte*8+:8];
					end
				end
			end else if(reg_write_address == 16'h0138)begin
				for(idx_byte=0;idx_byte<4;idx_byte=idx_byte+1)begin
					if(i_s_axi_wstrb[idx_byte])begin
						reg_stage_sequence[idx_byte*8+:8] <= i_s_axi_wdata[idx_byte*8+:8];
					end
				end
			end
		end
	end

	// 队列内存不逐项复位，计数与游标控制旧数据不可见。
	always@(posedge i_axi_aclk)begin
		if(i_axi_arstn && flag_submit)begin
			reg_command[reg_command_write] <= {reg_stage_opcode,reg_stage_tag,reg_stage_sequence,reg_stage_context,reg_stage[9],reg_stage[8],reg_stage[7],reg_stage[6],reg_stage[5],reg_stage[4],reg_stage[3],reg_stage[2],reg_stage[1],reg_stage[0]};
		end
		if(i_axi_arstn && flag_completion_put)begin
			reg_completion[reg_completion_write] <= {wire_engine_opcode,wire_engine_tag,wire_engine_result};
		end
	end

	// 快照不提前弹出FIFO，四项容量及满队列拒绝语义保持不变。
	always@(posedge i_axi_aclk or negedge i_axi_arstn)begin
		if(!i_axi_arstn)begin
			reg_command_head <= 424'd0;
			flag_command_head_valid <= 1'b0;
		end else if(flag_command_take)begin
			flag_command_head_valid <= 1'b0;
		end else if(!flag_command_head_valid && cnt_command != 3'd0)begin
			reg_command_head <= reg_command[reg_command_read];
			flag_command_head_valid <= 1'b1;
		end
	end

	// 同拍进出不改变占用数，各游标只随对应握手前进。
	always@(posedge i_axi_aclk or negedge i_axi_arstn)begin
		if(!i_axi_arstn)begin
			reg_command_write <= 2'd0;
				reg_command_read <= 2'd0;
				cnt_command <= 3'd0;
			reg_completion_write <= 2'd0;
				reg_completion_read <= 2'd0;
				cnt_completion <= 3'd0;
			cnt_submitted <= 32'd0;
				cnt_completed <= 32'd0;
				cnt_popped <= 32'd0;
		end else begin
			if(flag_submit)begin
				reg_command_write <= reg_command_write + 2'd1;
				cnt_submitted <= cnt_submitted + 32'd1;
				end
			if(flag_command_take)begin
				reg_command_read <= reg_command_read + 2'd1;
				end
			case({flag_submit,flag_command_take})
				2'b10:begin
					cnt_command <= cnt_command + 3'd1;
					end
				2'b01:begin
					cnt_command <= cnt_command - 3'd1;
					end
				default:begin
					cnt_command <= cnt_command;
					end
			endcase
			if(flag_completion_put)begin
				reg_completion_write <= reg_completion_write + 2'd1;
				cnt_completed <= cnt_completed + 32'd1;
				end
			if(flag_pop)begin
				reg_completion_read <= reg_completion_read + 2'd1;
				cnt_popped <= cnt_popped + 32'd1;
				end
			case({flag_completion_put,flag_pop})
				2'b10:begin
					cnt_completion <= cnt_completion + 3'd1;
					end
				2'b01:begin
					cnt_completion <= cnt_completion - 3'd1;
					end
				default:begin
					cnt_completion <= cnt_completion;
					end
			endcase
		end
	end

	// 完成数据使用AR时捕获的队首，POP并发不会拆散一条突发记录。
	always@(*)begin
		dec_read_data = 32'd0;
			dec_read_response = 2'b00;
		if(flag_read_bad)begin
			dec_read_response = 2'b10;
		end else if(reg_read_address >= 16'h0100 && reg_read_address <= 16'h0124)begin
			dec_read_data = reg_stage[reg_read_address[5:2]];
		end else begin
			case(reg_read_address)
				16'h0000:begin
					dec_read_data = 32'h56534531;
					end
				16'h0004:begin
					dec_read_data = C_TOUCH_ENABLE ? 32'h00010007 : 32'h00010006;
					end
				16'h0008:begin
					dec_read_data[2:0] = cnt_command;
						dec_read_data[6:4] = cnt_completion;
					dec_read_data[8] = cnt_command == 3'd4;
						dec_read_data[9] = cnt_completion == 3'd0;
				end
				16'h000c:begin
					dec_read_data = LEGACY_ENABLE ? 32'h0000001f : 32'd0;
					end
				16'h0010:begin
					dec_read_data = cnt_submitted;
					end
				16'h0014:begin
					dec_read_data = cnt_completed;
					end
				16'h0018:begin
					dec_read_data = cnt_popped;
					end
				16'h0128:begin
					dec_read_data = {24'd0,reg_stage_opcode};
					end
				16'h012c:begin
					dec_read_data = reg_stage_tag;
					end
				16'h001c:begin dec_read_data = LEGACY_ENABLE ? 32'h00000007 : 32'd0; end
				16'h0020:begin dec_read_data = wire_count_executed; end
				16'h0024:begin dec_read_data = wire_count_replayed; end
				16'h0028:begin dec_read_data = wire_count_rejected; end
				16'h002c:begin dec_read_data = wire_count_bound; end
				16'h0030:begin dec_read_data = LEGACY_ENABLE ? 32'd32 : 32'd0; end
				16'h0034:begin dec_read_data = 32'h0008063f; end
				16'h0038:begin dec_read_data = {24'd0,wire_active}; end
				16'h003c:begin dec_read_data = wire_overruns; end
				16'h0040:begin dec_read_data = wire_render_cycles; end
				16'h0044:begin dec_read_data = wire_pcm_dropped; end
				16'h0048:begin dec_read_data = 32'h0002087f; end
				16'h004c:begin dec_read_data = C_FX_ENABLE ? (32'h04001203 | (C_DELAY_ADDR_BITS<<16)) : 32'd0; end
				16'h0050:begin dec_read_data = C_FX_ENABLE ? ((32'd1<<C_DELAY_ADDR_BITS)-1) : 32'd0; end
				16'h0054:begin dec_read_data = wire_fx_frames; end
				16'h0058:begin dec_read_data = wire_fx_clipped; end
				16'h005c:begin dec_read_data = wire_fx_dropped; end
				16'h0060:begin dec_read_data = wire_fx_cycles; end
                16'h0064:begin dec_read_data = 32'h4c504631; end
				16'h0300:begin dec_read_data = reg_pcm_snapshot[31:0]; end
				16'h0304:begin dec_read_data = reg_pcm_snapshot[63:32]; end
				16'h0308:begin dec_read_data = reg_pcm_snapshot[95:64]; end
				16'h030c:begin dec_read_data = {31'd0,reg_pcm_snapshot[96]}; end
				16'h0134:begin dec_read_data = reg_stage_context; end
				16'h0138:begin dec_read_data = reg_stage_sequence; end
				16'h0200:begin
					dec_read_data = reg_read_snapshot[31:0];
					dec_read_response = flag_snapshot_valid ? 2'b00 : 2'b10;
					end
				16'h0204:begin
					dec_read_data = reg_read_snapshot[63:32];
					dec_read_response = flag_snapshot_valid ? 2'b00 : 2'b10;
					end
				16'h0208:begin
					dec_read_data = reg_read_snapshot[95:64];
					dec_read_response = flag_snapshot_valid ? 2'b00 : 2'b10;
					end
				16'h020c:begin
					dec_read_data = reg_read_snapshot[127:96];
					dec_read_response = flag_snapshot_valid ? 2'b00 : 2'b10;
					end
				16'h0210:begin
					dec_read_data = reg_read_snapshot[159:128];
					dec_read_response = flag_snapshot_valid ? 2'b00 : 2'b10;
					end
				16'h0214:begin
					dec_read_data = {24'd0,reg_read_snapshot[167:160]};
					dec_read_response = flag_snapshot_valid ? 2'b00 : 2'b10;
					end
				default:begin
					dec_read_response = 2'b10;
					end
			endcase
		end
	end

	// 读拍寄存后才发布VALID，反压期间ID/数据/RESP/LAST整体保持。
	always@(posedge i_axi_aclk or negedge i_axi_arstn)begin
		if(!i_axi_arstn)begin
			flag_read_active <= 1'b0;
			reg_pcm_snapshot <= 97'd0;
				reg_read_address <= 16'd0;
				reg_read_remaining <= 8'd0;
				reg_read_id <= 4'd0;
			reg_read_burst <= 2'd0;
				flag_read_bad <= 1'b0;
				reg_read_snapshot <= 168'd0;
				flag_snapshot_valid <= 1'b0;
			s_axi_rid_o <= 4'd0;
				s_axi_rdata_o <= 32'd0;
				s_axi_rresp_o <= 2'd0;
				s_axi_rlast_o <= 1'b0;
				s_axi_rvalid_o <= 1'b0;
		end else begin
			if(flag_ar_accept)begin
				reg_pcm_snapshot <= o_pcm_valid ? {1'b1,o_pcm_frame,o_pcm_data} : 97'd0;
				flag_read_active <= 1'b1;
					reg_read_address <= i_s_axi_araddr;
					reg_read_remaining <= i_s_axi_arlen;
				reg_read_id <= i_s_axi_arid;
					reg_read_burst <= i_s_axi_arburst;
				reg_read_snapshot <= cnt_completion != 3'd0 ? wire_completion_head : 168'd0;
					flag_snapshot_valid <= cnt_completion != 3'd0;
				flag_read_bad <= i_s_axi_arsize != 3'd2 || i_s_axi_araddr[1:0] != 2'd0 || i_s_axi_arlock ||
					i_s_axi_arburst > 2'd1 || (i_s_axi_arburst == 2'd0 && i_s_axi_arlen > 8'd15) ||
					(i_s_axi_arburst == 2'd1 && wire_read_end[12]);
			end
			if(flag_r_advance)begin
				s_axi_rvalid_o <= flag_read_active;
				if(flag_read_active)begin
					s_axi_rdata_o <= dec_read_data;
						s_axi_rresp_o <= dec_read_response;
						s_axi_rid_o <= reg_read_id;
					s_axi_rlast_o <= reg_read_remaining == 8'd0;
					if(reg_read_remaining == 8'd0)begin
						flag_read_active <= 1'b0;
						end
					else begin
						reg_read_remaining <= reg_read_remaining - 8'd1;
						if(reg_read_burst == 2'd1)begin
							reg_read_address <= reg_read_address + 16'd4;
							end
					end
				end
			end
		end
	end

	// 外部AXI事务在这里转换为私有流式算子任务，不把AXIS当外部主干。
	AxisSynthSystem #(.C_TOUCH_ENABLE(C_TOUCH_ENABLE),.LEGACY_ENABLE(LEGACY_ENABLE),.C_FX_ENABLE(C_FX_ENABLE),.C_DELAY_ADDR_BITS(C_DELAY_ADDR_BITS)) Runtime_Inst(
		        .i_touch_gain(i_touch_gain),.i_touch_pitch(i_touch_pitch),.i_touch_cutoff(i_touch_cutoff),.i_touch_cutoff_active(i_touch_cutoff_active),
.i_axis_aclk(i_axi_aclk),.i_axis_arstn(i_axi_arstn),
		.i_s_axis_tdata(wire_command_head[383:0]),.i_s_axis_tuser(wire_command_head[415:384]),
		.i_s_axis_tdest(wire_command_head[423:416]),.i_s_axis_tlast(1'b1),
		.i_s_axis_tvalid(flag_command_head_valid),.o_s_axis_tready(flag_engine_ready),
		.o_m_axis_tdata(wire_engine_result),.o_m_axis_tuser(wire_engine_tag),.o_m_axis_tdest(wire_engine_opcode),
		.o_m_axis_tlast(flag_engine_last),.o_m_axis_tvalid(flag_engine_valid),.i_m_axis_tready(cnt_completion < 3'd4),
		.o_count_executed(wire_count_executed),.o_count_replayed(wire_count_replayed),
		.o_count_rejected(wire_count_rejected),.o_count_bound(wire_count_bound),
		.o_pcm_valid(o_pcm_valid),.i_pcm_ready(i_pcm_ready),.o_pcm_data(o_pcm_data),.o_pcm_frame(o_pcm_frame),
		.o_overruns(wire_overruns),.o_pcm_dropped(wire_pcm_dropped),.o_render_cycles(wire_render_cycles),.o_active(wire_active),
		.o_fx_frames(wire_fx_frames),.o_fx_clipped(wire_fx_clipped),.o_fx_dropped(wire_fx_dropped),.o_fx_cycles(wire_fx_cycles)
	);
endmodule

