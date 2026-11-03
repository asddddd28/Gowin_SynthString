`timescale 1ns / 1ps
// DX logarithmic envelope / DX 对数包络. Contract: spec/AxisDxEnvelope_spec.md.
// Scaling formulas derive from Google MSFA (Apache-2.0); see assets/fm1/DSP_NOTICE.txt.
// State is caller-owned; accepting a result commits exactly one audio sample.
module AxisDxEnvelope(
	input i_axis_aclk,
	input i_axis_arstn,
	input [383:0] i_s_axis_tdata,
	input [31:0] i_s_axis_tuser,
	input i_s_axis_tvalid,
	output o_s_axis_tready,
	output [95:0] o_m_axis_tdata,
	output [31:0] o_m_axis_tuser,
	output o_m_axis_tvalid,
	input i_m_axis_tready
);
	localparam [31:0] C_FLOOR = 32'd1048576;
	localparam [31:0] C_JUMP = 32'd112459776;
	reg [2:0] reg_state;
	reg [2:0] dec_next_state;
	reg [383:0] reg_request;
	reg [31:0] reg_tag;
	reg [95:0] reg_result;
	reg [31:0] mem_rate [0:63];
	reg [31:0] mem_exp [0:255];
	reg [31:0] mem_velocity [0:63];
	reg [17:0] mem_keyscale_product [0:127];
	reg [2:0] reg_stage;
	reg flag_bad;
	reg [31:0] reg_level;
	reg [12:0] reg_scaled_level;
	reg [5:0] reg_base_rate;
	reg [4:0] reg_rate_scale;
	reg [17:0] reg_curve_product;
	reg [6:0] reg_depth;
	reg flag_negative;
	reg signed [31:0] reg_velocity_delta;
	reg signed [31:0] reg_velocity_offset; // 曲线查表及偏移先寄存，再执行灵敏度乘法与舍入
	reg signed [31:0] reg_key_delta;
	reg [31:0] reg_increment;
	reg [31:0] reg_target;
	reg [31:0] reg_next_level;
	reg [31:0] reg_status;
	reg [31:0] reg_mantissa;
	reg [4:0] reg_shift;
	wire flag_accept;
	wire [6:0] wire_note;
	wire [6:0] wire_velocity;
	wire [6:0] wire_output;
	wire [31:0] wire_profile;
	wire signed [9:0] wire_offset;
	wire [9:0] wire_distance;
	wire [6:0] wire_group;
	wire [9:0] wire_group_full;
	wire [1:0] wire_curve;
	wire [6:0] wire_depth;
	wire [5:0] wire_note_group;
	wire [6:0] wire_note_group_full;
	wire [5:0] wire_rate_group_full;
	wire flag_linear_curve;
	wire [6:0] wire_curve_address;
	wire [4:0] wire_rate_group;
	wire [7:0] wire_rate_product;
	wire signed [31:0] wire_vel_product;
	wire [31:0] wire_key_product;
	wire [6:0] wire_rate;
	wire signed [31:0] wire_scaled_output;
	wire signed [31:0] wire_limited_output;
	wire signed [31:0] wire_velocity_output;
	wire signed [31:0] wire_output_level;
	wire signed [31:0] wire_actual;
	reg [2:0] dec_stage;
	reg flag_dec_bad;
	reg [31:0] dec_level;
	reg [1:0] dec_index;
	reg [2:0] dec_result_stage;
	reg [31:0] dec_result_level;
	reg flag_reached;
	wire [31:0] wire_rising_level;
	wire [31:0] wire_distance_to_top;
	wire [31:0] wire_rising_step;
	reg [31:0] reg_rising_base, reg_rising_step; // 分开电平选择、增量乘法与最终到达判断
	reg [7:0] reg_rising_distance; // 原距离高8位，保持原32位减法回绕语义
	wire [32:0] wire_rising_next;
	wire [31:0] wire_falling_distance;

	initial begin
		$readmemh("rom/dx_rate.hex",mem_rate);
		$readmemh("rom/dx_exp2.hex",mem_exp);
		$readmemh("rom/dx_velocity.hex",mem_velocity);
		$readmemh("rom/dx_keyscale_product.hex",mem_keyscale_product);
	end

	assign o_s_axis_tready = i_axis_arstn && reg_state == 0;
	assign flag_accept = i_s_axis_tvalid && o_s_axis_tready;
	assign o_m_axis_tvalid = reg_state == 7;
	assign o_m_axis_tdata = reg_result;
	assign o_m_axis_tuser = reg_tag;
	assign wire_note = reg_request[326:320];
	assign wire_velocity = reg_request[333:327];
	assign wire_output = reg_request[340:334];
	assign wire_profile = reg_request[383:352];
	assign wire_offset = $signed({3'd0,wire_note}) - $signed({3'd0,wire_profile[6:0]}) - 10'sd17;
	assign wire_distance = wire_offset[9] ? -wire_offset : wire_offset;
	assign wire_group_full = wire_distance / 10'd3;
	assign wire_group = wire_group_full[6:0];
	assign wire_curve = wire_offset[9] ? wire_profile[22:21] : wire_profile[24:23];
	assign wire_depth = wire_offset[9] ? wire_profile[13:7] : wire_profile[20:14];
	assign wire_note_group_full = wire_note / 7'd3;
	assign wire_note_group = wire_note_group_full[5:0];
	assign wire_rate_group_full = wire_note_group-6'd7;
	assign wire_rate_group = wire_note_group < 7 ? 5'd0 : (wire_note_group > 38 ? 5'd31 : wire_rate_group_full[4:0]);
	assign flag_linear_curve = wire_curve == 0 || wire_curve == 3;
	assign wire_curve_address = {flag_linear_curve,wire_group[5:0]};
	assign wire_rate_product = wire_rate_group * wire_profile[27:25];
	assign wire_vel_product = reg_velocity_offset * $signed({1'b0,wire_profile[30:28]});
	// ROM contains the exact constant product; only the variable-depth multiply remains.
	assign wire_key_product = reg_curve_product * reg_depth;
	assign wire_rate = {1'b0,reg_base_rate}+{2'd0,reg_rate_scale};
	assign wire_scaled_output = $signed({25'd0,wire_output})+reg_key_delta;
	assign wire_limited_output = wire_scaled_output > 127 ? 32'sd127 : wire_scaled_output;
	assign wire_velocity_output = (wire_limited_output <<< 5)+reg_velocity_delta;
	assign wire_output_level = wire_velocity_output < 0 ? 32'sd0 : wire_velocity_output;
	assign wire_actual = $signed({19'd0,reg_scaled_level})+wire_output_level-32'sd4256;
	assign wire_rising_level = reg_level < C_JUMP ? C_JUMP : reg_level;
	assign wire_distance_to_top = 32'd285212672-wire_rising_level;
	assign wire_rising_step = reg_rising_distance*reg_increment;
	assign wire_rising_next = {1'b0,reg_rising_base}+{1'b0,reg_rising_step};
	assign wire_falling_distance = reg_level-reg_target;

	// Stage decode is isolated from the arithmetic state commit.
	always @(*) begin
		dec_stage = reg_request[34:32];
		dec_level = reg_request[31:0];
		flag_dec_bad = dec_stage > 5;
		if (reg_request[36:35] == 1) begin
			dec_stage = 1;
			flag_dec_bad = 0;
			if (reg_request[37]) dec_level = 0;
		end else if (reg_request[36:35] == 3) begin
			dec_stage = 0;
			dec_level = 0;
			flag_dec_bad = 0;
		end else if (flag_dec_bad) begin
			dec_stage = 0;
			dec_level = 0;
		end else if (reg_request[36:35] == 2 && dec_stage != 0) begin
			dec_stage = 5;
		end
		case (dec_stage)
			1: dec_index = 0;
			2: dec_index = 1;
			3: dec_index = 2;
			default: dec_index = 3;
		endcase
	end

	// One segment maximum per request, including an immediate zero-length segment.
	always @(*) begin
		dec_result_level = reg_level;
		dec_result_stage = reg_stage;
		flag_reached = 0;
		if (reg_stage == 1 || reg_stage == 2 || reg_stage == 3 || reg_stage == 5) begin
			if (reg_target > reg_level) begin
				if (wire_rising_next >= {1'b0,reg_target}) begin
					dec_result_level = reg_target;
					flag_reached = 1;
				end else dec_result_level = wire_rising_next[31:0];
			end else if (wire_falling_distance <= reg_increment) begin
				dec_result_level = reg_target;
				flag_reached = 1;
			end else dec_result_level = reg_level-reg_increment;
			if (flag_reached) dec_result_stage = reg_stage == 5 ? 3'd0 : reg_stage+3'd1;
		end
	end

	always @(*) begin
		dec_next_state = reg_state;
		case (reg_state)
			0: if (flag_accept) dec_next_state = 1;
			1,2,3,4,5,6: dec_next_state = reg_state+3'd1;
			7: if (i_m_axis_tready) dec_next_state = 0;
			default: dec_next_state = 0;
		endcase
	end

	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) reg_state <= 0;
		else reg_state <= dec_next_state;
	end

	// 电平在state4提交；state5只用已寄存地址查表，避免将更新逻辑串到BSRAM地址。
	always @(posedge i_axis_aclk) begin
		if (reg_state == 5) reg_mantissa <= mem_exp[reg_next_level[23:16]];
	end

	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) begin
			reg_request<=0; reg_tag<=0; reg_result<=0; reg_stage<=0; flag_bad<=0;
			reg_level<=0; reg_scaled_level<=0; reg_base_rate<=0; reg_rate_scale<=0;
			reg_curve_product<=0; reg_depth<=0; flag_negative<=0; reg_velocity_delta<=0;
			reg_key_delta<=0; reg_increment<=0; reg_target<=0; reg_next_level<=0;
			reg_status<=0; reg_shift<=0;
			reg_velocity_offset<=0; reg_rising_base<=0; reg_rising_distance<=0; reg_rising_step<=0;
		end else begin
			case (reg_state)
				0: if (flag_accept) begin
					reg_request<=i_s_axis_tdata;
					reg_tag<=i_s_axis_tuser;
				end
				1: begin
					reg_stage<=dec_stage; reg_level<=dec_level; flag_bad<=flag_dec_bad;
					reg_scaled_level<=reg_request[(2+dec_index)*32+:13];
					reg_base_rate<=reg_request[(6+dec_index)*32+:6];
					reg_rate_scale<=wire_rate_product[7:3];
					reg_depth<=wire_depth;
					flag_negative<=!wire_curve[1];
					reg_curve_product<=mem_keyscale_product[wire_curve_address];
					reg_velocity_offset<=$signed(mem_velocity[wire_velocity[6:1]])-32'sd239;
				end
				2: begin
					reg_velocity_delta<=((wire_vel_product+32'sd7) >>> 3) <<< 4;
					reg_rising_base<=wire_rising_level;
					reg_rising_distance<=wire_distance_to_top[31:24];
					reg_key_delta<=flag_negative ? -$signed(wire_key_product>>15) : $signed(wire_key_product>>15);
					reg_increment<=mem_rate[wire_rate > 63 ? 6'd63 : wire_rate[5:0]];
				end
				3: begin
					reg_target<=wire_actual < 16 ? C_FLOOR : wire_actual<<16;
					reg_rising_step<=wire_rising_step;
				end
				4: begin
					reg_next_level<=dec_result_level;
					reg_status<={25'd0,flag_bad,1'b0,flag_reached,(dec_result_stage!=0),dec_result_stage};
					reg_shift<=dec_result_level[31:24] >= 17 ? 5'd0 : 5'd17-dec_result_level[28:24];
				end
				6: begin
					reg_result[31:0]<=reg_next_level;
					reg_result[63:32]<=reg_status;
					reg_result[95:64]<=reg_status[2:0]==0 || reg_next_level<=C_FLOOR ? 32'd0 : reg_mantissa>>reg_shift;
				end
				default: reg_result<=reg_result;
			endcase
		end
	end
endmodule
