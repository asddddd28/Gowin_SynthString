`timescale 1ns / 1ps
// Contract: spec/SynthSystemTop_spec.md.
module SynthSystemTop #(parameter C_UART_CYCLES=434,parameter C_SETTLE_CYCLES=10000,parameter C_HALF_CYCLES=6,parameter C_POWERUP_CYCLES=65535,parameter C_AMP_CYCLES=1048576,parameter C_DELAY_ADDR_BITS=13,parameter C_FX_ENABLE=0,parameter C_DISPLAY_ENABLE=0,parameter C_TOUCH_ENABLE=0,parameter C_SEQUENCE_ENABLE=0)(
    input [5:0] i_buttons,
    output [31:0] o_sequence_status,
    output [8:0] o_sequence_bpm,
    input i_touch_next,inout [1:0] io_touch_scl,inout [1:0] io_touch_sda,output [1:0] o_touch_mode,
    input i_clk,
    input i_rstn,
    input i_adc_dout,
    input i_uart_rx,
    output [2:0] o_mux_sel,
    output o_mux_en,
    output o_adc_cs_n,
    output o_adc_sclk,
    output o_adc_din,
    output o_uart_tx,
    output HP_BCK,
    output HP_WS,
    output HP_DIN,
    output PA_EN,
    output o_display_reset_n,
    output o_display_calibrating,
    output [31:0] o_display_keys,
    output [31:0] o_display_latency,
    output [31:0] o_display_underruns,
    output [31:0] o_display_errors,
    output [31:0] o_display_frames,
    output o_display_sample_valid,
    output [15:0] o_display_sample,
    output o_display_request,
    output [7:0] o_display_opcode,
    output [7:0] o_display_argument,
    output [63:0] o_display_words,
    input i_display_response_valid,
    input [135:0] i_display_response
);

    reg [31:0] cnt_powerup=0;
    reg [1:0] reg_reset=0,reg_adc=0;
    wire flag_rstn=reg_reset[1];
    wire flag_boot_done,flag_boot_fault,flag_key_fault,flag_master_fault;
    wire [31:0] wire_pressed,wire_delivered,wire_key_events,wire_completed,wire_pcm_frames,wire_underruns,wire_bad_packets,wire_replayed;
    wire [4:0] wire_key;
    wire [11:0] wire_raw;
    wire flag_sample;
    reg [31:0] cnt_amplifier;
    wire [63:0] wire_pcm;
    wire [31:0] wire_pcm_frame;
    wire flag_pcm_valid,flag_pcm_ready;
    wire flag_local_request,flag_local_response,flag_key_write,flag_monitor_sample;
    wire flag_key_start,flag_key_finish,flag_key_failed;
    wire [7:0] wire_local_opcode,wire_local_argument;
    wire [63:0] wire_local_words;
    wire [135:0] wire_local_response;
    wire [4:0] wire_config_key,wire_event_key;
    wire [47:0] wire_config_data,wire_config_read;
    wire [15:0] wire_monitor_sample;
    wire [31:0] wire_event_frame;
    wire flag_monitor_response;
    wire [135:0] wire_monitor_response;
    wire flag_touch_select=C_TOUCH_ENABLE && wire_local_opcode>=8'h30 && wire_local_opcode<=8'h33;
    wire flag_sequence_select=C_SEQUENCE_ENABLE && wire_local_opcode>=8'h40 && wire_local_opcode<=8'h49;
    wire [391:0] wire_sequence_request;
    wire flag_sequence_request,flag_sequence_ready,flag_sequence_response,flag_sequence_response_ready;
    wire [135:0] wire_sequence_response,wire_sequence_local_response;
    wire flag_sequence_local_response,flag_sequence_click,flag_sequence_accent,flag_sequence_record;
    wire [3:0] wire_patch_lock;
    wire [15:0] wire_click_sample;
    wire flag_touch_response,flag_keys_idle;
    wire [135:0] wire_touch_response;
    wire [31:0] wire_performance_keys,wire_touch_pitch;
    wire [17:0] wire_touch_gain;
    wire [19:0] wire_touch_cutoff;
    wire flag_touch_cutoff_active;
    wire flag_keyboard_select=wire_local_opcode>=8'h20 && wire_local_opcode<=8'h28;
    wire flag_keyboard_response,flag_velocity_enabled;
    wire [135:0] wire_keyboard_response;
    wire [4:0] wire_velocity_key;
    wire [6:0] wire_velocity;
    wire flag_display_select=C_DISPLAY_ENABLE && ((wire_local_opcode>=8'h10 && wire_local_opcode<8'h20) ||
        (wire_local_opcode>=8'h50 && wire_local_opcode<=8'h55));
    assign flag_local_response=flag_sequence_select ? flag_sequence_local_response : flag_touch_select ? flag_touch_response : flag_keyboard_select ? flag_keyboard_response : flag_display_select ? i_display_response_valid : flag_monitor_response;
    assign wire_local_response=flag_sequence_select ? wire_sequence_local_response : flag_touch_select ? wire_touch_response : flag_keyboard_select ? wire_keyboard_response : flag_display_select ? i_display_response : wire_monitor_response;
    assign o_display_reset_n=flag_rstn;
    assign o_display_keys=wire_pressed;
    assign o_display_underruns=wire_underruns;
    assign o_display_errors=wire_bad_packets;
    assign o_display_frames=wire_pcm_frames;
    assign o_display_sample_valid=flag_monitor_sample;
    assign o_display_sample=wire_monitor_sample;
    assign o_display_request=flag_local_request && flag_display_select;
    assign o_display_opcode=wire_local_opcode;
    assign o_display_argument=wire_local_argument;
    assign o_display_words=wire_local_words;
    wire flag_amplifier=flag_rstn && flag_boot_done && cnt_amplifier==C_AMP_CYCLES && !flag_boot_fault && !flag_key_fault && !flag_master_fault && wire_underruns==0;
    wire [127:0] wire_status={wire_bad_packets[15:0],wire_underruns[15:0],wire_pcm_frames,wire_pressed,24'h535905,3'd0,flag_amplifier,flag_boot_fault,flag_key_fault,flag_master_fault,flag_boot_done};
    assign PA_EN=!flag_amplifier;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin cnt_powerup<=0;reg_reset<=0;end
        else begin
            if (cnt_powerup<C_POWERUP_CYCLES) cnt_powerup<=cnt_powerup+1'b1;
            reg_reset<={reg_reset[0],cnt_powerup==C_POWERUP_CYCLES};
        end
    end
    always @(posedge i_clk or negedge flag_rstn) begin
        if (!flag_rstn) begin reg_adc<=0;cnt_amplifier<=0;end
        else begin
            reg_adc<={reg_adc[0],i_adc_dout};
            if (cnt_amplifier<C_AMP_CYCLES) cnt_amplifier<=cnt_amplifier+1'b1;
        end
    end
    wire [391:0] boot_request;
    wire boot_request_valid,boot_request_ready;
    wire [135:0] boot_response;
    wire boot_response_valid,boot_response_ready;
    wire [391:0] key_request;
    wire key_request_valid,key_request_ready;
    wire [135:0] key_response;
    wire key_response_valid,key_response_ready;
    wire [391:0] host_request;
    wire host_request_valid,host_request_ready;
    wire [135:0] host_response;
    wire host_response_valid,host_response_ready;
    wire [391:0] master_request;
    wire master_request_valid,master_request_ready;
    wire [135:0] master_response;
    wire master_response_valid,master_response_ready;
    wire [15:0] axi_awaddr;
    wire axi_awvalid;
    wire axi_awready;
    wire [31:0] axi_wdata;
    wire axi_wvalid;
    wire axi_wready;
    wire [1:0] axi_bresp;
    wire axi_bvalid;
    wire axi_bready;
    wire [15:0] axi_araddr;
    wire axi_arvalid;
    wire axi_arready;
    wire [31:0] axi_rdata;
    wire [1:0] axi_rresp;
    wire axi_rlast;
    wire axi_rvalid;
    wire axi_rready;
    KeyboardSampler #(.C_SETTLE_CYCLES(C_SETTLE_CYCLES),.C_HALF_CYCLES(C_HALF_CYCLES)) Scanner_Inst(
        .i_clk(i_clk),
        .i_rstn(flag_rstn),
        .i_adc_dout(reg_adc[1]),
        .i_ready(1'b1),
        .o_mux_sel(o_mux_sel),
        .o_mux_en(o_mux_en),
        .o_adc_cs_n(o_adc_cs_n),
        .o_adc_sclk(o_adc_sclk),
        .o_adc_din(o_adc_din),
        .o_key(wire_key),
        .o_raw(wire_raw),
        .o_valid(flag_sample)
    );
    SynthKeyboardControl Thresholds_Inst(
        .i_clk(i_clk),.i_rstn(flag_rstn),.i_key(wire_key),.i_raw(wire_raw),.i_valid(flag_sample),
        .o_pressed(wire_pressed),.o_calibrating(o_display_calibrating),.o_velocity_enabled(flag_velocity_enabled),
        .i_velocity_key(wire_velocity_key),.o_velocity(wire_velocity),
        .i_request(flag_local_request && flag_keyboard_select),.i_opcode(wire_local_opcode),.i_argument(wire_local_argument),.i_words(wire_local_words),
        .o_response_valid(flag_keyboard_response),.o_response(wire_keyboard_response)
    );
    SynthBootSequencer #(.C_FX_ENABLE(C_FX_ENABLE)) Boot_Inst(
        .i_clk(i_clk),
        .i_rstn(flag_rstn),
        .o_request(boot_request),
        .o_request_valid(boot_request_valid),
        .i_request_ready(boot_request_ready),
        .i_response(boot_response),
        .i_response_valid(boot_response_valid),
        .o_response_ready(boot_response_ready),
        .o_done(flag_boot_done),
        .o_fault(flag_boot_fault)
    );
    SynthKeyboardSource  Keys_Inst(
        .i_clk(i_clk),
        .i_rstn(flag_rstn),
        .o_request(key_request),
        .o_request_valid(key_request_valid),
        .i_request_ready(key_request_ready),
        .i_response(key_response),
        .i_response_valid(key_response_valid),
        .o_response_ready(key_response_ready),
        .i_enabled(flag_boot_done),
        .i_pressed(wire_performance_keys),.o_idle(flag_keys_idle),
        .o_velocity_key(wire_velocity_key),.i_velocity(wire_velocity),.i_velocity_enabled(flag_velocity_enabled),
        .o_delivered(wire_delivered),
        .o_events(wire_key_events),
        .o_fault(flag_key_fault),
        .i_config_write(flag_key_write),.i_config_key(wire_config_key),.i_config_data(wire_config_data),.o_config_data(wire_config_read),
        .o_event_start(flag_key_start),.o_event_finish(flag_key_finish),.o_event_failed(flag_key_failed),.o_event_key(wire_event_key),.o_event_frame(wire_event_frame)
    );
    SynthUartControl #(.C_UART_CYCLES(C_UART_CYCLES)) Host_Inst(
        .i_clk(i_clk),
        .i_rstn(flag_rstn),
        .o_request(host_request),
        .o_request_valid(host_request_valid),
        .i_request_ready(host_request_ready),
        .i_response(host_response),
        .i_response_valid(host_response_valid),
        .o_response_ready(host_response_ready),
        .i_rx(i_uart_rx),
        .o_tx(o_uart_tx),
        .i_initialized(flag_boot_done && !flag_master_fault),
        .i_status(wire_status),
        .o_bad_packets(wire_bad_packets),
        .o_replayed(wire_replayed),
        .o_local_request(flag_local_request),.o_local_opcode(wire_local_opcode),.o_local_argument(wire_local_argument),.o_local_words(wire_local_words),
        .i_local_valid(flag_local_response),.i_local_response(wire_local_response)
    );
    SynthCommandArbiter #(.C_SEQUENCE_ENABLE(C_SEQUENCE_ENABLE)) Arbiter_Inst(
        .i_sequence_request(wire_sequence_request),.i_sequence_request_valid(flag_sequence_request),.o_sequence_request_ready(flag_sequence_ready),
        .o_sequence_response(wire_sequence_response),.o_sequence_response_valid(flag_sequence_response),.i_sequence_response_ready(flag_sequence_response_ready),
        .i_clk(i_clk),
        .i_rstn(flag_rstn),
        .o_request(master_request),
        .o_request_valid(master_request_valid),
        .i_request_ready(master_request_ready),
        .i_response(master_response),
        .i_response_valid(master_response_valid),
        .o_response_ready(master_response_ready),
        .i_boot_done(flag_boot_done),
        .i_boot_request(boot_request),
        .i_boot_request_valid(boot_request_valid),
        .o_boot_request_ready(boot_request_ready),
        .o_boot_response(boot_response),
        .o_boot_response_valid(boot_response_valid),
        .i_boot_response_ready(boot_response_ready),
        .i_key_request(key_request),
        .i_key_request_valid(key_request_valid),
        .o_key_request_ready(key_request_ready),
        .o_key_response(key_response),
        .o_key_response_valid(key_response_valid),
        .i_key_response_ready(key_response_ready),
        .i_host_request(host_request),
        .i_host_request_valid(host_request_valid),
        .o_host_request_ready(host_request_ready),
        .o_host_response(host_response),
        .o_host_response_valid(host_response_valid),
        .i_host_response_ready(host_response_ready)
    );
    SynthAxiMaster #(.C_SEQUENCE_ENABLE(C_SEQUENCE_ENABLE)) Master_Inst(
        .i_patch_lock(wire_patch_lock),
        .i_clk(i_clk),
        .i_rstn(flag_rstn),
        .i_request(master_request),
        .i_request_valid(master_request_valid),
        .o_request_ready(master_request_ready),
        .o_response(master_response),
        .o_response_valid(master_response_valid),
        .i_response_ready(master_response_ready),
        .o_axi_awaddr(axi_awaddr),
        .o_axi_awvalid(axi_awvalid),
        .i_axi_awready(axi_awready),
        .o_axi_wdata(axi_wdata),
        .o_axi_wvalid(axi_wvalid),
        .i_axi_wready(axi_wready),
        .i_axi_bresp(axi_bresp),
        .i_axi_bvalid(axi_bvalid),
        .o_axi_bready(axi_bready),
        .o_axi_araddr(axi_araddr),
        .o_axi_arvalid(axi_arvalid),
        .i_axi_arready(axi_arready),
        .i_axi_rdata(axi_rdata),
        .i_axi_rresp(axi_rresp),
        .i_axi_rlast(axi_rlast),
        .i_axi_rvalid(axi_rvalid),
        .o_axi_rready(axi_rready),
        .o_fault(flag_master_fault),
        .o_completed(wire_completed)
    );
    AxiSynthEndpoint #(.C_TOUCH_ENABLE(C_TOUCH_ENABLE),.C_DELAY_ADDR_BITS(C_DELAY_ADDR_BITS),.C_FX_ENABLE(C_FX_ENABLE)) Endpoint_Inst(
        .i_touch_gain(wire_touch_gain),.i_touch_pitch(wire_touch_pitch),.i_touch_cutoff(wire_touch_cutoff),.i_touch_cutoff_active(flag_touch_cutoff_active),
        .i_axi_aclk(i_clk),
        .i_axi_arstn(flag_rstn),
        .o_pcm_valid(flag_pcm_valid),
        .i_pcm_ready(flag_pcm_ready),
        .o_pcm_data(wire_pcm),
        .o_pcm_frame(wire_pcm_frame),
        .i_s_axi_awid(4'd0),
        .i_s_axi_awaddr(axi_awaddr),
        .i_s_axi_awlen(8'd0),
        .i_s_axi_awsize(3'd2),
        .i_s_axi_awburst(2'd1),
        .i_s_axi_awlock(1'b0),
        .i_s_axi_awvalid(axi_awvalid),
        .o_s_axi_awready(axi_awready),
        .i_s_axi_arid(4'd0),
        .i_s_axi_araddr(axi_araddr),
        .i_s_axi_arlen(8'd0),
        .i_s_axi_arsize(3'd2),
        .i_s_axi_arburst(2'd1),
        .i_s_axi_arlock(1'b0),
        .i_s_axi_arvalid(axi_arvalid),
        .o_s_axi_arready(axi_arready),
        .i_s_axi_wdata(axi_wdata),
        .i_s_axi_wstrb(4'hf),
        .i_s_axi_wlast(1'b1),
        .i_s_axi_wvalid(axi_wvalid),
        .o_s_axi_wready(axi_wready),
        .o_s_axi_bid(),
        .o_s_axi_bresp(axi_bresp),
        .o_s_axi_bvalid(axi_bvalid),
        .i_s_axi_bready(axi_bready),
        .o_s_axi_rid(),
        .o_s_axi_rdata(axi_rdata),
        .o_s_axi_rresp(axi_rresp),
        .o_s_axi_rlast(axi_rlast),
        .o_s_axi_rvalid(axi_rvalid),
        .i_s_axi_rready(axi_rready)
    );
    SynthPcmOutput #(.C_METRONOME_ENABLE(C_SEQUENCE_ENABLE)) Audio_Inst(
        .i_click(wire_click_sample),
        .i_clk(i_clk),
        .i_rstn(flag_rstn),
        .i_valid(flag_pcm_valid),
        .i_data(wire_pcm),
        .o_ready(flag_pcm_ready),
        .o_bclk(HP_BCK),
        .o_ws(HP_WS),
        .o_data(HP_DIN),
        .o_frames(wire_pcm_frames),
        .o_underruns(wire_underruns),.o_sample_valid(flag_monitor_sample),.o_sample(wire_monitor_sample)
    );
    SynthStudioMonitor Monitor_Inst(
        .i_clk(i_clk),.i_rstn(flag_rstn),
        .i_request(flag_local_request && !flag_display_select && !flag_keyboard_select && !flag_touch_select && !flag_sequence_select),.i_opcode(wire_local_opcode),.i_argument(wire_local_argument),.i_words(wire_local_words),
        .o_response_valid(flag_monitor_response),.o_response(wire_monitor_response),.o_latency(o_display_latency),
        .o_key_write(flag_key_write),.o_key_index(wire_config_key),.o_key_data(wire_config_data),.i_key_data(wire_config_read),
        .i_pcm_valid(flag_monitor_sample),.i_pcm_sample(wire_monitor_sample),.i_pcm_frame(wire_pcm_frame),
        .i_key_start(flag_key_start),.i_key_finish(flag_key_finish),.i_key_failed(flag_key_failed),.i_event_key(wire_event_key),.i_event_frame(wire_event_frame)
    );
    generate if(C_SEQUENCE_ENABLE)begin:SequenceDomain
        SynthSequencer Recorder_Inst(
            .i_clk(i_clk),.i_rstn(flag_rstn),.i_enabled(flag_boot_done && !flag_key_fault && !flag_master_fault),.i_silent(o_display_calibrating),.i_buttons(i_buttons),
            .i_capture(key_request_valid && key_request_ready),.i_key(wire_velocity_key),.i_event(key_request),
            .o_request(wire_sequence_request),.o_request_valid(flag_sequence_request),.i_request_ready(flag_sequence_ready),
            .i_response(wire_sequence_response),.i_response_valid(flag_sequence_response),.o_response_ready(flag_sequence_response_ready),
            .i_local_request(flag_local_request && flag_sequence_select),.i_opcode(wire_local_opcode),.i_argument(wire_local_argument),.i_words(wire_local_words),
            .o_local_valid(flag_sequence_local_response),.o_local_response(wire_sequence_local_response),.o_patch_lock(wire_patch_lock),
            .o_click(flag_sequence_click),.o_accent(flag_sequence_accent),.o_recording(flag_sequence_record),.o_bpm(o_sequence_bpm),.o_status(o_sequence_status));
        SynthMetronome Click_Inst(.i_clk(i_clk),.i_rstn(flag_rstn),.i_sample(flag_monitor_sample),.i_running(flag_sequence_record),
            .i_click(flag_sequence_click),.i_accent(flag_sequence_accent),.o_sample(wire_click_sample));
    end else begin:NoSequenceDomain
        assign wire_sequence_request=0;assign flag_sequence_request=0;assign flag_sequence_response_ready=1;
        assign flag_sequence_local_response=0;assign wire_sequence_local_response=0;assign wire_patch_lock=0;
        assign flag_sequence_click=0;assign flag_sequence_accent=0;assign flag_sequence_record=0;assign wire_click_sample=0;
        assign o_sequence_status=0;assign o_sequence_bpm=0;
    end endgenerate
    generate if(C_TOUCH_ENABLE)begin:TouchDomain
        wire [1:0] wire_update,wire_contact;
        wire [19:0] wire_x,wire_y;
        wire [15:0] wire_error;
        SynthTouchInput Input_Inst(.i_clk(i_clk),.i_rstn(flag_rstn),.io_scl(io_touch_scl),.io_sda(io_touch_sda),
            .o_update(wire_update),.o_touch(wire_contact),.o_x(wire_x),.o_y(wire_y),.o_error(wire_error));
        SynthTouchPerformance Performance_Inst(.i_clk(i_clk),.i_rstn(flag_rstn),.i_next_mode(i_touch_next),.i_silent(o_display_calibrating),
            .i_update(wire_update),.i_touch(wire_contact),.i_x(wire_x),.i_y(wire_y),.i_error(wire_error),
            .i_pressed(wire_pressed),.i_delivered(wire_delivered),.i_keys_idle(flag_keys_idle),.o_pressed(wire_performance_keys),.o_mode(o_touch_mode),
            .o_gain(wire_touch_gain),.o_pitch(wire_touch_pitch),.o_cutoff(wire_touch_cutoff),.o_cutoff_active(flag_touch_cutoff_active),
            .i_request(flag_local_request && flag_touch_select),.i_opcode(wire_local_opcode),.i_argument(wire_local_argument),.i_words(wire_local_words),
            .o_response_valid(flag_touch_response),.o_response(wire_touch_response));
    end else begin:NoTouchDomain
        assign wire_performance_keys=wire_pressed;assign wire_touch_gain=18'd65536;assign wire_touch_pitch=0;assign wire_touch_cutoff=0;
        assign flag_touch_cutoff_active=0;assign flag_touch_response=0;assign wire_touch_response=0;assign o_touch_mode=0;
    end endgenerate
endmodule
