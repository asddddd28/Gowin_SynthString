`timescale 1ns / 1ps
// Boot program loader / 启动装载器. Contract: spec/SynthBootSequencer_spec.md.
module SynthBootSequencer(
    input i_clk, input i_rstn,
    output [391:0] o_request, output o_request_valid, input i_request_ready,
    input [135:0] i_response, input i_response_valid, output o_response_ready,
    output o_done, output o_fault
);
    localparam COUNT_READ=0,COUNT_LOAD=1,WORD_READ=2,WORD_LOAD=3,SEND=4,WAIT_REPLY=5,DONE=6,FAILED=7;
    reg [2:0] reg_state,next_state;
    reg [31:0] mem_program[0:1023];
    reg [31:0] reg_read;
    reg [9:0] reg_address;
    reg [6:0] cnt_commands,reg_command;
    reg [3:0] reg_word;
    reg [391:0] reg_request;
    wire flag_bad=i_response[135:128]!=0 || i_response[71:64]!=0;
    initial $readmemh("rom/boot.hex",mem_program);
    assign o_request=reg_request;
    assign o_request_valid=reg_state==SEND;
    assign o_response_ready=reg_state==WAIT_REPLY;
    assign o_done=reg_state==DONE;
    assign o_fault=reg_state==FAILED;
    always @(posedge i_clk) begin
        if (reg_state==COUNT_READ || reg_state==WORD_READ) reg_read<=mem_program[reg_address];
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) reg_state<=COUNT_READ;
        else reg_state<=next_state;
    end
    always @(*) begin
        next_state=reg_state;
        case (reg_state)
            COUNT_READ: next_state=COUNT_LOAD;
            COUNT_LOAD: next_state=(reg_read==0 || reg_read>93) ? FAILED : WORD_READ;
            WORD_READ: next_state=WORD_LOAD;
            WORD_LOAD: next_state=reg_word==10 ? SEND : WORD_READ;
            SEND: if (i_request_ready) next_state=WAIT_REPLY;
            WAIT_REPLY: if (i_response_valid) begin
                if (flag_bad) next_state=FAILED;
                else if (reg_command+1'b1==cnt_commands) next_state=DONE;
                else next_state=WORD_READ;
            end
            DONE: next_state=DONE;
            default: next_state=FAILED;
        endcase
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            reg_address<=0;cnt_commands<=0;reg_command<=0;reg_word<=0;reg_request<=0;
        end else begin
            case (reg_state)
                COUNT_LOAD: begin cnt_commands<=reg_read[6:0];reg_address<=1;end
                WORD_LOAD: begin
                    reg_address<=reg_address+1'b1;
                    if (reg_word==0) begin
                        reg_request[335:320]<=reg_read[15:0];
                        reg_request[359:336]<=0;
                        reg_request[391:360]<={25'h1600000,reg_command};
                    end else reg_request[(reg_word-1)*32+:32]<=reg_read;
                    if (reg_word<10) reg_word<=reg_word+1'b1;
                end
                WAIT_REPLY: if (i_response_valid && !flag_bad) begin reg_command<=reg_command+1'b1;reg_word<=0;end
                default: reg_word<=reg_word;
            endcase
        end
    end
endmodule
