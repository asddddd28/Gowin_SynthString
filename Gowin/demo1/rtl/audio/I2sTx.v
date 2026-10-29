`timescale 1ns / 1ps
// I2sTx: 1024/C_FRAME_STEP core cycles/frame; C_FRAME_STEP is 1 or 2.
// I²S 串行器：新声道标志提前一位，下降沿改变数据，上升沿采样。
module I2sTx #(parameter C_PT8211=0, parameter C_FRAME_STEP=1)(
	input i_clk, input i_rstn,
	input i_sample_valid, input signed [23:0] i_left, input signed [23:0] i_right,
	output o_sample_tick, output o_bclk, output o_lrclk, output o_sdata,
	output o_mclk, output o_underrun
);
	reg [9:0] cnt_frame;
	reg signed [23:0] reg_pending_left, reg_pending_right;
	reg signed [23:0] reg_play_left, reg_play_right;
	reg flag_pending, flag_started;
	reg reg_sdata_o, flag_underrun_o;
	wire flag_frame_start;
	wire [5:0] enc_bit;
    wire signed [15:0] wire_rounded_left,wire_rounded_right;
    wire signed [23:0] wire_input_left=C_PT8211 ? {wire_rounded_left,8'd0} : i_left;
    wire signed [23:0] wire_input_right=C_PT8211 ? {wire_rounded_right,8'd0} : i_right;
    PcmRounder LeftRound_Inst(.i_sample(i_left),.o_sample(wire_rounded_left));
    PcmRounder RightRound_Inst(.i_sample(i_right),.o_sample(wire_rounded_right));
	assign flag_frame_start = (cnt_frame == 10'd0);
	assign enc_bit = C_PT8211 ? {1'b0,cnt_frame[9:5]} : cnt_frame[9:4];
	assign o_sample_tick = flag_frame_start;
	assign o_bclk = C_PT8211 ? cnt_frame[4] : cnt_frame[3];
	assign o_lrclk = C_PT8211 ? !cnt_frame[9] : cnt_frame[9];
	assign o_mclk = cnt_frame[1];
	assign o_sdata = reg_sdata_o;
	assign o_underrun = flag_underrun_o;
	// 帧计数同时给出三个同源时钟，所有内部逻辑仍使用 i_clk。
	always @(posedge i_clk or negedge i_rstn) begin
		if (!i_rstn) begin
			cnt_frame <= 10'd0;
		end else begin
			cnt_frame <= cnt_frame + C_FRAME_STEP;
		end
	end
	// 播放端只在完整帧边界读取待播放采样，同时到达时可直接旁路。
	always @(posedge i_clk or negedge i_rstn) begin
		if (!i_rstn) begin
			reg_pending_left <= 0; reg_pending_right <= 0;
			reg_play_left <= 0; reg_play_right <= 0;
			flag_pending <= 0; flag_started <= 0; flag_underrun_o <= 0;
		end else begin
			if (i_sample_valid) begin
				reg_pending_left <= wire_input_left; reg_pending_right <= wire_input_right;
				flag_pending <= 1;
			end
			if (flag_frame_start) begin
				flag_started <= 1;
				flag_pending <= 0;
				if (i_sample_valid) begin
						reg_play_left <= wire_input_left; reg_play_right <= wire_input_right;
				end else if (flag_pending) begin
					reg_play_left <= reg_pending_left; reg_play_right <= reg_pending_right;
				end else if (flag_started) begin
					flag_underrun_o <= 1;
				end
			end
		end
	end
	// I2S: 位置 0 延迟，1..24 有效。PT8211: 每声道恰好 16 位，无延迟位。
	always @(posedge i_clk or negedge i_rstn) begin
		if (!i_rstn) begin
			reg_sdata_o <= 0;
		end else if (C_PT8211 ? (cnt_frame[4:0] == C_FRAME_STEP) : (cnt_frame[3:0] == 0)) begin
			if (C_PT8211) begin
                // PT8211: exactly 16 BCKs per channel, WS high=left, 24-bit PCM MSBs.
                if(enc_bit<16) reg_sdata_o<=reg_play_left[23-enc_bit];
                else reg_sdata_o<=reg_play_right[39-enc_bit];
            end else if ((enc_bit >= 1) && (enc_bit <= 24)) begin
				reg_sdata_o <= reg_play_left[24 - enc_bit];
			end else if ((enc_bit >= 33) && (enc_bit <= 56)) begin
				reg_sdata_o <= reg_play_right[56 - enc_bit];
			end else begin
				reg_sdata_o <= 0;
			end
		end
	end
endmodule
