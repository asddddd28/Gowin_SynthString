`timescale 1ns / 1ps
// Stateless LFO arithmetic. State ownership and packet units: spec/AxisLfoStep_spec.md.
module AxisLfoStep(
	input i_axis_aclk,
	input i_axis_arstn,
	input [255:0] i_s_axis_tdata,
	input [31:0] i_s_axis_tuser,
	input i_s_axis_tvalid,
	output o_s_axis_tready,
	output [159:0] o_m_axis_tdata,
	output [31:0] o_m_axis_tuser,
	output o_m_axis_tvalid,
	input i_m_axis_tready
);
	localparam signed [31:0] Q_UNITY = 32'sd67108864;
	reg [4:0] flag_valid;
	reg [4:0] flag_unipolar;
	wire flag_advance = !flag_valid[4] || i_m_axis_tready;
	wire flag_restart = i_s_axis_tdata[132];
	wire [32:0] wire_phase_sum = {1'b0,i_s_axis_tdata[31:0]} + {1'b0,i_s_axis_tdata[63:32]};
	wire flag_wrap = wire_phase_sum[32] && !flag_restart;
	wire [31:0] wire_rng_current = i_s_axis_tdata[95:64] == 0 ? 32'd1 : i_s_axis_tdata[95:64];
	wire [31:0] wire_seed = i_s_axis_tdata[223:192] == 0 ? 32'd1 : i_s_axis_tdata[223:192];
	wire [31:0] wire_rng_base = flag_restart ? wire_seed : wire_rng_current;
	wire [31:0] wire_rng_shift = wire_rng_base ^ (wire_rng_base << 13);
	wire [31:0] wire_rng_middle = wire_rng_shift ^ (wire_rng_shift >> 17);
	wire [31:0] wire_rng_next = wire_rng_middle ^ (wire_rng_middle << 5);
	wire [31:0] wire_phase_next = flag_restart ? i_s_axis_tdata[191:160] : wire_phase_sum[31:0];
	wire [31:0] wire_rng_commit = flag_restart || flag_wrap ? wire_rng_next : wire_rng_current;
	wire signed [31:0] wire_random_origin = $signed(wire_rng_base) >>> 5;
	wire [31:0] wire_held_next = flag_restart || flag_wrap ? wire_random_origin : i_s_axis_tdata[127:96];
	reg [127:0] reg_meta_first, reg_meta_second, reg_meta_third, reg_meta_fourth, reg_meta_fifth;
	reg [31:0] reg_tag_first, reg_tag_second, reg_tag_third, reg_tag_fourth, reg_tag_fifth;
	reg [2:0] reg_shape_first, reg_shape_second, reg_shape_third;
	reg [31:0] reg_width;
	reg signed [31:0] mem_sine [0:1023];
	reg signed [31:0] reg_sine_low, reg_sine_high, reg_sine_base;
	reg signed [31:0] reg_analytic_second, reg_analytic_third;
	reg signed [55:0] reg_sine_fraction;
	reg signed [65:0] reg_random_fraction, reg_random_delayed;
	reg signed [31:0] reg_wave, reg_value;
	wire [31:0] wire_phase_first = reg_meta_first[31:0];
	wire [9:0] wire_neighbor = wire_phase_first[31:22] + 10'd1;
	wire [31:0] wire_distance = wire_phase_first[31] ? wire_phase_first-32'h80000000 : 32'h80000000-wire_phase_first;
	wire signed [31:0] wire_random_target = $signed(reg_meta_first[63:32]) >>> 5;
	wire signed [32:0] wire_random_delta = {wire_random_target[31],wire_random_target} - $signed({reg_meta_first[95],reg_meta_first[95:64]});
	wire signed [32:0] wire_sine_delta = {reg_sine_high[31],reg_sine_high} - {reg_sine_low[31],reg_sine_low};
	wire signed [55:0] wire_sine_value = reg_sine_base + (reg_sine_fraction >>> 22);
	wire signed [65:0] wire_random_value = $signed(reg_meta_third[95:64]) + (reg_random_delayed >>> 32);
	wire signed [32:0] wire_unipolar = ($signed({reg_wave[31],reg_wave}) + 33'sd67108864) >>> 1;

	initial $readmemh("rom/sine_q26.hex",mem_sine);
	assign o_s_axis_tready = i_axis_arstn && flag_advance;
	assign o_m_axis_tvalid = flag_valid[4];
	assign o_m_axis_tdata = {reg_meta_fifth,reg_value};
	assign o_m_axis_tuser = reg_tag_fifth;

	// Synchronous ROM reads have the same clock enable as all metadata stages.
	always @(posedge i_axis_aclk) begin
		if (flag_advance && flag_valid[0]) begin
			reg_sine_low <= mem_sine[wire_phase_first[31:22]];
			reg_sine_high <= mem_sine[wire_neighbor];
		end
	end
	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) begin
			flag_valid <= 0;
			flag_unipolar <= 0;
			reg_meta_first <= 0;
			reg_meta_second <= 0;
			reg_meta_third <= 0;
			reg_meta_fourth <= 0;
			reg_meta_fifth <= 0;
			reg_tag_first <= 0;
			reg_tag_second <= 0;
			reg_tag_third <= 0;
			reg_tag_fourth <= 0;
			reg_tag_fifth <= 0;
			reg_shape_first <= 0;
			reg_shape_second <= 0;
			reg_shape_third <= 0;
			reg_width <= 0;
			reg_sine_base <= 0;
			reg_analytic_second <= 0;
			reg_analytic_third <= 0;
			reg_sine_fraction <= 0;
			reg_random_fraction <= 0;
			reg_random_delayed <= 0;
			reg_wave <= 0;
			reg_value <= 0;
		end else if (flag_advance) begin
			flag_valid <= {flag_valid[3:0],i_s_axis_tvalid};
			flag_unipolar <= {flag_unipolar[3:0],i_s_axis_tdata[131]};
			reg_meta_first <= {30'd0,flag_restart,flag_wrap,wire_held_next,wire_rng_commit,wire_phase_next};
			reg_meta_second <= reg_meta_first;
			reg_meta_third <= reg_meta_second;
			reg_meta_fourth <= reg_meta_third;
			reg_meta_fifth <= reg_meta_fourth;
			reg_tag_first <= i_s_axis_tuser;
			reg_tag_second <= reg_tag_first;
			reg_tag_third <= reg_tag_second;
			reg_tag_fourth <= reg_tag_third;
			reg_tag_fifth <= reg_tag_fourth;
			reg_shape_first <= i_s_axis_tdata[130:128];
			reg_shape_second <= reg_shape_first;
			reg_shape_third <= reg_shape_second;
			reg_width <= i_s_axis_tdata[255:224];
			case (reg_shape_first)
				1: reg_analytic_second <= Q_UNITY - (wire_distance >> 4);
				2: reg_analytic_second <= (wire_phase_first >> 5) - Q_UNITY;
				3: reg_analytic_second <= Q_UNITY - (wire_phase_first >> 5);
				4: reg_analytic_second <= wire_phase_first < reg_width ? Q_UNITY : -Q_UNITY;
				5: reg_analytic_second <= wire_random_target;
				default: reg_analytic_second <= 0;
			endcase
			reg_analytic_third <= reg_analytic_second;
			reg_random_fraction <= wire_random_delta * $signed({1'b0,wire_phase_first});
			reg_random_delayed <= reg_random_fraction;
			reg_sine_fraction <= wire_sine_delta * $signed({1'b0,reg_meta_second[21:0]});
			reg_sine_base <= reg_sine_low;
			case (reg_shape_third)
				0: reg_wave <= wire_sine_value[31:0];
				6: reg_wave <= wire_random_value[31:0];
				default: reg_wave <= reg_analytic_third;
			endcase
			reg_value <= flag_unipolar[3] ? wire_unipolar[31:0] : reg_wave;
		end
	end
endmodule
