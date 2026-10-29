`timescale 1ns / 1ps
// UartRx: synchronized 8N1 receiver, midpoint start validation.
// 采样周期按核心时钟四舍五入，停止位错误不输出字节。
module UartRx #(
	parameter C_CLOCK_HZ = 98304000, parameter C_BAUD = 115200
)(input i_clk, input i_rstn, input i_rx,
	output [7:0] o_byte, output o_valid, output o_error);
	localparam C_DIV = (C_CLOCK_HZ + C_BAUD / 2) / C_BAUD;
	localparam ST_IDLE=0, ST_START=1, ST_DATA=2, ST_STOP=3;
	reg [1:0] state_current, state_next;
	reg [1:0] reg_sync;
	reg [15:0] cnt_baud;
	reg [2:0] cnt_bit;
	reg [7:0] reg_byte_o;
	reg flag_valid_o, flag_error_o;
	assign o_byte=reg_byte_o; assign o_valid=flag_valid_o; assign o_error=flag_error_o;
	always @(posedge i_clk or negedge i_rstn) begin
		if (!i_rstn) begin reg_sync<=2'b11; state_current<=ST_IDLE; end
		else begin reg_sync<={reg_sync[0],i_rx}; state_current<=state_next; end
	end
	always @(*) begin
		state_next=state_current;
		case(state_current)
			ST_IDLE: begin if (!reg_sync[1]) begin state_next=ST_START; end end
			ST_START: begin if (cnt_baud==C_DIV/2-1) begin
				if (!reg_sync[1]) begin state_next=ST_DATA; end
				else begin state_next=ST_IDLE; end
			end end
			ST_DATA: begin if ((cnt_baud==C_DIV-1)&&(cnt_bit==7)) begin state_next=ST_STOP; end end
			ST_STOP: begin if (cnt_baud==C_DIV-1) begin state_next=ST_IDLE; end end
			default: begin state_next=ST_IDLE; end
		endcase
	end
	always @(posedge i_clk or negedge i_rstn) begin
		if (!i_rstn) begin cnt_baud<=0; cnt_bit<=0; reg_byte_o<=0; flag_valid_o<=0; flag_error_o<=0; end
		else begin
			flag_valid_o<=0; flag_error_o<=0;
			case(state_current)
				ST_IDLE: begin cnt_baud<=0; cnt_bit<=0; end
				ST_START: begin
					if (cnt_baud==C_DIV/2-1) begin cnt_baud<=0; end
					else begin cnt_baud<=cnt_baud+1'b1; end
				end
				ST_DATA: begin
					if(cnt_baud==C_DIV-1) begin
						cnt_baud<=0; reg_byte_o[cnt_bit]<=reg_sync[1]; cnt_bit<=cnt_bit+1'b1;
					end else begin cnt_baud<=cnt_baud+1'b1; end
				end
				ST_STOP: begin
					if(cnt_baud==C_DIV-1) begin
						cnt_baud<=0; flag_valid_o<=reg_sync[1]; flag_error_o<=!reg_sync[1];
					end else begin cnt_baud<=cnt_baud+1'b1; end
				end
				default: begin cnt_baud<=0; end
			endcase
		end
	end
endmodule
