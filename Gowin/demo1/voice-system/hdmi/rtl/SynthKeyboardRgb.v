`timescale 1ns / 1ps
// Keyboard-light adapter. 50 MHz only; audio and ADC timing are independent.
// Protocol and frame timing: SynthKeyboardRgb.md / SynthKeyboardRgb.json.
module SynthKeyboardRgb #(
    parameter integer C_FRAME_CYCLES=1000000
)(
    input i_clk,
    input i_rstn,
    input [31:0] i_pressed,
    input i_calibrating,
    input i_request,
    input [7:0] i_opcode,
    input [7:0] i_argument,
    input [63:0] i_words,
    output o_response_valid,
    output [135:0] o_response,
    output o_rgb
);
    reg [31:0] reg_pressed;
    reg [3:0] reg_mode;
    reg flag_direction;
    reg flag_clear;
    reg flag_response_o;
    reg [135:0] reg_response_o;
    wire [31:0] wire_press;
    wire [4:0] wire_pixel;
    wire [23:0] wire_grb;
    wire flag_frame;
    wire flag_mode_valid;

    assign flag_mode_valid=(i_argument<=8'd4 || i_argument==8'd6);
    assign wire_press=i_calibrating ? 32'd0 : i_pressed & ~reg_pressed;
    assign o_response_valid=flag_response_o;
    assign o_response=reg_response_o;

    // Consume physical edges even during calibration. Held keys never retrigger.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            reg_pressed<=0;
            reg_mode<=4'd1;
            flag_direction<=0;
            flag_clear<=0;
            flag_response_o<=0;
            reg_response_o<=0;
        end else begin
            reg_pressed<=i_pressed;
            flag_clear<=0;
            flag_response_o<=i_request;
            if(i_request) begin
                reg_response_o<=0;
                case(i_opcode)
                    8'h18: begin
                        if(i_argument!=0 || i_words!=0) begin
                            reg_response_o[135:128]<=8'd5;
                        end else begin
                            reg_response_o<={8'd0,i_pressed,32'h00010000,
                                23'd0,flag_direction,4'd0,reg_mode,32'h52474231};
                        end
                    end
                    8'h19: begin
                        if(!flag_mode_valid || i_words[63:1]!=0) begin
                            reg_response_o[135:128]<=8'd5;
                        end else begin
                            reg_mode<=i_argument[3:0];
                            flag_direction<=i_words[0];
                            flag_clear<=1;
                        end
                    end
                    default: begin
                        reg_response_o[135:128]<=8'd5;
                    end
                endcase
            end
        end
    end

    SynthKeyboardLightEffects Effects_Inst(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_press(wire_press),
        .i_clear(flag_clear || i_calibrating),.i_mode(reg_mode),
        .i_direction(flag_direction),.i_frame_tick(flag_frame),
        .i_pixel(wire_pixel),.o_grb(wire_grb)
    );
    LedFrameTx #(.C_FRAME_CYCLES(C_FRAME_CYCLES)) Tx_Inst(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_grb(wire_grb),
        .o_pixel(wire_pixel),.o_frame_tick(flag_frame),.o_data(o_rgb)
    );
endmodule
