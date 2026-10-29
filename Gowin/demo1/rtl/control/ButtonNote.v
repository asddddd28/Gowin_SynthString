`timescale 1ns / 1ps
// ButtonNote: active-low test key, sample-clock debounce, retained event.
// 稳定 960 帧约 10ms 后生成音符事件；握手前保持事件，快速反向会排在后续。
module ButtonNote #(parameter C_DEBOUNCE=960)(
	input i_clk, input i_rstn, input i_tick, input i_key_n, input i_ready,
	output o_valid, output [55:0] o_event
);
	reg [1:0] reg_sync;
	reg flag_stable, flag_sent;
	reg [15:0] cnt_stable;
	assign o_valid=flag_sent!=flag_stable;
	assign o_event={flag_stable ? 8'd2 : 8'd1,8'hff,8'd69,8'd96,24'd0};
	always @(posedge i_clk or negedge i_rstn) begin
		if(!i_rstn) begin reg_sync<=3; flag_stable<=1; flag_sent<=1; cnt_stable<=0; end
		else begin
			reg_sync<={reg_sync[0],i_key_n};
			if(o_valid && i_ready) begin flag_sent<=flag_stable; end
			if(i_tick) begin
				if(reg_sync[1]==flag_stable) begin cnt_stable<=0; end
				else if(cnt_stable==C_DEBOUNCE-1) begin flag_stable<=reg_sync[1]; cnt_stable<=0; end
				else begin cnt_stable<=cnt_stable+1'b1; end
			end
		end
	end
endmodule
