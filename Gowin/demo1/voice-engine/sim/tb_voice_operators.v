`timescale 1ns / 1ps
// Four independent task streams: arithmetic vectors, stalls, tag ordering and reset cancellation.
module tb_voice_operators(output o_done); // Expose suite completion to an enclosing simulation harness
	reg i_clk = 0; // 50 MHz validation clock
	reg i_rstn = 0; // Reset cancels tasks in every operator
	reg [511:0] reg_inputs = 0; // Four packed input snapshots
	reg [127:0] reg_tags = 0; // Independent tags include reset epoch
	reg [3:0] reg_valid = 0; // Source qualification per operator
	reg [3:0] reg_ready = 0; // Independent sink backpressure
	wire [3:0] wire_ready; // Operator acceptance
	wire [3:0] wire_valid; // Operator completion qualification
	wire [255:0] wire_results; // Four complete result words
	wire [127:0] wire_tags; // Returned transaction identifiers
	reg [191:0] reg_vectors [0:16383]; // Wide-integer reference packets and results
	integer cnt_total [0:3]; // Number of test vectors for each core
	integer cnt_sent [0:3]; // Accepted inputs in current reset epoch
	integer cnt_received [0:3]; // Completions in current reset epoch
	integer cnt_first [0:3]; // Cycle of first input transfer
	integer cnt_latency [0:3]; // Measured first-response latency
	reg [63:0] reg_held_data [0:3]; // Previous stalled output snapshot
	reg [31:0] reg_held_tag [0:3]; // Previous stalled output identity
	reg [3:0] flag_held = 0; // Outstanding output stability checks
	reg [3:0] flag_accepted = 0; // Input transfers captured at the real clock edge
	reg [31:0] reg_random = 32'h1256abcd; // Deterministic flow-control pattern
	integer cnt_cycle = 0; // Timeout and reset stimulus time base
	integer idx_load; // Vector file selector
	integer idx_check; // Scoreboard operator index
	integer idx_drive; // Driver operator index
	integer int_file; // Input vector file handle
	integer int_scan; // Parsed field count
	integer cnt_aborted = 0; // Transactions cancelled at reset
	reg [127:0] reg_packet; // File packet scratch
	reg [63:0] reg_expected; // File result scratch
	reg [31:0] reg_expected_tag; // Scoreboard identity expression
	reg flag_done = 0; // All active streams drained
	assign o_done = flag_done && cnt_cycle > 75; // Completion requires the post-reset epoch to finish

	AxisPhasePm Phase_Inst(
		.i_axis_aclk(i_clk), .i_axis_arstn(i_rstn),
		.i_s_axis_tdata(reg_inputs[127:0]), .i_s_axis_tuser(reg_tags[31:0]),
		.i_s_axis_tvalid(reg_valid[0]), .o_s_axis_tready(wire_ready[0]),
		.o_m_axis_tdata(wire_results[63:0]), .o_m_axis_tuser(wire_tags[31:0]),
		.o_m_axis_tvalid(wire_valid[0]), .i_m_axis_tready(reg_ready[0])
	);
	AxisEnvelopeSegment Envelope_Inst(
		.i_axis_aclk(i_clk), .i_axis_arstn(i_rstn),
		.i_s_axis_tdata(reg_inputs[255:128]), .i_s_axis_tuser(reg_tags[63:32]),
		.i_s_axis_tvalid(reg_valid[1]), .o_s_axis_tready(wire_ready[1]),
		.o_m_axis_tdata(wire_results[127:64]), .o_m_axis_tuser(wire_tags[63:32]),
		.o_m_axis_tvalid(wire_valid[1]), .i_m_axis_tready(reg_ready[1])
	);
	AxisGainMix Gain_Inst(
		.i_axis_aclk(i_clk), .i_axis_arstn(i_rstn),
		.i_s_axis_tdata(reg_inputs[383:256]), .i_s_axis_tuser(reg_tags[95:64]),
		.i_s_axis_tvalid(reg_valid[2]), .o_s_axis_tready(wire_ready[2]),
		.o_m_axis_tdata(wire_results[191:128]), .o_m_axis_tuser(wire_tags[95:64]),
		.o_m_axis_tvalid(wire_valid[2]), .i_m_axis_tready(reg_ready[2])
	);
	AxisNoiseStep Noise_Inst(
		.i_axis_aclk(i_clk), .i_axis_arstn(i_rstn),
		.i_s_axis_tdata(reg_inputs[511:384]), .i_s_axis_tuser(reg_tags[127:96]),
		.i_s_axis_tvalid(reg_valid[3]), .o_s_axis_tready(wire_ready[3]),
		.o_m_axis_tdata(wire_results[255:192]), .o_m_axis_tuser(wire_tags[127:96]),
		.o_m_axis_tvalid(wire_valid[3]), .i_m_axis_tready(reg_ready[3])
	);

	// Reference values originate in Python arbitrary-precision arithmetic.
	initial begin
		for(idx_load = 0; idx_load < 4; idx_load = idx_load + 1)begin
			case(idx_load)
				0: int_file = $fopen("vectors/AxisPhasePm.txt", "r");
				1: int_file = $fopen("vectors/AxisEnvelopeSegment.txt", "r");
				2: int_file = $fopen("vectors/AxisGainMix.txt", "r");
				default: int_file = $fopen("vectors/AxisNoiseStep.txt", "r");
			endcase
			if(int_file == 0)begin
				$fatal(1, "Missing vector file for operator %0d", idx_load);
			end
			cnt_total[idx_load] = 0;
			while(!$feof(int_file))begin
				int_scan = $fscanf(int_file, "%h %h\n", reg_packet, reg_expected);
				if(int_scan == 2)begin
					if(cnt_total[idx_load] >= 4096)begin
						$fatal(1, "Reference vector storage overflow");
					end
					reg_vectors[idx_load * 4096 + cnt_total[idx_load]] = {reg_packet, reg_expected};
					cnt_total[idx_load] = cnt_total[idx_load] + 1;
				end
			end
			$fclose(int_file);
		end
	end

	// One free-running domain; no clocks are synthesized by a task.
	always #10 i_clk = ~i_clk;

	// Change sources away from the capture edge and keep a stalled request stable.
	always@(negedge i_clk)begin
		if(cnt_cycle < 5 || (cnt_cycle >= 70 && cnt_cycle < 75))begin
			i_rstn = 0;
			reg_valid = 0;
			reg_ready = 0;
		end else begin
			i_rstn = 1;
			reg_random = reg_random ^ (reg_random << 13);
			reg_random = reg_random ^ (reg_random >> 17);
			reg_random = reg_random ^ (reg_random << 5);
			for(idx_drive = 0; idx_drive < 4; idx_drive = idx_drive + 1)begin
				if(!reg_valid[idx_drive] || flag_accepted[idx_drive])begin
					reg_valid[idx_drive] = cnt_sent[idx_drive] < cnt_total[idx_drive] &&
						(cnt_sent[idx_drive] < 40 || reg_random[idx_drive]);
					if(reg_valid[idx_drive])begin
						reg_inputs[idx_drive * 128 +: 128] =
							reg_vectors[idx_drive * 4096 + cnt_sent[idx_drive]][191:64];
						reg_tags[idx_drive * 32 +: 32] =
							(idx_drive << 24) | ((cnt_cycle >= 75) << 16) | cnt_sent[idx_drive];
					end
				end
				if(cnt_sent[idx_drive] < 40)begin
					reg_ready[idx_drive] = 1;
				end else if(cnt_cycle < 75 || (cnt_cycle % 181 >= 40 && cnt_cycle % 181 < 80))begin
					reg_ready[idx_drive] = 0;
				end else begin
					reg_ready[idx_drive] = reg_random[idx_drive + 8];
				end
			end
		end
	end

	// Check before NBA updates, matching the actual input and output handshake edges.
	always@(posedge i_clk)begin
		cnt_cycle = cnt_cycle + 1;
		if(cnt_cycle > 30000)begin
			$fatal(1, "Timeout while draining operators");
		end
		if(!i_rstn)begin
			if(wire_valid !== 4'd0 || wire_ready !== 4'd0)begin
				$fatal(1, "Reset must remove all transfer qualifications");
			end
			for(idx_check = 0; idx_check < 4; idx_check = idx_check + 1)begin
				if(cnt_cycle == 71)begin
					cnt_aborted = cnt_aborted + cnt_sent[idx_check] - cnt_received[idx_check];
				end
				cnt_sent[idx_check] = 0;
				cnt_received[idx_check] = 0;
				cnt_first[idx_check] = -1;
				cnt_latency[idx_check] = -1;
			end
			flag_held = 0;
			flag_accepted = 0;
		end else begin
			flag_done = 1;
			for(idx_check = 0; idx_check < 4; idx_check = idx_check + 1)begin
				flag_accepted[idx_check] = reg_valid[idx_check] && wire_ready[idx_check];
				if(flag_held[idx_check])begin
					if(!wire_valid[idx_check] ||
						wire_results[idx_check * 64 +: 64] !== reg_held_data[idx_check] ||
						wire_tags[idx_check * 32 +: 32] !== reg_held_tag[idx_check])begin
						$fatal(1, "Output changed under backpressure op=%0d", idx_check);
					end
				end
				flag_held[idx_check] = wire_valid[idx_check] && !reg_ready[idx_check];
				reg_held_data[idx_check] = wire_results[idx_check * 64 +: 64];
				reg_held_tag[idx_check] = wire_tags[idx_check * 32 +: 32];
				if(wire_valid[idx_check] && reg_ready[idx_check])begin
					if(cnt_received[idx_check] >= cnt_sent[idx_check])begin
						$fatal(1, "Unsolicited completion op=%0d", idx_check);
					end
					reg_expected_tag = (idx_check << 24) | ((cnt_cycle >= 75) << 16) | cnt_received[idx_check];
					if(wire_tags[idx_check * 32 +: 32] !== reg_expected_tag ||
						wire_results[idx_check * 64 +: 64] !== reg_vectors[idx_check * 4096 + cnt_received[idx_check]][63:0])begin
						$fatal(1, "Mismatch op=%0d index=%0d result=%h expected=%h tag=%h",
							idx_check, cnt_received[idx_check], wire_results[idx_check * 64 +: 64],
							reg_vectors[idx_check * 4096 + cnt_received[idx_check]][63:0],
							wire_tags[idx_check * 32 +: 32]);
					end
					if(cnt_received[idx_check] == 0)begin
						cnt_latency[idx_check] = cnt_cycle - cnt_first[idx_check];
						if(cnt_latency[idx_check] != (idx_check == 0 ? 3 : 4))begin
							$fatal(1, "Unexpected minimum latency op=%0d cycles=%0d", idx_check, cnt_latency[idx_check]);
						end
					end
					cnt_received[idx_check] = cnt_received[idx_check] + 1;
				end
				if(reg_valid[idx_check] && wire_ready[idx_check])begin
					if(cnt_sent[idx_check] == 0)begin
						cnt_first[idx_check] = cnt_cycle;
					end else if(cnt_sent[idx_check] < 32 && cnt_cycle != cnt_first[idx_check] + cnt_sent[idx_check])begin
						$fatal(1, "Unstalled initiation interval is not one op=%0d", idx_check);
					end
					cnt_sent[idx_check] = cnt_sent[idx_check] + 1;
				end
				if(cnt_received[idx_check] != cnt_total[idx_check])begin
					flag_done = 0;
				end
			end
			if(flag_done && cnt_cycle > 75)begin
				if(cnt_aborted < 4)begin
					$fatal(1, "Reset coverage did not cancel pending work");
				end
				$display("PASS operators: PM=%0d ENV=%0d GAIN=%0d NOISE=%0d; cancelled=%0d; cycles=%0d",
					cnt_total[0], cnt_total[1], cnt_total[2], cnt_total[3], cnt_aborted, cnt_cycle);
				$display("PASS minimum transfer latency: 3 / 4 / 4 / 4 cycles; unstalled II=1; stable stalled outputs; no stale reset tags");
				$finish;
			end
		end
	end
endmodule

