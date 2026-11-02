`timescale 1ns / 1ps
// Contract: spec/SynthSystemTop_spec.md.
module SynthSystemTop #(parameter C_UART_CYCLES=434,parameter C_SETTLE_CYCLES=10000,parameter C_HALF_CYCLES=6,parameter C_POWERUP_CYCLES=65535,parameter C_AMP_CYCLES=1048576,parameter C_DELAY_ADDR_BITS=13)(
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
    output PA_EN
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
    LatencyKeyThresholds  Thresholds_Inst(
        .i_clk(i_clk),
        .i_rstn(flag_rstn),
        .i_key(wire_key),
        .i_raw(wire_raw),
        .i_valid(flag_sample),
        .o_candidate(),
        .o_confirm(),
        .o_cancel(),
        .o_pressed(wire_pressed)
    );
    SynthBootSequencer  Boot_Inst(
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
        .i_pressed(wire_pressed),
        .o_delivered(wire_delivered),
        .o_events(wire_key_events),
        .o_fault(flag_key_fault)
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
        .o_replayed(wire_replayed)
    );
    SynthCommandArbiter  Arbiter_Inst(
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
    SynthAxiMaster  Master_Inst(
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
    AxiSynthEndpoint #(.C_DELAY_ADDR_BITS(C_DELAY_ADDR_BITS)) Endpoint_Inst(
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
    SynthPcmOutput  Audio_Inst(
        .i_clk(i_clk),
        .i_rstn(flag_rstn),
        .i_valid(flag_pcm_valid),
        .i_data(wire_pcm),
        .o_ready(flag_pcm_ready),
        .o_bclk(HP_BCK),
        .o_ws(HP_WS),
        .o_data(HP_DIN),
        .o_frames(wire_pcm_frames),
        .o_underruns(wire_underruns)
    );
endmodule
