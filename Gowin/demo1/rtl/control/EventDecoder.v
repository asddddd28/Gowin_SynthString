`timescale 1ns / 1ps
// EventDecoder: fixed packet, checksum and inter-byte timeout.
// 收满八字节才提交；0xA5 出现在 payload 中不触发错误重同步。
module EventDecoder #(parameter C_TIMEOUT=983040)(
	input i_clk, input i_rstn, input i_valid, input [7:0] i_byte, input i_error,
	output o_valid, output [55:0] o_event, output o_error
);
	reg [3:0] cnt_byte;
	reg [31:0] cnt_timeout;
	reg [47:0] reg_payload;
	reg [7:0] reg_xor;
	reg [55:0] reg_event_o;
	reg flag_valid_o, flag_error_o;
	assign o_valid=flag_valid_o; assign o_event=reg_event_o; assign o_error=flag_error_o;
	always @(posedge i_clk or negedge i_rstn) begin
		if(!i_rstn) begin
			cnt_byte<=0; cnt_timeout<=0; reg_payload<=0; reg_xor<=0;
			reg_event_o<=0; flag_valid_o<=0; flag_error_o<=0;
		end else begin
			flag_valid_o<=0;
			if(i_error || ((cnt_byte!=0)&&(cnt_timeout==C_TIMEOUT-1))) begin
				cnt_byte<=0; cnt_timeout<=0; flag_error_o<=1;
			end else if(i_valid) begin
				cnt_timeout<=0;
				if(cnt_byte==0) begin
					if(i_byte==8'ha5) begin cnt_byte<=1; reg_xor<=8'ha5; end
				end else if(cnt_byte==7) begin
					cnt_byte<=0;
					if(i_byte==reg_xor) begin
						reg_event_o<={reg_payload[47:16],reg_payload[7:0],reg_payload[15:8],8'd0};
						flag_valid_o<=1;
					end else begin flag_error_o<=1; end
				end else begin
					reg_payload<={reg_payload[39:0],i_byte}; reg_xor<=reg_xor^i_byte;
					cnt_byte<=cnt_byte+1'b1;
				end
			end else if(cnt_byte!=0) begin cnt_timeout<=cnt_timeout+1'b1; end
		end
	end
endmodule
