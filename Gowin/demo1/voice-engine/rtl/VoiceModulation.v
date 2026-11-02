`timescale 1ns / 1ps
// Parameter-bank and LFO-state owner. Contract: spec/VoiceModulation_spec.md.
module VoiceModulation(
	input i_axis_aclk,
	input i_axis_arstn,
	input i_start_frame,
	input [3:0] i_patch_valid,
	input [3:0] i_patch_bank,
	input [7:0] i_voice_active,
	input [15:0] i_voice_patch,
	input i_start_voice,
	input [2:0] i_voice,
	input [1:0] i_patch,
	input i_note_on,
	input [2:0] i_note_voice,
	input i_restart,
	input [4:0] i_restart_context,
	input i_begin,
	input i_config_write,
	input i_config_route,
	input i_config_bank,
	input [1:0] i_config_patch,
	input [2:0] i_config_index,
	input [159:0] i_config_data,
	input [4:0] i_inspect,
	output [127:0] o_inspect,
	output o_busy,
	output o_done,
	output [479:0] o_modulation
);
	reg [2:0] reg_state, dec_next_state;
	reg [4:0] reg_context;
	reg [5:0] cnt_pending;
	reg [2:0] reg_route, reg_voice;
	reg [1:0] reg_patch;
	reg [159:0] mem_lfo_config [0:15];
	reg [63:0] mem_route_config [0:63];
	reg [15:0] flag_lfo_enabled;
	reg [63:0] flag_route_enabled;
	reg [23:0] flag_initialized;
	reg [31:0] mem_phase [0:23], mem_rng [0:23], mem_origin [0:23];
	reg signed [31:0] mem_value [0:23];
	reg signed [35:0] mem_accumulator [0:14];
	reg signed [63:0] reg_product;
	reg [3:0] reg_target;
	reg [63:0] reg_route_descriptor; // 同步读取路由，隔离配置RAM选择路径
	reg flag_descriptor_valid, flag_descriptor_enabled;
	reg signed [31:0] reg_source_operand, reg_depth_operand; // 乘法器输入寄存边界
	reg [3:0] reg_operand_target;
	reg flag_operand_valid, flag_product_valid;
	reg [479:0] reg_modulation;
	reg flag_done;
	wire flag_local = reg_context >= 8;
	wire [4:0] wire_local_context = reg_context - 5'd8;
	wire [2:0] wire_voice = wire_local_context[3:1];
	wire [1:0] wire_patch = flag_local ? i_voice_patch[wire_voice*2+:2] : reg_context[2:1];
	wire [3:0] wire_source_address = {i_patch_bank[wire_patch],wire_patch,reg_context[0]};
	wire [159:0] wire_config = mem_lfo_config[wire_source_address];
	wire flag_eligible = reg_context < 24 && flag_lfo_enabled[wire_source_address] && i_patch_valid[wire_patch] &&
		(wire_config[68] == flag_local) && (!flag_local || i_voice_active[wire_voice]);
	wire flag_lfo_ready, flag_lfo_valid;
	wire flag_issue = reg_state == 1 && flag_eligible;
	wire flag_submit = flag_issue && flag_lfo_ready;
	wire [159:0] wire_lfo_result;
	wire [31:0] wire_lfo_tag;
	wire [255:0] wire_request = {wire_config[159:128],wire_config[127:96],wire_config[63:32],
		27'd0,!flag_initialized[reg_context],wire_config[67:64],mem_origin[reg_context],mem_rng[reg_context],wire_config[31:0],mem_phase[reg_context]};
	wire [5:0] wire_route_address = {i_patch_bank[reg_patch],reg_patch,reg_route};
	wire [63:0] wire_route_config = reg_route_descriptor;
	wire [3:0] wire_selected_lfo = {i_patch_bank[reg_patch],reg_patch,wire_route_config[1]};
	wire [4:0] wire_selected_context = mem_lfo_config[wire_selected_lfo][68] ?
		(5'd8+{reg_voice,1'b0}+wire_route_config[1]) : {2'd0,reg_patch,wire_route_config[1]};
	wire signed [31:0] wire_source_value = flag_lfo_enabled[wire_selected_lfo] ? mem_value[wire_selected_context] : 32'sd0;
	wire [3:0] wire_config_lfo = {i_config_bank,i_config_patch,i_config_index[0]};
	wire [5:0] wire_config_route = {i_config_bank,i_config_patch,i_config_index};
	wire flag_inspect_valid = i_inspect < 24;
	integer index;
	assign o_busy = reg_state != 0;
	assign o_done = flag_done;
	assign o_modulation = reg_modulation;
	assign o_inspect = flag_inspect_valid ? {mem_rng[i_inspect],21'd0,flag_initialized[i_inspect],10'd0,mem_phase[i_inspect],mem_value[i_inspect]} : 128'd0;

	always @(*) begin
		dec_next_state=reg_state;
		case(reg_state)
			0: begin
				if (i_start_frame) dec_next_state=1;
				else if (i_start_voice) dec_next_state=3;
			end
			1: if (reg_context == 23 && (!flag_eligible || flag_lfo_ready)) dec_next_state=2;
			2: if (cnt_pending == 0) dec_next_state=0;
			3: if (reg_route == 7) dec_next_state=4;
			4: if (!flag_descriptor_valid && !flag_operand_valid && !flag_product_valid) dec_next_state=5;
			5: dec_next_state=0;
			default: dec_next_state=0;
		endcase
	end
	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) reg_state<=0;
		else reg_state<=dec_next_state;
	end
	// All state transitions occur once per accepted LFO completion, never per route.
	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) begin
			reg_context<=0;
			cnt_pending<=0;
			reg_route<=0;
			reg_voice<=0;
			reg_patch<=0;
			flag_lfo_enabled<=0;
			flag_route_enabled<=0;
			flag_initialized<=0;
			reg_product<=0;
			reg_target<=0;
			reg_route_descriptor<=0;
			flag_descriptor_valid<=0;
			flag_descriptor_enabled<=0;
			reg_source_operand<=0;
			reg_depth_operand<=0;
			reg_operand_target<=0;
			flag_operand_valid<=0;
			flag_product_valid<=0;
			reg_modulation<=0;
			flag_done<=0;
			for(index=0;index<24;index=index+1) begin
				mem_phase[index]<=0;
				mem_rng[index]<=1;
				mem_origin[index]<=0;
				mem_value[index]<=0;
			end
			for(index=0;index<15;index=index+1) mem_accumulator[index]<=0;
		end else begin
			flag_done<=0;
			// 描述符、源值、乘积依序前进；连续同目标写回读取上一拍累加值。
			flag_descriptor_valid <= reg_state == 3;
			flag_operand_valid <= flag_descriptor_valid;
			flag_product_valid <= flag_operand_valid;
			if (reg_state == 3) begin
				reg_route_descriptor <= mem_route_config[wire_route_address];
				flag_descriptor_enabled <= flag_route_enabled[wire_route_address];
			end
			if (flag_descriptor_valid) begin
				reg_source_operand <= flag_descriptor_enabled ? wire_source_value : 32'sd0;
				reg_depth_operand <= flag_descriptor_enabled ? wire_route_config[63:32] : 32'sd0;
				reg_operand_target <= flag_descriptor_enabled ? wire_route_config[5:2] : 4'd0;
			end
			if (flag_operand_valid) begin
				reg_product <= reg_source_operand * reg_depth_operand;
				reg_target <= reg_operand_target;
			end
			if (flag_product_valid) begin
				mem_accumulator[reg_target] <= mem_accumulator[reg_target] + reg_product[61:26];
			end
			case({flag_submit,flag_lfo_valid})
				2'b10: cnt_pending<=cnt_pending+1'b1;
				2'b01: cnt_pending<=cnt_pending-1'b1;
				default: cnt_pending<=cnt_pending;
			endcase
			if (flag_lfo_valid) begin
				mem_value[wire_lfo_tag[4:0]]<=wire_lfo_result[31:0];
				mem_phase[wire_lfo_tag[4:0]]<=wire_lfo_result[63:32];
				mem_rng[wire_lfo_tag[4:0]]<=wire_lfo_result[95:64];
				mem_origin[wire_lfo_tag[4:0]]<=wire_lfo_result[127:96];
				flag_initialized[wire_lfo_tag[4:0]]<=1;
			end
			case(reg_state)
				0: begin
					if (i_start_frame) reg_context<=0;
					if (i_start_voice && !i_start_frame) begin
						reg_route<=0;
						reg_voice<=i_voice;
						reg_patch<=i_patch;
						for(index=0;index<15;index=index+1) mem_accumulator[index]<=0;
					end
					if (i_note_on) begin
						flag_initialized[8+{i_note_voice,1'b0}]<=0;
						flag_initialized[9+{i_note_voice,1'b0}]<=0;
					end
					if (i_restart) flag_initialized[i_restart_context]<=0;
					if (i_begin) begin
						flag_lfo_enabled[{i_config_bank,i_config_patch,1'b0}+:2]<=0;
						flag_route_enabled[{i_config_bank,i_config_patch,3'd0}+:8]<=0;
					end else if (i_config_write) begin
						if (i_config_route) flag_route_enabled[wire_config_route]<=i_config_data[0];
						else flag_lfo_enabled[wire_config_lfo]<=i_config_data[69];
					end
				end
				1: if (!flag_eligible || flag_lfo_ready) reg_context<=reg_context+1'b1;
				2: if (cnt_pending == 0) flag_done<=1;
				3: reg_route<=reg_route+1'b1;
				5: begin
					for(index=0;index<15;index=index+1) begin
						if (mem_accumulator[index] > 36'sd2147483647) reg_modulation[index*32+:32]<=32'h7fffffff;
						else if (mem_accumulator[index] < -36'sd2147483648) reg_modulation[index*32+:32]<=32'h80000000;
						else reg_modulation[index*32+:32]<=mem_accumulator[index][31:0];
					end
					flag_done<=1;
				end
				default: flag_done<=0;
			endcase
		end
	end
	// Descriptor RAM is invalidated by masks, not a reset on every data bit.
	always @(posedge i_axis_aclk) begin
		if (i_axis_arstn && reg_state == 0 && i_config_write && !i_begin) begin
			if (i_config_route) mem_route_config[wire_config_route]<=i_config_data[63:0];
			else mem_lfo_config[wire_config_lfo]<=i_config_data;
		end
	end
	AxisLfoStep Lfo_Inst(
		.i_axis_aclk(i_axis_aclk),
		.i_axis_arstn(i_axis_arstn),
		.i_s_axis_tdata(wire_request),
		.i_s_axis_tuser({27'd0,reg_context}),
		.i_s_axis_tvalid(flag_issue),
		.o_s_axis_tready(flag_lfo_ready),
		.o_m_axis_tdata(wire_lfo_result),
		.o_m_axis_tuser(wire_lfo_tag),
		.o_m_axis_tvalid(flag_lfo_valid),
		.i_m_axis_tready(1'b1)
	);
endmodule
