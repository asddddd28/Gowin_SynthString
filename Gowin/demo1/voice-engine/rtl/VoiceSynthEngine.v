`timescale 1ns / 1ps
// Resident program and voice state owner. Contract: spec/VoiceSynthEngine_spec.md.
// The audio FSM and control completion register are independent: a stalled host
// cannot stop a sounding note. Commands mutate state only between whole frames.
module VoiceSynthEngine(
	input i_axis_aclk,
	input i_axis_arstn,
	input [383:0] i_s_axis_tdata,
	input [31:0] i_s_axis_tuser,
	input [7:0] i_s_axis_tdest,
	input i_s_axis_tvalid,
	output o_s_axis_tready,
	output [127:0] o_m_axis_tdata,
	output [31:0] o_m_axis_tuser,
	output [7:0] o_m_axis_tdest,
	output o_m_axis_tvalid,
	input i_m_axis_tready,
	input i_sample_tick,
	output o_pcm_valid,
	output [63:0] o_pcm_data,
	output [31:0] o_frame,
	output [31:0] o_overruns,
	output [31:0] o_render_cycles,
	output [7:0] o_active
);
	localparam [31:0] Q_UNITY = 32'd67108864;
	reg [4:0] reg_state, dec_next_state;
	reg [2:0] reg_voice, reg_operator;
	reg [7:0] reg_active, reg_held;
	reg [31:0] mem_identity [0:7];
	reg [1:0] mem_patch [0:7];
	reg [31:0] mem_increment [0:7];
	reg [31:0] mem_gain [0:7], mem_pan [0:7];
	reg [31:0] mem_gain_target [0:7], mem_pan_target [0:7];
	reg [6:0] mem_note [0:7], mem_velocity [0:7];
	reg [63:0] flag_dx_row;
	reg [63:0] mem_age [0:7];
	reg [1:0] mem_event [0:7];
	reg [63:0] reg_age;
	(* syn_ramstyle = "block_ram" *) reg [162:0] mem_context [0:63];
	reg [162:0] reg_context_row;
	reg [63:0] flag_context_valid;
	reg signed [31:0] reg_outputs [0:5];
	(* syn_ramstyle = "block_ram" *) reg [191:0] mem_core [0:63];
	(* syn_ramstyle = "block_ram" *) reg [255:0] mem_envelope [0:63];
	reg [3:0] reg_bank, reg_patch_valid, reg_drafting;
	reg [31:0] mem_revision [0:3], mem_draft_revision [0:3];
	reg [5:0] mem_core_loaded [0:3], mem_eg_loaded [0:3], mem_carriers [0:3];
	reg [2:0] mem_carrier_count [0:3];
	reg flag_enabled, flag_sustain;
	reg [31:0] reg_master;
	reg [31:0] reg_mod_increment, reg_mod_gain, reg_mod_pan;
	reg [671:0] reg_operator_request;
	wire flag_operator_ready, flag_operator_valid, flag_wave_ready;
	wire [159:0] wire_operator_result;
	wire [31:0] wire_operator_tag;
	wire [5:0] wire_context = {reg_voice,reg_operator};
	wire [31:0] wire_noise_seed = {26'd0,wire_context}+32'd1;
	wire [162:0] wire_context_data = flag_context_valid[wire_context] ? reg_context_row : {wire_noise_seed,131'd0};
	wire [1:0] wire_patch = mem_patch[reg_voice];
	wire [5:0] wire_program = {reg_bank[wire_patch],wire_patch,reg_operator};
	reg [191:0] wire_core;
	reg [255:0] wire_envelope;
	wire [31:0] wire_flags = wire_core[159:128];
	wire [63:0] wire_tuned = reg_mod_increment * wire_core[31:0];
	wire [31:0] wire_increment = wire_flags[13] ? wire_core[31:0] :
		(wire_tuned[63:47] != 0 ? 32'h7fffffff : wire_tuned[47:16]);
	reg signed [34:0] dec_route_sum;
	reg signed [31:0] dec_modulation;
	reg signed [35:0] reg_carrier_sum;
	reg flag_carrier_live;
	reg signed [67:0] reg_mono_product;
	reg signed [63:0] reg_voice_product;
	reg signed [63:0] reg_left_product, reg_right_product;
	reg signed [39:0] reg_left_sum, reg_right_sum;
	reg signed [71:0] reg_master_left, reg_master_right;
	reg [63:0] reg_pcm;
	reg flag_pcm;
	reg [31:0] cnt_frame, cnt_overruns, cnt_cycles, reg_cycles;
	reg [127:0] reg_completion;
	reg [31:0] reg_completion_tag;
	reg [7:0] reg_completion_opcode;
	reg flag_completion;
	reg flag_session;
	reg [23:0] reg_epoch;
	reg [31:0] reg_sequence;
	reg [327:0] reg_signature;
	reg [127:0] reg_cached;
	reg [31:0] cnt_applied, cnt_replayed, cnt_rejected, cnt_stolen;
	wire [7:0] wire_address = i_s_axis_tdata[327:320];
	wire [23:0] wire_epoch = i_s_axis_tdata[351:328];
	wire [31:0] wire_sequence = i_s_axis_tdata[383:352];
	wire [327:0] wire_signature = {i_s_axis_tdest,i_s_axis_tdata[319:0]};
	reg [7:0] reg_cached_address;
	wire flag_accept = i_s_axis_tvalid && o_s_axis_tready;
	reg [7:0] dec_status;
	reg flag_replay, flag_eligible;
	reg [127:0] dec_completion;
	reg flag_checked, flag_checked_replay, flag_checked_eligible;
	reg flag_prechecked, flag_prechecked_replay, flag_prechecked_eligible;
	reg flag_packet_decoded;
	reg [20:0] reg_signature_equal;
	reg [9:0] reg_payload_zero;
	integer signature_chunk, payload_chunk;
	reg [7:0] dec_identity_status, reg_prechecked_identity, reg_prechecked_status;
	reg [127:0] reg_prechecked_completion;
	reg [7:0] reg_checked_status;
	reg [127:0] reg_checked_completion;
	reg [2:0] dec_slot;
	reg flag_found, flag_free;
	reg [63:0] dec_oldest;
	reg [2:0] dec_oldest_slot;
	reg [1:0] reg_lookup_state, dec_lookup_state;
	reg [2:0] reg_lookup_index, reg_match_slot, reg_free_slot;
	wire flag_lookup_needed = i_s_axis_tdest == 8'ha4 || i_s_axis_tdest == 8'ha5 || i_s_axis_tdest == 8'ha6;
	wire flag_lookup_abort = reg_state != 0 || i_sample_tick || !i_s_axis_tvalid || !flag_lookup_needed;
	reg [2:0] dec_carriers;
	reg [31:0] dec_flags;
	reg flag_format_busy;
	wire [5:0] wire_commit_live_row = {reg_bank[wire_address[1:0]],wire_address[1:0],3'd0};
	wire [5:0] wire_commit_draft_row = {!reg_bank[wire_address[1:0]],wire_address[1:0],3'd0};
	wire [1:0] wire_config_patch = wire_address[4:3];
	wire [5:0] wire_draft_row = {!reg_bank[wire_config_patch],wire_config_patch,wire_address[2:0]};
	wire [6:0] wire_note_input = i_s_axis_tdata[159] ? i_s_axis_tdata[134:128] : 7'd60;
	wire [6:0] wire_velocity_input = i_s_axis_tdata[159] ? i_s_axis_tdata[141:135] : 7'd100;
	wire flag_wave_write = flag_accept && flag_checked_eligible && reg_checked_status == 0 && i_s_axis_tdest == 8'ha8;
	wire flag_control_apply = flag_accept && flag_checked_eligible && reg_checked_status == 0;
	wire flag_mod_done, flag_mod_busy;
	wire [479:0] wire_modulation;
	wire [127:0] wire_lfo_inspect;
	wire [15:0] wire_voice_patches = {mem_patch[7],mem_patch[6],mem_patch[5],mem_patch[4],mem_patch[3],mem_patch[2],mem_patch[1],mem_patch[0]};
	wire [1:0] wire_mod_patch = i_s_axis_tdest == 8'ha0 ? wire_address[1:0] : wire_address[4:3];
	reg signed [63:0] reg_pitch_product;
	wire signed [63:0] wire_pitch_sum = $signed({32'd0,mem_increment[reg_voice]}) + (reg_pitch_product >>> 26);
	wire signed [31:0] wire_pitch_delta = $signed(wire_modulation[31:0]) > 32'sd67108864 ? 32'sd67108864 :
		($signed(wire_modulation[31:0]) < -32'sd67108864 ? -32'sd67108864 : $signed(wire_modulation[31:0]));
	wire signed [32:0] wire_gain_sum = $signed({1'b0,smooth(mem_gain[reg_voice],mem_gain_target[reg_voice])}) + $signed({wire_modulation[63],wire_modulation[63:32]});
	wire signed [32:0] wire_pan_sum = $signed({1'b0,smooth(mem_pan[reg_voice],mem_pan_target[reg_voice])}) + $signed({wire_modulation[95],wire_modulation[95:64]});
	wire signed [31:0] wire_operator_gain_delta = wire_modulation[(3+reg_operator)*32+:32];
	wire signed [31:0] wire_operator_depth_delta = wire_modulation[(9+reg_operator)*32+:32];
	wire signed [32:0] wire_operator_gain_sum = $signed({1'b0,wire_core[63:32]}) + $signed({wire_operator_gain_delta[31],wire_operator_gain_delta});
	wire signed [32:0] wire_operator_depth_sum = $signed({wire_core[95],wire_core[95:64]}) + $signed({wire_operator_depth_delta[31],wire_operator_depth_delta});
	wire [31:0] wire_operator_gain = wire_operator_gain_sum < 0 ? 32'd0 : (wire_operator_gain_sum > 67108864 ? Q_UNITY : wire_operator_gain_sum[31:0]);
	wire [31:0] wire_operator_depth = wire_flags[11] ?
		(wire_operator_depth_sum < 0 ? 32'd0 : (wire_operator_depth_sum > 67108864 ? Q_UNITY : wire_operator_depth_sum[31:0])) :
		(wire_operator_depth_sum < -33'sd2147483648 ? 32'h80000000 : (wire_operator_depth_sum > 33'sd2147483647 ? 32'h7fffffff : wire_operator_depth_sum[31:0]));
	integer carrier_scan, op_scan, reset_index, commit_scan;

	function [31:0] reciprocal;
		input [2:0] count;
		begin
			case(count)
				1: reciprocal=67108864; 2: reciprocal=33554432; 3: reciprocal=22369621;
				4: reciprocal=16777216; 5: reciprocal=13421772; 6: reciprocal=11184810;
				default: reciprocal=0;
			endcase
		end
	endfunction
	function [31:0] smooth;
		input [31:0] current_value, target_value;
		reg [31:0] distance, step;
		begin
			distance = current_value < target_value ? target_value-current_value : current_value-target_value;
			step = distance < 64 ? (distance != 0) : distance >> 6;
			smooth = current_value < target_value ? current_value+step : current_value-step;
		end
	endfunction
	function [31:0] saturate_audio;
		input signed [71:0] product;
		reg signed [71:0] value;
		begin
			value = product >>> 26;
			if (value > 67108864) saturate_audio = Q_UNITY;
			else if (value < -67108864) saturate_audio = -Q_UNITY;
			else saturate_audio = value[31:0];
		end
	endfunction

	assign o_s_axis_tready = i_axis_arstn && reg_state == 0 && !i_sample_tick && (!flag_completion || i_m_axis_tready) &&
		flag_checked;
	assign o_m_axis_tdata = reg_completion;
	assign o_m_axis_tuser = reg_completion_tag;
	assign o_m_axis_tdest = reg_completion_opcode;
	assign o_m_axis_tvalid = flag_completion;
	assign o_pcm_data = reg_pcm;
	assign o_pcm_valid = flag_pcm;
	assign o_frame = cnt_frame;
	assign o_overruns = cnt_overruns;
	assign o_render_cycles = reg_cycles;
	assign o_active = reg_active;

	// Program edges only point to lower operator indices. Sum before saturation.
	always @(*) begin
		dec_route_sum = 0;
		for (op_scan=0;op_scan<6;op_scan=op_scan+1) begin
			if (op_scan < reg_operator && wire_flags[op_scan]) dec_route_sum = dec_route_sum + reg_outputs[op_scan];
		end
		if (dec_route_sum > 2147483647) dec_modulation = 32'h7fffffff;
		else if (dec_route_sum < -35'sd2147483648) dec_modulation = 32'h80000000;
		else dec_modulation = dec_route_sum[31:0];
	end

	// One CAM row per clock breaks the chained eight-by-64-bit age comparator.
	// No voice changes while idle until command acceptance. Audio ticks invalidate
	// the partial snapshot; lookup restarts after rendering and cannot delay audio.
	always @(*) begin
		dec_slot=flag_found ? reg_match_slot : (flag_free ? reg_free_slot : dec_oldest_slot);
	end
	always @(*) begin
		dec_lookup_state=reg_lookup_state;
		if (flag_lookup_abort) dec_lookup_state=0;
		else case (reg_lookup_state)
			0: dec_lookup_state=1;
			1: if (reg_lookup_index==7) dec_lookup_state=2;
			2: if (flag_accept) dec_lookup_state=0;
			default: dec_lookup_state=0;
		endcase
	end
	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) reg_lookup_state<=0;
		else reg_lookup_state<=dec_lookup_state;
	end
	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) begin
			reg_lookup_index<=0;reg_match_slot<=0;reg_free_slot<=0;
			flag_found<=0;flag_free<=0;dec_oldest<=64'hffffffffffffffff;dec_oldest_slot<=0;
		end else if (reg_lookup_state==0 || flag_lookup_abort) begin
			reg_lookup_index<=0;reg_match_slot<=0;reg_free_slot<=0;
			flag_found<=0;flag_free<=0;dec_oldest<=64'hffffffffffffffff;dec_oldest_slot<=0;
		end else if (reg_lookup_state==1) begin
			reg_lookup_index<=reg_lookup_index+1'b1;
			if (reg_active[reg_lookup_index] && mem_age[reg_lookup_index]<dec_oldest) begin
				dec_oldest<=mem_age[reg_lookup_index];dec_oldest_slot<=reg_lookup_index;
			end
			if (!reg_active[reg_lookup_index] && !flag_free) begin flag_free<=1;reg_free_slot<=reg_lookup_index;end
			if (reg_active[reg_lookup_index] && mem_identity[reg_lookup_index]==i_s_axis_tdata[31:0]) begin
				flag_found<=1;reg_match_slot<=reg_lookup_index;
			end
		end
	end

	// Identity and business checks are independent cones. Their registered results
	// are combined on the following clock; only accepted commands consume sequence.
	always @(*) begin
		dec_identity_status=0;flag_replay=0;flag_eligible=0;
		if (flag_session && wire_epoch != reg_epoch) dec_identity_status=4;
		else if (flag_session && wire_sequence == reg_sequence) begin
			if ((&reg_signature_equal) && wire_address == reg_cached_address) flag_replay=1;
			else dec_identity_status=5;
		end else if (flag_session && wire_sequence < reg_sequence) dec_identity_status=6;
		else if (wire_sequence != (flag_session ? reg_sequence+32'd1 : 32'd0)) dec_identity_status=7;
		else flag_eligible=1;
	end
	always @(*) begin
		dec_status=0;dec_completion=0;dec_carriers=0;flag_format_busy=0;
		for (commit_scan=0;commit_scan<8;commit_scan=commit_scan+1) begin
			if (reg_active[commit_scan] && mem_patch[commit_scan] == wire_address[1:0]) flag_format_busy=1;
		end
		dec_flags=i_s_axis_tdata[159:128];
			case(i_s_axis_tdest)
				8'ha0: begin
					if (wire_address > 3 || !(&reg_payload_zero[9:1])) dec_status=8;
					else if (reg_patch_valid[wire_address[1:0]] && i_s_axis_tdata[31:0] <= mem_revision[wire_address[1:0]]) dec_status=5;
				end
				8'ha1: begin
					if (wire_address > 29 || wire_address[2:0] > 5 || !(&reg_payload_zero[9:6]) ||
						dec_flags[31:23] != 0 || (!dec_flags[15] && dec_flags[22:16] != 0) || dec_flags[9:7] > 5 ||
						((dec_flags[5:0] >> wire_address[2:0]) != 0) ||
						i_s_axis_tdata[63:32] > Q_UNITY ||
						(dec_flags[11] && i_s_axis_tdata[95:64] > Q_UNITY) ||
						(dec_flags[13] ? i_s_axis_tdata[31:0] > 32'h7fffffff : i_s_axis_tdata[31:0] > (dec_flags[15] ? 32'h00400000 : 32'h00100000)) ||
						(dec_flags[9:7] == 5 && i_s_axis_tdata[191:160] > 65536) ||
						(dec_flags[15] && (dec_flags[11:7] != 0 || i_s_axis_tdata[95:64] != 0 ||
						 i_s_axis_tdata[127:96] > 7 || i_s_axis_tdata[191] || i_s_axis_tdata[166:160] > 99 ||
						 i_s_axis_tdata[173:167] > 99 || i_s_axis_tdata[180:174] > 99))) dec_status=8;
					else if (!reg_drafting[wire_config_patch]) dec_status=9;
				end
				8'ha2: begin
					if (wire_address > 29 || wire_address[2:0] > 5 || !(&reg_payload_zero[9:8]) ||
						i_s_axis_tdata[127:96] != 0 ||
						(flag_dx_row[wire_draft_row] ?
						 (i_s_axis_tdata[31:0] > 4032 || i_s_axis_tdata[63:32] > 4032 || i_s_axis_tdata[95:64] > 4032 ||
						  i_s_axis_tdata[159:128] > 63 || i_s_axis_tdata[191:160] > 63 || i_s_axis_tdata[223:192] > 63 || i_s_axis_tdata[255:224] > 63) :
						 (i_s_axis_tdata[31:0] > Q_UNITY || i_s_axis_tdata[63:32] > Q_UNITY || i_s_axis_tdata[95:64] > Q_UNITY ||
						  i_s_axis_tdata[159:128] == 0 || i_s_axis_tdata[191:160] == 0 || i_s_axis_tdata[223:192] == 0 || i_s_axis_tdata[255:224] == 0))) dec_status=8;
					else if (!reg_drafting[wire_config_patch]) dec_status=9;
				end
				8'ha3: begin
					if (wire_address > 3 || !(&reg_payload_zero[9:0])) dec_status=8;
					else if (!reg_drafting[wire_address[1:0]] || mem_core_loaded[wire_address[1:0]] != 63 ||
						mem_eg_loaded[wire_address[1:0]] != 63 || mem_carriers[wire_address[1:0]] == 0) dec_status=9;
					// Logarithmic and linear EG states cannot share a live context after a bank swap.
					else if (reg_patch_valid[wire_address[1:0]] && flag_format_busy &&
						flag_dx_row[wire_commit_live_row+:6] != flag_dx_row[wire_commit_draft_row+:6]) dec_status=10;
					for (carrier_scan=0;carrier_scan<6;carrier_scan=carrier_scan+1) dec_carriers=dec_carriers+mem_carriers[wire_address[1:0]][carrier_scan];
				end
				8'ha4,8'ha6: begin
					if (wire_address > 3 || !(&reg_payload_zero[9:5]) || i_s_axis_tdata[158:142] != 0 ||
						(!i_s_axis_tdata[159] && i_s_axis_tdata[158:128] != 0) || i_s_axis_tdata[63:32] > 32'h7fffffff ||
						i_s_axis_tdata[95:64] > Q_UNITY || i_s_axis_tdata[127:96] > Q_UNITY) dec_status=8;
					else if (!reg_patch_valid[wire_address[1:0]]) dec_status=9;
					else if (i_s_axis_tdest == 8'ha6 && !flag_found) dec_status=3;
					else if (i_s_axis_tdest == 8'ha6 && mem_patch[dec_slot] != wire_address[1:0]) dec_status=5;
					else if (i_s_axis_tdest == 8'ha4 && flag_found &&
						(mem_patch[dec_slot] != wire_address[1:0] || mem_increment[dec_slot] != i_s_axis_tdata[63:32] ||
						mem_gain_target[dec_slot] != i_s_axis_tdata[95:64] || mem_pan_target[dec_slot] != i_s_axis_tdata[127:96] ||
						mem_note[dec_slot] != wire_note_input || mem_velocity[dec_slot] != wire_velocity_input)) dec_status=5;
					dec_completion[2:0]=dec_slot;
					dec_completion[73]=flag_found && i_s_axis_tdest == 8'ha4;
				end
				8'ha5: if (wire_address != 0 || !(&reg_payload_zero[9:1])) dec_status=8;
				8'ha7: if (wire_address != 0 || !(&reg_payload_zero[9:2]) || i_s_axis_tdata[31:3] != 0 || i_s_axis_tdata[63:32] > Q_UNITY) dec_status=8;
				8'ha8: begin
					if (wire_address != 0 || !(&reg_payload_zero[9:2]) || i_s_axis_tdata[31:11] != 0 ||
						$signed(i_s_axis_tdata[63:32]) > 67108864 || $signed(i_s_axis_tdata[63:32]) < -67108864) dec_status=8;
					else if (flag_enabled || reg_active != 0 || !flag_wave_ready) dec_status=10;
				end
				8'ha9: begin
					if (wire_address > 3 || !(&reg_payload_zero[9:0])) dec_status=8;
					case(wire_address[1:0])
						0: dec_completion={cnt_stolen,32'd0,cnt_frame,24'd0,reg_active};
						1: dec_completion={cnt_replayed,32'd0,cnt_rejected,cnt_applied};
						2: dec_completion={reg_cycles,32'd0,cnt_overruns,30'd0,flag_sustain,flag_enabled};
						3: dec_completion={32'd0,32'd0,mem_revision[0],24'd0,reg_drafting,reg_patch_valid};
					endcase
				end
				8'hb0: begin
					if (wire_address > 25 || wire_address[2:0] > 1 || !(&reg_payload_zero[9:5]) ||
						i_s_axis_tdata[31:0] > 32'd8796093 || i_s_axis_tdata[95:70] != 0 || i_s_axis_tdata[66:64] > 6) dec_status=8;
					else if (!reg_drafting[wire_config_patch]) dec_status=9;
				end
				8'hb1: begin
					if (wire_address > 31 || !(&reg_payload_zero[9:2]) || i_s_axis_tdata[31:6] != 0 || i_s_axis_tdata[5:2] > 14) dec_status=8;
					else if (!reg_drafting[wire_config_patch]) dec_status=9;
				end
				8'hb2,8'hb3: begin
					if (wire_address > 23 || !(&reg_payload_zero[9:0])) dec_status=8;
					else if (i_s_axis_tdest == 8'hb2) dec_completion=wire_lfo_inspect;
				end
				default: dec_status=1;
			endcase
		dec_completion[71:64]=dec_status;
	end

	// A frame boundary cancels both validation stages. The upstream command is
	// still held until READY, so a fresh voice snapshot is checked after rendering.
	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) begin
			flag_checked<=0;flag_checked_replay<=0;flag_checked_eligible<=0;
			reg_checked_status<=0;reg_checked_completion<=0;
			flag_packet_decoded<=0;reg_signature_equal<=0;reg_payload_zero<=0;
			flag_prechecked<=0;flag_prechecked_replay<=0;flag_prechecked_eligible<=0;
			reg_prechecked_identity<=0;reg_prechecked_status<=0;reg_prechecked_completion<=0;
		end else if (reg_state!=0 || i_sample_tick || !i_s_axis_tvalid || flag_accept) begin
			flag_packet_decoded<=0;flag_prechecked<=0;flag_checked<=0;
		end else if (!flag_packet_decoded) begin
			flag_packet_decoded<=1;
			for (signature_chunk=0;signature_chunk<20;signature_chunk=signature_chunk+1)
				reg_signature_equal[signature_chunk]<=wire_signature[signature_chunk*16+:16]==reg_signature[signature_chunk*16+:16];
			reg_signature_equal[20]<=wire_signature[327:320]==reg_signature[327:320];
			for (payload_chunk=0;payload_chunk<10;payload_chunk=payload_chunk+1)
				reg_payload_zero[payload_chunk]<=i_s_axis_tdata[payload_chunk*32+:32]==0;
		end else if (!flag_checked && flag_prechecked) begin
			flag_checked<=1;flag_checked_replay<=flag_prechecked_replay;flag_checked_eligible<=flag_prechecked_eligible;
			reg_checked_status<=flag_prechecked_eligible ? reg_prechecked_status : reg_prechecked_identity;
			if (flag_prechecked_replay) begin reg_checked_completion<=reg_cached;reg_checked_completion[72]<=1;end
			else if (flag_prechecked_eligible) reg_checked_completion<=reg_prechecked_completion;
			else reg_checked_completion<={56'd0,reg_prechecked_identity,64'd0};
		end else if (!flag_prechecked && (!flag_lookup_needed || reg_lookup_state==2)) begin
			flag_prechecked<=1;flag_prechecked_replay<=flag_replay;flag_prechecked_eligible<=flag_eligible;
			reg_prechecked_identity<=dec_identity_status;reg_prechecked_status<=dec_status;reg_prechecked_completion<=dec_completion;
		end
	end

	always @(*) begin
		dec_next_state=reg_state;
		case(reg_state)
			0: if (i_sample_tick) dec_next_state=flag_enabled ? 11 : 1;
			1: begin
				if (!flag_enabled || !reg_active[reg_voice]) dec_next_state=8;
				else if (!wire_flags[12]) dec_next_state=4;
				else dec_next_state=2;
			end
			2: if (flag_operator_ready) dec_next_state=3;
			3: if (flag_operator_valid) dec_next_state=4;
			4: dec_next_state=reg_operator == 5 ? 5 : 17;
			5: dec_next_state=6;
			6: dec_next_state=7;
			7: dec_next_state=8;
			8: dec_next_state=reg_voice == 7 ? 9 : (flag_enabled ? 13 : 1);
			9: dec_next_state=10;
			10: dec_next_state=0;
			11: dec_next_state=12;
			12: if (flag_mod_done) dec_next_state=13;
			13: dec_next_state=reg_active[reg_voice] ? 14 : 1;
			14: if (flag_mod_done) dec_next_state=15;
			15: dec_next_state=16;
			16: dec_next_state=1;
			17: dec_next_state=1;
			default: dec_next_state=0;
		endcase
	end
	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) reg_state<=0;
		else reg_state<=dec_next_state;
	end

	// Synchronous program banks: operator advance spends state 17 fetching the next row.
	// No reset on RAM contents; loaded masks and committed-bank validity guard all use.
	always @(posedge i_axis_aclk) begin
		wire_core<=mem_core[wire_program];
		wire_envelope<=mem_envelope[wire_program];
		reg_context_row<=mem_context[wire_context];
		if (i_axis_arstn && reg_state==3 && flag_operator_valid)
			mem_context[wire_context]<={wire_operator_result[159:128],wire_context_data[98:67],wire_operator_result[31:0],
				wire_operator_result[98:96],wire_operator_result[95:64],wire_operator_result[63:32]};
		if (i_axis_arstn && flag_control_apply && i_s_axis_tdest==8'ha1)
			mem_core[wire_draft_row]<=i_s_axis_tdata[191:0];
		if (i_axis_arstn && flag_control_apply && i_s_axis_tdest==8'ha2)
			mem_envelope[wire_draft_row]<=i_s_axis_tdata[255:0];
	end
	// One sequential owner for each voice state; command updates occur between frames.
	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) begin
			flag_context_valid<=0;
			flag_dx_row<=0;
			reg_voice<=0; reg_operator<=0; reg_active<=0; reg_held<=0; reg_age<=0;
			reg_bank<=0; reg_patch_valid<=0; reg_drafting<=0; flag_enabled<=0; flag_sustain<=0; reg_master<=Q_UNITY;
			reg_operator_request<=0; reg_carrier_sum<=0; flag_carrier_live<=0;
			reg_mono_product<=0; reg_voice_product<=0; reg_left_product<=0; reg_right_product<=0;
			reg_left_sum<=0; reg_right_sum<=0; reg_master_left<=0; reg_master_right<=0;
			reg_pcm<=0; flag_pcm<=0; cnt_frame<=0; cnt_overruns<=0; cnt_cycles<=0; reg_cycles<=0;
			flag_completion<=0; reg_completion<=0; reg_completion_tag<=0; reg_completion_opcode<=0;
			flag_session<=0; reg_epoch<=0; reg_sequence<=0; reg_signature<=0; reg_cached_address<=0; reg_cached<=0;
			cnt_applied<=0; cnt_replayed<=0; cnt_rejected<=0; cnt_stolen<=0;
			reg_pitch_product<=0; reg_mod_increment<=0; reg_mod_gain<=0; reg_mod_pan<=0;
			for(reset_index=0;reset_index<4;reset_index=reset_index+1) begin
				mem_revision[reset_index]<=0; mem_draft_revision[reset_index]<=0; mem_core_loaded[reset_index]<=0;
				mem_eg_loaded[reset_index]<=0; mem_carriers[reset_index]<=0; mem_carrier_count[reset_index]<=0;
			end
			for(reset_index=0;reset_index<8;reset_index=reset_index+1) begin
				mem_identity[reset_index]<=0; mem_patch[reset_index]<=0; mem_increment[reset_index]<=0;
				mem_gain[reset_index]<=0; mem_pan[reset_index]<=0; mem_gain_target[reset_index]<=0; mem_pan_target[reset_index]<=0;
				mem_age[reset_index]<=0; mem_event[reset_index]<=0;
				mem_note[reset_index]<=60; mem_velocity[reset_index]<=100;
			end
			for(reset_index=0;reset_index<6;reset_index=reset_index+1) reg_outputs[reset_index]<=0;
			// Arithmetic state is initialized on allocation; inactive entries are never read.
		end else begin
			flag_pcm<=0;
			if (flag_completion && i_m_axis_tready) flag_completion<=0;
			if (i_sample_tick && reg_state != 0) cnt_overruns<=cnt_overruns+1'b1;
			if (reg_state != 0) cnt_cycles<=cnt_cycles+1'b1;
			case(reg_state)
				0: if (i_sample_tick) begin
					reg_voice<=0; reg_operator<=0; reg_left_sum<=0; reg_right_sum<=0;
					reg_carrier_sum<=0; flag_carrier_live<=0; cnt_cycles<=1;
					for(reset_index=0;reset_index<6;reset_index=reset_index+1) reg_outputs[reset_index]<=0;
				end
				1: begin
					if (reg_operator == 0) begin
						mem_gain[reg_voice]<=smooth(mem_gain[reg_voice],mem_gain_target[reg_voice]);
						mem_pan[reg_voice]<=smooth(mem_pan[reg_voice],mem_pan_target[reg_voice]);
					end
					if (flag_enabled && reg_active[reg_voice] && wire_flags[12]) begin
						reg_operator_request<={wire_core[191:160],5'd0,wire_flags[22:16],mem_velocity[reg_voice],mem_note[reg_voice],wire_flags[15],wire_flags[11:10],wire_flags[9:7],wire_context_data[162:131],
							wire_core[127:96],wire_context_data[130:99],wire_context_data[98:67],wire_envelope,
							26'd0,wire_flags[14],mem_event[reg_voice],wire_context_data[66:64],wire_context_data[63:32],
							wire_operator_gain,wire_operator_depth,dec_modulation,wire_increment,wire_context_data[31:0]};
					end else begin
						reg_outputs[reg_operator]<=0;
						// Clear stale stereo products for the inactive-voice fast path.
						reg_left_product<=0; reg_right_product<=0;
					end
				end
				3: if (flag_operator_valid) begin
					flag_context_valid[wire_context]<=1;
					reg_outputs[reg_operator]<=wire_operator_result[31:0];
					if (wire_flags[6]) begin
						reg_carrier_sum<=reg_carrier_sum+$signed(wire_operator_result[31:0]);
						flag_carrier_live<=flag_carrier_live || wire_operator_result[98:96] != 0;
					end
				end
				4: if (reg_operator != 5) reg_operator<=reg_operator+1'b1;
				5: begin
					reg_mono_product<=reg_carrier_sum*$signed(reciprocal(mem_carrier_count[wire_patch]));
					mem_event[reg_voice]<=0;
					if (!flag_carrier_live && !reg_held[reg_voice]) reg_active[reg_voice]<=0;
				end
				6: reg_voice_product<=$signed(reg_mono_product[57:26])*$signed(reg_mod_gain);
				7: begin
					reg_left_product<=$signed(reg_voice_product[57:26])*$signed(Q_UNITY-reg_mod_pan);
					reg_right_product<=$signed(reg_voice_product[57:26])*$signed(reg_mod_pan);
				end
				8: begin
					reg_left_sum<=reg_left_sum+{{8{reg_left_product[57]}},reg_left_product[57:26]};
					reg_right_sum<=reg_right_sum+{{8{reg_right_product[57]}},reg_right_product[57:26]};
					reg_voice<=reg_voice+1'b1; reg_operator<=0; reg_carrier_sum<=0; flag_carrier_live<=0;
					for(reset_index=0;reset_index<6;reset_index=reset_index+1) reg_outputs[reset_index]<=0;
				end
				9: begin
					reg_master_left<=(reg_left_sum >>> 3)*$signed(reg_master);
					reg_master_right<=(reg_right_sum >>> 3)*$signed(reg_master);
				end
				10: begin
					reg_pcm<={saturate_audio(reg_master_right),saturate_audio(reg_master_left)};
					flag_pcm<=1; cnt_frame<=cnt_frame+1'b1; reg_cycles<=cnt_cycles;
				end
				15: begin
					reg_pitch_product<=$signed(mem_increment[reg_voice])*wire_pitch_delta;
					reg_mod_gain<=wire_gain_sum < 0 ? 32'd0 : (wire_gain_sum > 67108864 ? Q_UNITY : wire_gain_sum[31:0]);
					reg_mod_pan<=wire_pan_sum < 0 ? 32'd0 : (wire_pan_sum > 67108864 ? Q_UNITY : wire_pan_sum[31:0]);
				end
				16: reg_mod_increment<=wire_pitch_sum < 0 ? 32'd0 : (wire_pitch_sum > 64'sh7fffffff ? 32'h7fffffff : wire_pitch_sum[31:0]);
				default: reg_pcm<=reg_pcm;
			endcase
			if (flag_accept) begin
				flag_completion<=1; reg_completion<=reg_checked_completion;
				reg_completion_tag<=i_s_axis_tuser; reg_completion_opcode<=i_s_axis_tdest;
				if (flag_checked_replay) cnt_replayed<=cnt_replayed+1'b1;
				else if (reg_checked_status != 0) cnt_rejected<=cnt_rejected+1'b1;
				if (flag_checked_eligible) begin
					flag_session<=1; reg_epoch<=wire_epoch; reg_sequence<=wire_sequence;
					reg_signature<=wire_signature; reg_cached_address<=wire_address; reg_cached<=reg_checked_completion;
					if (reg_checked_status == 0) begin
						cnt_applied<=cnt_applied+1'b1;
						case(i_s_axis_tdest)
							8'ha0: begin
								reg_drafting[wire_address[1:0]]<=1; mem_draft_revision[wire_address[1:0]]<=i_s_axis_tdata[31:0];
								mem_core_loaded[wire_address[1:0]]<=0; mem_eg_loaded[wire_address[1:0]]<=0; mem_carriers[wire_address[1:0]]<=0;
							end
							8'ha1: begin
								mem_core_loaded[wire_config_patch][wire_address[2:0]]<=1;
								mem_eg_loaded[wire_config_patch][wire_address[2:0]]<=0;
								flag_dx_row[wire_draft_row]<=dec_flags[15];
								mem_carriers[wire_config_patch][wire_address[2:0]]<=dec_flags[6] && dec_flags[12];
							end
							8'ha2: begin mem_eg_loaded[wire_config_patch][wire_address[2:0]]<=1; end
							8'ha3: begin
								reg_bank[wire_address[1:0]]<=!reg_bank[wire_address[1:0]]; reg_patch_valid[wire_address[1:0]]<=1;
								reg_drafting[wire_address[1:0]]<=0; mem_revision[wire_address[1:0]]<=mem_draft_revision[wire_address[1:0]];
								mem_carrier_count[wire_address[1:0]]<=dec_carriers;
							end
							8'ha4: if (!flag_found) begin
								if (reg_active[dec_slot]) cnt_stolen<=cnt_stolen+1'b1;
								reg_active[dec_slot]<=1; reg_held[dec_slot]<=1; mem_identity[dec_slot]<=i_s_axis_tdata[31:0];
								mem_patch[dec_slot]<=wire_address[1:0]; mem_increment[dec_slot]<=i_s_axis_tdata[63:32];
								mem_note[dec_slot]<=wire_note_input; mem_velocity[dec_slot]<=wire_velocity_input;
								mem_gain[dec_slot]<=i_s_axis_tdata[95:64]; mem_gain_target[dec_slot]<=i_s_axis_tdata[95:64];
								mem_pan[dec_slot]<=i_s_axis_tdata[127:96]; mem_pan_target[dec_slot]<=i_s_axis_tdata[127:96];
								mem_event[dec_slot]<=1; mem_age[dec_slot]<=reg_age; reg_age<=reg_age+1'b1;
								// Invalidate all contexts of the allocated voice; first use supplies zeros and a deterministic noise seed.
								flag_context_valid[{dec_slot,3'd0}+:8]<=0;
							end
							8'ha5: if (flag_found) begin
								reg_held[dec_slot]<=0; if (!flag_sustain) mem_event[dec_slot]<=2;
							end
							8'ha6: begin
								mem_note[dec_slot]<=wire_note_input; mem_velocity[dec_slot]<=wire_velocity_input;
								mem_increment[dec_slot]<=i_s_axis_tdata[63:32]; mem_gain_target[dec_slot]<=i_s_axis_tdata[95:64]; mem_pan_target[dec_slot]<=i_s_axis_tdata[127:96];
							end
							8'ha7: begin
								flag_enabled<=i_s_axis_tdata[0]; flag_sustain<=i_s_axis_tdata[1]; reg_master<=i_s_axis_tdata[63:32];
								if (flag_sustain && !i_s_axis_tdata[1]) begin
									for(reset_index=0;reset_index<8;reset_index=reset_index+1) begin
										if (reg_active[reset_index] && !reg_held[reset_index]) mem_event[reset_index]<=2;
									end
								end
								if (i_s_axis_tdata[2]) begin reg_active<=0; reg_held<=0; end
							end
							default: reg_active<=reg_active;
						endcase
					end
				end
			end
		end
	end
	VoiceModulation Modulation_Inst(
		.i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),
		.i_start_frame(reg_state == 11),.i_patch_valid(reg_patch_valid),.i_patch_bank(reg_bank),
		.i_voice_active(reg_active),.i_voice_patch(wire_voice_patches),
		.i_start_voice(reg_state == 13 && reg_active[reg_voice]),.i_voice(reg_voice),.i_patch(wire_patch),
		.i_note_on(flag_control_apply && i_s_axis_tdest == 8'ha4 && !flag_found),.i_note_voice(dec_slot),
		.i_restart(flag_control_apply && i_s_axis_tdest == 8'hb3),.i_restart_context(wire_address[4:0]),
		.i_begin(flag_control_apply && i_s_axis_tdest == 8'ha0),
		.i_config_write(flag_control_apply && (i_s_axis_tdest == 8'hb0 || i_s_axis_tdest == 8'hb1)),
		.i_config_route(i_s_axis_tdest == 8'hb1),.i_config_bank(!reg_bank[wire_mod_patch]),
		.i_config_patch(wire_mod_patch),.i_config_index(wire_address[2:0]),.i_config_data(i_s_axis_tdata[159:0]),
		.i_inspect(wire_address[4:0]),.o_inspect(wire_lfo_inspect),.o_busy(flag_mod_busy),
		.o_done(flag_mod_done),.o_modulation(wire_modulation)
	);
	AxisFmOperator Operator_Inst(
		.i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(reg_operator_request),
		.i_s_axis_tuser({26'd0,wire_context}),.i_s_axis_tvalid(reg_state == 2),.o_s_axis_tready(flag_operator_ready),
		.o_m_axis_tdata(wire_operator_result),.o_m_axis_tuser(wire_operator_tag),
		.o_m_axis_tvalid(flag_operator_valid),.i_m_axis_tready(reg_state == 3),
		.i_wave_write(flag_wave_write),.i_wave_address(i_s_axis_tdata[10:0]),.i_wave_data(i_s_axis_tdata[63:32]),.o_wave_ready(flag_wave_ready)
	);
endmodule
