`timescale 1ns / 1ps
// SynthSystem: UART and future controller events into a continuous audio stream.
// 系统集成：UART 优先，外部接口次之，消抖按键最后；外部接口必须遵守握手。
module SynthSystem #(parameter C_VOICES=8, parameter C_CLOCK_HZ=98304000, parameter C_PT8211=0,
    parameter C_LINK_TIMEOUT_FRAMES=192000, parameter C_FRAME_STEP=1)(
	input i_clk, input i_rstn, input i_uart_rx, input i_key_n, input i_panic,
	input i_note_valid, input [55:0] i_note_event, output o_note_ready,
	output o_uart_tx, output o_mclk, output o_bclk, output o_lrclk, output o_sdata,
	output [7:0] o_flags, output [7:0] o_voices, output [7:0] o_oscillators,
	output [15:0] o_max_cycles, output [31:0] o_clips,
	output o_sample_valid, output signed [23:0] o_sample
);
	wire [7:0] wire_byte;
	wire flag_byte, flag_rx_error, flag_packet, flag_packet_error;
	wire [55:0] wire_packet, wire_button, wire_event;
	wire flag_button, flag_event, flag_take, flag_fifo_overflow;
	wire flag_tick, flag_busy, flag_overrun, flag_underrun, flag_status;
	wire [31:0] wire_samples;
    wire signed [23:0] wire_bank_sample;
    wire flag_bank_sample;
    wire [31:0] wire_bank_clips,wire_output_clips;
    assign o_clips=wire_bank_clips+wire_output_clips;
	wire flag_panic;
    wire flag_table_command=(wire_packet[55:52]==4'h1)||(wire_packet[55:52]==4'h2)||(wire_packet[55:52]==4'h3)||(wire_packet[55:52]==4'h4);
    wire pcm_write,pcm_available;wire [13:0] pcm_address;wire [15:0] pcm_data;
    wire [14:0] pcm_loop_start,pcm_loop_end;wire [6:0] pcm_root;wire [103:0] pcm_status;
    PcmUpload Pcm_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_packet(flag_packet),.i_event(wire_packet),
      .i_frame_idle(flag_tick&&!flag_busy&&(o_voices==0)),.o_write(pcm_write),.o_address(pcm_address),.o_data(pcm_data),
      .o_available(pcm_available),.o_loop_start(pcm_loop_start),.o_loop_end(pcm_loop_end),.o_root(pcm_root),.o_status(pcm_status));
    wire profile_write;wire [4:0] profile_address;wire [287:0] profile_data;wire [103:0] profile_status;
    ProfileUpload Profile_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_packet(flag_packet),.i_event(wire_packet),
        .o_write(profile_write),.o_address(profile_address),.o_data(profile_data),.o_status(profile_status));
    wire table_write,table_bank,table_available;
    wire table_frame,table_two;wire [4:0] position_query;wire [15:0] position_status;
    reg flag_table_request;
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) flag_table_request<=0;
        else flag_table_request<=flag_packet&&(wire_packet[55:48]==8'h16||wire_packet[55:48]==8'h46);
    end
    wire [10:0] table_address;wire [15:0] table_data;wire [103:0] table_status;
    WavetableUpload Upload_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_packet(flag_packet),.i_event(wire_packet),
      .o_frame(table_frame),.o_two(table_two),.i_position_status(position_status),.o_query_key(position_query),
      .i_frame_idle(flag_tick&&!flag_busy&&(o_voices==0)),.o_write(table_write),.o_address(table_address),
      .o_data(table_data),.o_bank(table_bank),.o_available(table_available),.o_status(table_status));
	wire flag_fifo_ready;
    reg [17:0] cnt_link_idle;
    reg flag_link_armed, flag_link_expired;
    // USB 会话从串口 NoteOn 开始；有效包续租，断流约两秒后停止所有声部。
    // 本地按键单独使用时不启用看门狗。显式 PANIC 同时结束会话。
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin cnt_link_idle<=0; flag_link_armed<=0; flag_link_expired<=0; end
        else begin
            flag_link_expired<=0;
            if(i_panic || (flag_packet && wire_packet[55:48]==4)) begin
                cnt_link_idle<=0; flag_link_armed<=0;
            end else if(flag_packet) begin
                cnt_link_idle<=0;
                if(wire_packet[55:48]==1) flag_link_armed<=1;
            end else if(flag_tick && flag_link_armed) begin
                if(cnt_link_idle==C_LINK_TIMEOUT_FRAMES-1) begin
                    cnt_link_idle<=0; flag_link_armed<=0; flag_link_expired<=1;
                end else cnt_link_idle<=cnt_link_idle+1'b1;
            end
        end
    end
	assign flag_panic=i_panic || flag_link_expired || (flag_packet && wire_packet[55:48]==4);
	assign o_note_ready=!flag_packet && !flag_panic && flag_fifo_ready;
	assign o_flags={2'b00,flag_busy,1'b0,flag_packet_error,flag_fifo_overflow,flag_overrun,flag_underrun};
	UartRx #(.C_CLOCK_HZ(C_CLOCK_HZ)) Receiver_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_rx(i_uart_rx),.o_byte(wire_byte),.o_valid(flag_byte),.o_error(flag_rx_error));
	EventDecoder Decoder_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_valid(flag_byte),.i_byte(wire_byte),.i_error(flag_rx_error),.o_valid(flag_packet),.o_event(wire_packet),.o_error(flag_packet_error));
	ButtonNote Button_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_tick(flag_tick),.i_key_n(i_key_n),.i_ready(!flag_packet&&!i_note_valid&&!flag_panic&&flag_fifo_ready),.o_valid(flag_button),.o_event(wire_button));
	EventFifo Events_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_clear(flag_panic),
		.i_valid(((flag_packet&&!flag_table_command)||(i_note_valid&&o_note_ready)||(flag_button&&flag_fifo_ready))&&!flag_panic),
		.i_data(flag_packet ? wire_packet : (i_note_valid ? i_note_event : wire_button)),
		.i_ready(flag_take),.o_valid(flag_event),.o_data(wire_event),.o_overflow(flag_fifo_overflow),.o_ready(flag_fifo_ready));
	VoicePair #(.C_VOICES(C_VOICES)) Bank_Inst(.i_pcm_write(pcm_write),.i_pcm_address(pcm_address),.i_pcm_data(pcm_data),
        .i_table_frame(table_frame),.i_table_two(table_two),
        .i_position_write(flag_packet&&wire_packet[55:48]==8'h44&&wire_packet[47:45]==3'b001&&wire_packet[39:24]==0),
        .i_position_address(wire_packet[44:40]),.i_position_data(wire_packet[23:8]),.i_position_query(position_query),.o_position_status(position_status),
        .i_pcm_available(pcm_available),.i_pcm_loop_start(pcm_loop_start),.i_pcm_loop_end(pcm_loop_end),.i_pcm_root(pcm_root),.i_profile_write(profile_write),.i_profile_address(profile_address),.i_profile_data(profile_data),.i_table_write(table_write),.i_table_address(table_address),.i_table_data(table_data),
        .i_table_bank(table_bank),.i_table_available(table_available),.i_clk(i_clk),.i_rstn(i_rstn),.i_tick(flag_tick),.i_panic(flag_panic),
		.i_event_valid(flag_event),.i_event(wire_event),.o_event_ready(flag_take),
		.o_sample(wire_bank_sample),.o_sample_valid(flag_bank_sample),.o_busy(flag_busy),.o_overrun(flag_overrun),
		.o_active_voices(o_voices),.o_active_oscillators(o_oscillators),.o_max_cycles(o_max_cycles),
		.o_clip_count(wire_bank_clips),.o_sample_count(wire_samples),.o_status_request(flag_status));
    OutputGain Output_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_panic(flag_panic),
        .i_gain_write(flag_take&&flag_event&&wire_event[55:48]==3&&wire_event[47:40]==12&&wire_event[23:8]<=4),
        .i_shift(wire_event[10:8]),.i_sample_valid(flag_bank_sample),.i_sample(wire_bank_sample),
        .o_sample_valid(o_sample_valid),.o_sample(o_sample),.o_clips(wire_output_clips));
	I2sTx #(.C_PT8211(C_PT8211),.C_FRAME_STEP(C_FRAME_STEP)) Audio_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_sample_valid(o_sample_valid),.i_left(o_sample),.i_right(o_sample),
		.o_sample_tick(flag_tick),.o_bclk(o_bclk),.o_lrclk(o_lrclk),.o_sdata(o_sdata),.o_mclk(o_mclk),.o_underrun(flag_underrun));
	StatusUart #(.C_CLOCK_HZ(C_CLOCK_HZ)) Telemetry_Inst(.i_pcm_request(flag_packet&&wire_packet[55:48]==8'h36),.i_pcm_status(pcm_status),.i_profile_request(flag_packet&&wire_packet[55:48]==8'h27),.i_profile_status(profile_status),.i_table_request(flag_table_request),.i_table_status(table_status),.i_clk(i_clk),.i_rstn(i_rstn),.i_request(flag_status),
		.i_flags(o_flags),.i_voices(o_voices),.i_oscillators(o_oscillators),.i_cycles(o_max_cycles),.i_clips(o_clips),.i_samples(wire_samples),.o_tx(o_uart_tx));
endmodule
