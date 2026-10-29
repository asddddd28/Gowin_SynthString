`timescale 1ns / 1ps
// EnvelopeStep: one sample of a shared, saturating ADSR arithmetic unit.
// step=0 表示该段立即完成；偷音以固定 8192 步长退场。
module EnvelopeStep(
	input [2:0] i_stage, input [17:0] i_level,
	input [17:0] i_attack, input [17:0] i_decay,
	input [17:0] i_sustain, input [17:0] i_release,
	output [2:0] o_stage, output [17:0] o_level
);
	reg [2:0] dec_stage;
	reg [17:0] dec_level;
	wire [18:0] enc_attack_sum, enc_decay_limit;
	assign enc_attack_sum = {1'b0, i_level} + {1'b0, i_attack};
	assign enc_decay_limit = {1'b0, i_sustain} + {1'b0, i_decay};
	assign o_stage = dec_stage;
	assign o_level = dec_level;
	always @(*) begin
		dec_stage = i_stage; dec_level = i_level;
		case (i_stage)
			3'd1: begin
				if ((i_attack == 0) || (enc_attack_sum >= 19'd262143)) begin
					dec_level = 18'h3ffff; dec_stage = 2;
				end else begin dec_level = enc_attack_sum[17:0]; end
			end
			3'd2: begin
				if ((i_decay == 0) || ({1'b0, i_level} <= enc_decay_limit)) begin
					dec_level = i_sustain; dec_stage = 3;
				end else begin dec_level = i_level - i_decay; end
			end
			3'd3: begin dec_level = i_sustain; end
			3'd4: begin
				if ((i_release == 0) || (i_level <= i_release)) begin
					dec_level = 0; dec_stage = 0;
				end else begin dec_level = i_level - i_release; end
			end
			3'd5: begin
				if (i_level <= 8192) begin dec_level = 0; dec_stage = 0; end
				else begin dec_level = i_level - 18'd8192; end
			end
			default: begin dec_level = 0; dec_stage = 0; end
		endcase
	end
endmodule
