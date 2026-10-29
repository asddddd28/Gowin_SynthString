`timescale 1ns / 1ps
// StatusUart: nonblocking sixteen-byte telemetry frame.
// 查询忙时合并到下一次请求，串口发送绝不反压音频计算。
module StatusUart #(parameter C_CLOCK_HZ=98304000, parameter C_BAUD=115200)(
	input i_clk, input i_rstn, input i_request,
    input i_table_request,input [103:0] i_table_status,
    input i_pcm_request,input [103:0] i_pcm_status,
    input i_profile_request,input [103:0] i_profile_status,
	input [7:0] i_flags, input [7:0] i_voices, input [7:0] i_oscillators,
	input [15:0] i_cycles, input [31:0] i_clips, input [31:0] i_samples,
	output o_tx
);
	localparam C_DIV=(C_CLOCK_HZ+C_BAUD/2)/C_BAUD;
	reg [127:0] reg_packet;
	reg [9:0] reg_shift;
	reg [3:0] cnt_byte, cnt_bit;
	reg [15:0] cnt_baud;
	reg flag_busy, flag_request,flag_table_request,flag_profile_request,flag_pcm_request;
    wire [7:0] table_check,profile_check,pcm_check;
    assign pcm_check=8'ha5^8'h88^i_pcm_status[7:0]^i_pcm_status[15:8]^i_pcm_status[23:16]^i_pcm_status[31:24]^i_pcm_status[39:32]^i_pcm_status[47:40]^i_pcm_status[55:48]^i_pcm_status[63:56]^i_pcm_status[71:64]^i_pcm_status[79:72]^i_pcm_status[87:80]^i_pcm_status[95:88]^i_pcm_status[103:96];
    assign profile_check=8'ha5^8'h87^i_profile_status[7:0]^i_profile_status[15:8]^i_profile_status[23:16]^i_profile_status[31:24]^i_profile_status[39:32]^i_profile_status[47:40]^i_profile_status[55:48]^i_profile_status[63:56]^i_profile_status[71:64]^i_profile_status[79:72]^i_profile_status[87:80]^i_profile_status[95:88]^i_profile_status[103:96];
    assign table_check=8'ha5^8'h86^i_table_status[7:0]^i_table_status[15:8]^i_table_status[23:16]^i_table_status[31:24]^i_table_status[39:32]^i_table_status[47:40]^i_table_status[55:48]^i_table_status[63:56]^i_table_status[71:64]^i_table_status[79:72]^i_table_status[87:80]^i_table_status[95:88]^i_table_status[103:96];
	wire [7:0] enc_check;
	assign enc_check=8'ha5^8'h85^i_flags^i_voices^i_oscillators^i_cycles[7:0]^i_cycles[15:8]^i_clips[7:0]^i_clips[15:8]^i_clips[23:16]^i_clips[31:24]^i_samples[7:0]^i_samples[15:8]^i_samples[23:16]^i_samples[31:24];
	assign o_tx=flag_busy ? reg_shift[0] : 1'b1;
	always @(posedge i_clk or negedge i_rstn) begin
		if(!i_rstn) begin
			reg_packet<=0; reg_shift<=10'h3ff; cnt_byte<=0; cnt_bit<=0; cnt_baud<=0;
			flag_busy<=0; flag_request<=0;flag_table_request<=0;flag_profile_request<=0;flag_pcm_request<=0;
		end else begin
			if(i_request) begin flag_request<=1; end
            if(i_table_request) flag_table_request<=1;
            if(i_pcm_request) flag_pcm_request<=1;
            if(i_profile_request) flag_profile_request<=1;
			if(!flag_busy) begin
				if(flag_pcm_request) begin
                    reg_packet<={pcm_check,i_pcm_status,8'h88,8'ha5};
                    reg_shift<={1'b1,8'ha5,1'b0};cnt_byte<=0;cnt_bit<=0;cnt_baud<=0;
                    flag_busy<=1;flag_pcm_request<=i_pcm_request;
                end else if(flag_profile_request) begin
                    reg_packet<={profile_check,i_profile_status,8'h87,8'ha5};
                    reg_shift<={1'b1,8'ha5,1'b0};cnt_byte<=0;cnt_bit<=0;cnt_baud<=0;
                    flag_busy<=1;flag_profile_request<=i_profile_request;
                end else if(flag_table_request) begin
                    reg_packet<={table_check,i_table_status,8'h86,8'ha5};
                    reg_shift<={1'b1,8'ha5,1'b0};cnt_byte<=0;cnt_bit<=0;cnt_baud<=0;
                    flag_busy<=1;flag_table_request<=i_table_request;
                end else if(flag_request) begin
					reg_packet<={enc_check,i_samples[31:24],i_samples[23:16],i_samples[15:8],i_samples[7:0],i_clips[31:24],i_clips[23:16],i_clips[15:8],i_clips[7:0],i_cycles[15:8],i_cycles[7:0],i_oscillators,i_voices,i_flags,8'h85,8'ha5};
					reg_shift<={1'b1,8'ha5,1'b0}; cnt_byte<=0; cnt_bit<=0; cnt_baud<=0;
					flag_busy<=1; flag_request<=i_request;
				end
			end else if(cnt_baud==C_DIV-1) begin
				cnt_baud<=0;
				if(cnt_bit==9) begin
					cnt_bit<=0;
					if(cnt_byte==15) begin flag_busy<=0; end
					else begin
						cnt_byte<=cnt_byte+1'b1; reg_packet<=reg_packet>>8;
						reg_shift<={1'b1,reg_packet[15:8],1'b0};
					end
				end else begin cnt_bit<=cnt_bit+1'b1; reg_shift<={1'b1,reg_shift[9:1]}; end
			end else begin cnt_baud<=cnt_baud+1'b1; end
		end
	end
endmodule
