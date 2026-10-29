`timescale 1ns / 1ps
`ifndef SYNTH_VOICES
`define SYNTH_VOICES 32
`endif
// NEO: KEY0 reset; KEY1 chord; KEY2 waveform. 50 MHz / 2 * 29 / 14.75; 512 cycles/sample.
module top(input sys_clk, input sys_rst_n, input [1:0] Key_in, input uart_rx, output uart_tx,
    output HP_BCK, output HP_WS, output HP_DIN, output PA_EN);
    reg [15:0] cnt_powerup=0;
    wire clock_ready=&cnt_powerup;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) cnt_powerup<=0;
        else if(!clock_ready) cnt_powerup<=cnt_powerup+1'b1;
    end
    wire clk_audio, pll_lock, rstn;
    Gowin_PLL Clock_Inst(.clkin(sys_clk),.clkout0(clk_audio),.lock(pll_lock),
        .mdclk(sys_clk),.reset(!clock_ready));
    ResetSync Reset_Inst(.i_clk(clk_audio),.i_rstn(sys_rst_n && pll_lock),.o_rstn(rstn));
    reg [9:0] cnt_frame;
    always @(posedge clk_audio or negedge rstn) begin
        if(!rstn) cnt_frame<=0;
        else cnt_frame<=cnt_frame+10'd2;
    end
    wire chord_valid, event_ready;
    wire [55:0] chord_event;
    ChordKeys Keys_Inst(.i_clk(clk_audio),.i_rstn(rstn),.i_tick(cnt_frame==0),
        .i_chord_n(Key_in[0]),.i_wave_n(Key_in[1]),.i_ready(event_ready),
        .o_valid(chord_valid),.o_event(chord_event),.o_wave());
    SynthSystem #(.C_VOICES(`SYNTH_VOICES),.C_CLOCK_HZ(49152542),.C_PT8211(1),.C_FRAME_STEP(2)) Synth_Inst(
        .i_clk(clk_audio),.i_rstn(rstn),.i_uart_rx(uart_rx),.i_key_n(1'b1),.i_panic(1'b0),
        .i_note_valid(chord_valid),.i_note_event(chord_event),.o_note_ready(event_ready),
        .o_uart_tx(uart_tx),.o_mclk(),.o_bclk(HP_BCK),.o_lrclk(HP_WS),.o_sdata(HP_DIN),
        .o_flags(),.o_voices(),.o_oscillators(),.o_max_cycles(),.o_clips(),.o_sample_valid(),.o_sample());
    // NS4263 active-low enable, ~21 ms settling after PLL lock/reset.
    reg [20:0] cnt_settle;
    always @(posedge clk_audio or negedge rstn) begin
        if(!rstn) cnt_settle<=0;
        else if(!cnt_settle[20]) cnt_settle<=cnt_settle+1'b1;
    end
    assign PA_EN=!(rstn && cnt_settle[20]);
endmodule
