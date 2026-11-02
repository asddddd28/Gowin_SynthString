`timescale 1ns / 1ps
// Complete stateless arithmetic operator. Contract: spec/AxisFmOperator_spec.md.
// The caller owns phase, EG and feedback history; accepting a result commits one sample.
module AxisFmOperator(
	input i_axis_aclk,
	input i_axis_arstn,
	input [671:0] i_s_axis_tdata,
	input [31:0] i_s_axis_tuser,
	input i_s_axis_tvalid,
	output o_s_axis_tready,
	output [159:0] o_m_axis_tdata,
	output [31:0] o_m_axis_tuser,
	output o_m_axis_tvalid,
	input i_m_axis_tready,
	input i_wave_write,
	input [10:0] i_wave_address,
	input [31:0] i_wave_data,
	output o_wave_ready
);
	localparam signed [31:0] Q_UNITY = 32'sd67108864;
	reg [3:0] reg_state;
	reg [3:0] dec_next_state;
	reg [671:0] reg_request;
	reg [31:0] reg_tag;
	reg signed [63:0] reg_mod_product;
	reg signed [63:0] reg_feedback_product;
	reg [31:0] reg_phase;
	reg [31:0] reg_lookup;
	reg [31:0] reg_noise;
	reg signed [31:0] mem_sine [0:1023];
	reg signed [31:0] mem_wave_low [0:1023];
	reg signed [31:0] mem_wave_high [0:1023];
	reg signed [31:0] reg_low_a, reg_low_b, reg_high_a, reg_high_b;
	reg signed [31:0] reg_analytic;
	reg signed [31:0] reg_interp_low, reg_interp_high;
	reg signed [31:0] reg_wave;
	reg signed [31:0] reg_factor;
	reg signed [63:0] reg_wave_product;
	reg signed [31:0] reg_scaled_wave;
	reg signed [63:0] reg_amp_product;
	reg signed [63:0] reg_sample_product;
	reg [63:0] reg_envelope;
	reg [31:0] reg_envelope_amplitude;
	reg [31:0] reg_dx_feedback;
	reg [159:0] reg_result;
	wire flag_accept;
	wire flag_eg_ready, flag_eg_valid;
	wire [63:0] wire_eg_result;
	wire [31:0] wire_eg_tag;
	wire flag_native_ready, flag_native_valid, flag_dx_ready, flag_dx_valid;
	wire [63:0] wire_native_result;
	wire [95:0] wire_dx_result;
	wire [31:0] wire_dx_tag;
	wire signed [32:0] wire_history_sum;
	wire signed [31:0] wire_history_average;
	wire signed [32:0] wire_low_delta, wire_high_delta;
	wire signed [55:0] wire_low_fraction, wire_high_fraction;
	wire signed [32:0] wire_morph_delta;
	wire signed [50:0] wire_morph_product;
	wire signed [55:0] wire_low_sum, wire_high_sum;
	wire signed [50:0] wire_morph_sum;
	wire [16:0] wire_morph;
	wire signed [33:0] wire_mod_unipolar;
	reg signed [31:0] dec_mod_target;
	wire signed [32:0] wire_factor_delta;
	wire signed [64:0] wire_factor_product;
	wire signed [31:0] wire_amplitude;
	wire [9:0] wire_neighbor;
	wire [31:0] wire_triangle_distance;
	wire [31:0] wire_lookup_next;
	wire [31:0] wire_phase_next;
	reg signed [32:0] dec_multiply_first, dec_multiply_second;
	reg signed [31:0] dec_factor_first, dec_factor_second;
	wire signed [64:0] wire_product_first=dec_multiply_first*dec_factor_first;
	wire signed [64:0] wire_product_second=dec_multiply_second*dec_factor_second;

	initial begin
		$readmemh("rom/sine_q26.hex", mem_sine);
		$readmemh("rom/sine_q26.hex", mem_wave_low);
		$readmemh("rom/sine_q26.hex", mem_wave_high);
	end

	function [31:0] noise_next;
		input [31:0] seed;
		reg [31:0] value;
		begin
			value = seed == 0 ? 32'd1 : seed;
			value = value ^ (value << 13);
			value = value ^ (value >> 17);
			noise_next = value ^ (value << 5);
		end
	endfunction

	// A compute request wins if a writer and a request arrive together.
	// Both producers may hold VALID without creating a circular wait.
	assign o_s_axis_tready = i_axis_arstn && reg_state == 0 && flag_eg_ready;
	assign flag_accept = i_s_axis_tvalid && o_s_axis_tready;
	assign o_wave_ready = i_axis_arstn && reg_state == 0 && !i_s_axis_tvalid;
	assign o_m_axis_tvalid = reg_state == 10;
	assign o_m_axis_tdata = reg_result;
	assign o_m_axis_tuser = reg_tag;
	assign wire_history_sum = {i_s_axis_tdata[511],i_s_axis_tdata[511:480]} + {i_s_axis_tdata[543],i_s_axis_tdata[543:512]};
	assign wire_history_average = wire_history_sum >>> 1;
	assign wire_phase_next = reg_request[31:0] + reg_request[63:32] +
		(reg_request[612:611] == 1 ? reg_mod_product[57:26] : 32'd0);
	assign wire_lookup_next = (reg_request[613] ? reg_request[31:0] : wire_phase_next) +
		(reg_request[613] ? reg_dx_feedback : reg_feedback_product[57:26]) +
		(reg_request[613] ? (reg_request[95:64] << 9) :
		(reg_request[612:611] == 0 ? reg_mod_product[57:26] : 32'd0));
	assign flag_eg_ready = i_s_axis_tdata[613] ? flag_dx_ready : flag_native_ready;
	assign flag_eg_valid = reg_request[613] ? flag_dx_valid : flag_native_valid;
	assign wire_eg_result = reg_request[613] ? wire_dx_result[63:0] : wire_native_result;
	assign wire_neighbor = reg_lookup[31:22] + 10'd1;
	assign wire_low_delta = {reg_low_b[31],reg_low_b} - {reg_low_a[31],reg_low_a};
	assign wire_high_delta = {reg_high_b[31],reg_high_b} - {reg_high_a[31],reg_high_a};
	assign wire_low_fraction = wire_low_delta * $signed({1'b0,reg_lookup[21:0]});
	assign wire_high_fraction = wire_high_delta * $signed({1'b0,reg_lookup[21:0]});
	assign wire_morph = reg_request[671:640] > 32'd65536 ? 17'd65536 : reg_request[656:640];
	assign wire_morph_delta = {reg_interp_high[31],reg_interp_high} - {reg_interp_low[31],reg_interp_low};
	assign wire_morph_product = wire_morph_delta * $signed({1'b0,wire_morph});
	assign wire_low_sum = reg_low_a + (wire_low_fraction >>> 22);
	assign wire_high_sum = reg_high_a + (wire_high_fraction >>> 22);
	assign wire_morph_sum = reg_interp_low + (wire_morph_product >>> 16);
	assign wire_mod_unipolar = ($signed({reg_request[95],reg_request[95:64]}) + 34'sd67108864) >>> 1;
	assign wire_factor_delta = $signed(dec_mod_target) - 33'sd67108864;
	assign wire_factor_product = wire_product_second;
	assign wire_amplitude = reg_amp_product[57:26];
	assign wire_triangle_distance = reg_lookup[31] ? reg_lookup - 32'h80000000 : 32'h80000000 - reg_lookup;

	// Share gain and phase products; interpolation and morph have dedicated lanes
	// so their subtract/multiply/add chains do not cross the shared input mux.
	always @(*) begin
		dec_multiply_first=0;dec_multiply_second=0;dec_factor_first=0;dec_factor_second=0;
		case (reg_state)
			0: begin
				dec_multiply_first={i_s_axis_tdata[95],i_s_axis_tdata[95:64]};dec_factor_first=i_s_axis_tdata[127:96];
				dec_multiply_second={wire_history_average[31],wire_history_average};dec_factor_second=i_s_axis_tdata[575:544];
			end
			4: begin
				dec_multiply_second=wire_factor_delta;dec_factor_second=reg_request[127:96];
			end
			5: begin dec_multiply_first={reg_wave[31],reg_wave};dec_factor_first=reg_factor;end
			7: begin dec_multiply_first={reg_envelope_amplitude[31],reg_envelope_amplitude};dec_factor_first=reg_request[159:128];end
			8: begin dec_multiply_first={reg_scaled_wave[31],reg_scaled_wave};dec_factor_first=wire_amplitude;end
			default: begin end
		endcase
	end

	// AM uses a unipolar source; ring modulation uses a bipolar source.
	always @(*) begin
		dec_mod_target = Q_UNITY;
		if (reg_request[612:611] == 2) begin
			if (wire_mod_unipolar < 0) dec_mod_target = 0;
			else if (wire_mod_unipolar > Q_UNITY) dec_mod_target = Q_UNITY;
			else dec_mod_target = wire_mod_unipolar[31:0];
		end else if (reg_request[612:611] == 3) begin
			if ($signed(reg_request[95:64]) < -Q_UNITY) dec_mod_target = -Q_UNITY;
			else if ($signed(reg_request[95:64]) > Q_UNITY) dec_mod_target = Q_UNITY;
			else dec_mod_target = reg_request[95:64];
		end
	end

	always @(*) begin
		dec_next_state = reg_state;
		case (reg_state)
			0: if (flag_accept) dec_next_state = 1;
			1,2,3,4,5,7,8,9: dec_next_state = reg_state + 1'b1;
			6: if (flag_eg_valid) dec_next_state = 7;
			10: if (i_m_axis_tready) dec_next_state = 0;
			default: dec_next_state = 0;
		endcase
	end
	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) reg_state <= 0;
		else reg_state <= dec_next_state;
	end

	// Table storage is initialized, not reset as thousands of flip-flops.
	// Writes are excluded from active computation by o_wave_ready.
	always @(posedge i_axis_aclk) begin
		if (i_wave_write && o_wave_ready) begin
			if (i_wave_address[10]) mem_wave_high[i_wave_address[9:0]] <= i_wave_data;
			else mem_wave_low[i_wave_address[9:0]] <= i_wave_data;
		end
		if (reg_state == 2) begin
			reg_low_a <= reg_request[610:608] == 5 ? mem_wave_low[reg_lookup[31:22]] : mem_sine[reg_lookup[31:22]];
			reg_low_b <= reg_request[610:608] == 5 ? mem_wave_low[wire_neighbor] : mem_sine[wire_neighbor];
			reg_high_a <= mem_wave_high[reg_lookup[31:22]];
			reg_high_b <= mem_wave_high[wire_neighbor];
		end
	end

	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) begin
			reg_request <= 0; reg_tag <= 0; reg_mod_product <= 0; reg_feedback_product <= 0;
			reg_phase <= 0; reg_lookup <= 0; reg_noise <= 0; reg_analytic <= 0;
			reg_interp_low <= 0; reg_interp_high <= 0; reg_wave <= 0; reg_factor <= 0;
			reg_wave_product <= 0; reg_scaled_wave <= 0; reg_amp_product <= 0;
			reg_sample_product <= 0; reg_envelope <= 0; reg_result <= 0;
			reg_envelope_amplitude <= 0; reg_dx_feedback <= 0;
		end else begin
			case (reg_state)
				0: if (flag_accept) begin
					reg_request <= i_s_axis_tdata;
					reg_tag <= i_s_axis_tuser;
					reg_mod_product <= wire_product_first[63:0];
					reg_feedback_product <= wire_product_second[63:0];
					reg_dx_feedback <= i_s_axis_tdata[546:544] == 0 ? 32'd0 : wire_history_average <<< ({1'b0,i_s_axis_tdata[546:544]}+4'd1);
					reg_noise <= noise_next(i_s_axis_tdata[607:576]);
				end
				1: begin reg_phase <= wire_phase_next; reg_lookup <= wire_lookup_next; end
				2: begin
					case (reg_request[610:608])
						1: reg_analytic <= Q_UNITY - (wire_triangle_distance >> 4);
						2: reg_analytic <= (reg_lookup >> 5) - Q_UNITY;
						3: reg_analytic <= reg_lookup < reg_request[671:640] ? Q_UNITY : -Q_UNITY;
						4: reg_analytic <= $signed(reg_noise) >>> 5;
						default: reg_analytic <= 0;
					endcase
				end
				3: begin
					reg_interp_low <= wire_low_sum[31:0];
					reg_interp_high <= wire_high_sum[31:0];
				end
				4: begin
					case (reg_request[610:608])
						0: reg_wave <= reg_interp_low;
						5: reg_wave <= wire_morph_sum[31:0];
						default: reg_wave <= reg_analytic;
					endcase
					reg_factor <= Q_UNITY + wire_factor_product[57:26];
				end
				5: reg_wave_product <= wire_product_first[63:0];
				6: begin
					reg_scaled_wave <= reg_wave_product[57:26];
					if (flag_eg_valid) begin
						reg_envelope <= wire_eg_result;
						reg_envelope_amplitude <= reg_request[613] ? wire_dx_result[95:64] : wire_eg_result[31:0];
					end
				end
				7: reg_amp_product <= wire_product_first[63:0];
				8: reg_sample_product <= wire_product_first[63:0];
				9: reg_result <= {reg_noise,reg_envelope,reg_phase,reg_sample_product[57:26]};
				default: reg_result <= reg_result;
			endcase
		end
	end
	AxisEnvelopeMulti Envelope_Inst(
		.i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),
		.i_s_axis_tdata(i_s_axis_tdata[479:160]),.i_s_axis_tuser(i_s_axis_tuser),
		.i_s_axis_tvalid(flag_accept && !i_s_axis_tdata[613]),.o_s_axis_tready(flag_native_ready),
		.o_m_axis_tdata(wire_native_result),.o_m_axis_tuser(wire_eg_tag),
		.o_m_axis_tvalid(flag_native_valid),.i_m_axis_tready(reg_state == 6 && !reg_request[613])
	);
	AxisDxEnvelope DxEnvelope_Inst(
		.i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),
		.i_s_axis_tdata({i_s_axis_tdata[671:640],11'd0,i_s_axis_tdata[634:614],i_s_axis_tdata[479:160]}),
		.i_s_axis_tuser(i_s_axis_tuser),.i_s_axis_tvalid(flag_accept && i_s_axis_tdata[613]),
		.o_s_axis_tready(flag_dx_ready),.o_m_axis_tdata(wire_dx_result),.o_m_axis_tuser(wire_dx_tag),
		.o_m_axis_tvalid(flag_dx_valid),.i_m_axis_tready(reg_state == 6 && reg_request[613])
	);
endmodule
