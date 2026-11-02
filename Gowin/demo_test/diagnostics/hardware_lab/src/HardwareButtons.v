`timescale 1ns / 1ps
// HardwareButtons: six independent active-high inputs in the comprehensive hub.
// Contract: ../spec/src/HardwareButtons_spec.md. SW1 occupies mask bit zero.
module HardwareButtons #(
    parameter [31:0] C_STABLE_CYCLES = 32'd250000,
    parameter [31:0] C_REPORT_CYCLES = 32'd5000000
)(
    input i_clk,
    input i_rstn,
    input [5:0] i_buttons,
    input i_tx_ready,
    output o_tx_valid,
    output [7:0] o_tx_data
);
    wire [5:0] bus_raw;
    wire [5:0] bus_pressed;
    wire [95:0] bus_presses;
    wire [95:0] bus_releases;
    wire [95:0] bus_edges;
    genvar idx_button;

    // Each channel continues sampling while the shared UART is backpressured.
    generate
        for (idx_button=0;idx_button<6;idx_button=idx_button+1) begin:gen_buttons
            TactileInput #(.C_STABLE_CYCLES(C_STABLE_CYCLES)) Button_Inst(
                .i_clk(i_clk),.i_rstn(i_rstn),.i_switch(i_buttons[idx_button]),
                .o_raw(bus_raw[idx_button]),.o_pressed(bus_pressed[idx_button]),
                .o_presses(bus_presses[95-idx_button*16 -: 16]),
                .o_releases(bus_releases[95-idx_button*16 -: 16]),
                .o_edges(bus_edges[95-idx_button*16 -: 16]));
        end
    endgenerate

    // 10 Hz coherent snapshots leave headroom for keyboard and guitar traffic.
    HardwareButtonReport #(.C_REPORT_CYCLES(C_REPORT_CYCLES)) Report_Inst(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_raw(bus_raw),.i_pressed(bus_pressed),
        .i_presses(bus_presses),.i_releases(bus_releases),.i_edges(bus_edges),
        .i_tx_ready(i_tx_ready),.o_tx_valid(o_tx_valid),.o_tx_data(o_tx_data));
endmodule
