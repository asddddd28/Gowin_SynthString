`timescale 1ns / 1ps
// ResetSync: asynchronous assertion, two-clock synchronous release.
// 复位同步：外部复位立即置位，两个核心时钟后释放。
module ResetSync(input i_clk, input i_rstn, output o_rstn);
	reg [1:0] reg_release;
	assign o_rstn = reg_release[1];
	always @(posedge i_clk or negedge i_rstn) begin
		if (!i_rstn) begin
			reg_release <= 2'b00;
		end else begin
			reg_release <= {reg_release[0], 1'b1};
		end
	end
endmodule
