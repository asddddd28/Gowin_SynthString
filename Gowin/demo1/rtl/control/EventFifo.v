`timescale 1ns / 1ps
// EventFifo: ordered sixteen-entry event queue with sticky overflow.
// 满队列只丢弃新事件；同周期出队时允许写入，保持事件次序。
module EventFifo(
	input i_clk, input i_rstn, input i_clear,
	input i_valid, input [55:0] i_data, input i_ready,
	output o_valid, output [55:0] o_data, output o_overflow, output o_ready
);
	reg [55:0] reg_memory [0:15];
	reg [3:0] cnt_write, cnt_read;
	reg [4:0] cnt_used;
	reg flag_overflow_o;
	wire flag_pop, flag_push;
	assign o_valid = (cnt_used != 0);
	assign o_data = reg_memory[cnt_read];
	assign o_overflow = flag_overflow_o;
	assign flag_pop = i_ready && o_valid;
	assign o_ready = (cnt_used < 16) || flag_pop;
	assign flag_push = i_valid && o_ready;
	always @(posedge i_clk or negedge i_rstn) begin
		if (!i_rstn) begin
			cnt_write <= 0; cnt_read <= 0; cnt_used <= 0; flag_overflow_o <= 0;
		end else if (i_clear) begin
			cnt_write <= 0; cnt_read <= 0; cnt_used <= 0;
		end else begin
			if (flag_push) begin
				reg_memory[cnt_write] <= i_data;
				cnt_write <= cnt_write + 1'b1;
			end
			if (flag_pop) begin
				cnt_read <= cnt_read + 1'b1;
			end
			case ({flag_push, flag_pop})
				2'b10: begin cnt_used <= cnt_used + 1'b1; end
				2'b01: begin cnt_used <= cnt_used - 1'b1; end
				default: begin cnt_used <= cnt_used; end
			endcase
			if (i_valid && !flag_push) begin flag_overflow_o <= 1; end
		end
	end
endmodule
