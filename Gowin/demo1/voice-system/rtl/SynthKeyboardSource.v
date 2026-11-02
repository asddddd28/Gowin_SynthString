`timescale 1ns / 1ps
// Edge-to-note source / 按键事件源. Contract: spec/SynthKeyboardSource_spec.md.
module SynthKeyboardSource(
    input i_clk,input i_rstn,
    output [391:0] o_request,output o_request_valid,input i_request_ready,
    input [135:0] i_response,input i_response_valid,output o_response_ready,
    input i_enabled,input [31:0] i_pressed,output [31:0] o_delivered,
    output [31:0] o_events,output o_fault
);
    localparam SCAN=0,PREPARE=1,SEND=2,WAIT_REPLY=3;
    reg [1:0] reg_state,next_state;
    reg [31:0] mem_note_id[0:31];
    reg [31:0] mem_phase[0:31];
    reg [31:0] reg_phase;
    reg [31:0] reg_delivered,cnt_events,cnt_identity;
    reg [4:0] reg_key;
    reg flag_press,flag_fault;
    reg [391:0] reg_request;
    integer index;
    initial $readmemh("rom/keyboard_phase.hex",mem_phase);
    assign o_request=reg_request;
    assign o_request_valid=reg_state==SEND;
    assign o_response_ready=reg_state==WAIT_REPLY;
    assign o_delivered=reg_delivered;
    assign o_events=cnt_events;
    assign o_fault=flag_fault;
    always @(posedge i_clk) begin
        if (reg_state==SCAN) reg_phase<=mem_phase[reg_key];
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) reg_state<=SCAN;
        else reg_state<=next_state;
    end
    always @(*) begin
        next_state=reg_state;
        case (reg_state)
            SCAN: if (i_enabled && !flag_fault && i_pressed[reg_key]!=reg_delivered[reg_key]) next_state=PREPARE;
            PREPARE: next_state=SEND;
            SEND: if (i_request_ready) next_state=WAIT_REPLY;
            WAIT_REPLY: if (i_response_valid) next_state=SCAN;
            default: next_state=SCAN;
        endcase
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            reg_delivered<=0;cnt_events<=0;cnt_identity<=0;reg_key<=0;flag_press<=0;flag_fault<=0;reg_request<=0;
            for (index=0;index<32;index=index+1) mem_note_id[index]<=0;
        end else begin
            case (reg_state)
                SCAN: if (next_state==PREPARE) flag_press<=i_pressed[reg_key];
                    else reg_key<=reg_key+1'b1;
                PREPARE: begin
                    reg_request<=0;
                    reg_request[391:360]<=cnt_events;
                    if (flag_press) begin
                        cnt_identity<=cnt_identity+1'b1;
                        mem_note_id[reg_key]<=32'h80000000 | (cnt_identity+1'b1);
                        reg_request[327:320]<=8'ha4;
                        reg_request[31:0]<=32'h80000000 | (cnt_identity+1'b1);
                        reg_request[63:32]<=reg_phase;
                        reg_request[95:64]<=67108864;
                        reg_request[127:96]<=33554432;
                        // Fixed velocity until the keybed measures strike speed; retain true MIDI pitch for DX key scaling.
                        reg_request[159:128]<=32'h80003200 | (32'd48+{27'd0,reg_key});
                    end else begin
                        reg_request[327:320]<=8'ha5;
                        reg_request[31:0]<=mem_note_id[reg_key];
                    end
                end
                WAIT_REPLY: if (i_response_valid) begin
                    if (i_response[135:128]!=0 || i_response[71:64]!=0) flag_fault<=1;
                    else begin reg_delivered[reg_key]<=flag_press;cnt_events<=cnt_events+1'b1;end
                    reg_key<=reg_key+1'b1;
                end
                default: reg_key<=reg_key;
            endcase
        end
    end
endmodule
