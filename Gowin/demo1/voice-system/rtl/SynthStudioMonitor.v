`timescale 1ns / 1ps
// Local control and passive audio observation. See SynthStudioMonitor_spec.md.
module SynthStudioMonitor(
    input i_clk,input i_rstn,
    input i_request,input [7:0] i_opcode,input [7:0] i_argument,input [63:0] i_words,
    output o_response_valid,output [135:0] o_response,output [31:0] o_latency,
    output o_key_write,output [4:0] o_key_index,output [47:0] o_key_data,input [47:0] i_key_data,
    input i_pcm_valid,input [15:0] i_pcm_sample,input [31:0] i_pcm_frame,
    input i_key_start,input i_key_finish,input i_key_failed,input [4:0] i_event_key,input [31:0] i_event_frame
);
    localparam IDLE=0,VALIDATE=1,EXECUTE=2,READ_ISSUE=3,READ_COLLECT=4,RESPOND=5;
    reg [2:0] reg_state,dec_next_state;
    reg [7:0] reg_opcode,reg_argument,reg_status;
    reg [63:0] reg_words;
    reg [127:0] reg_response;
    reg [2:0] reg_lane;
    reg [15:0] reg_read_sample;
    (* syn_ramstyle = "block_ram" *) reg [15:0] mem_capture[0:511];
    reg [8:0] reg_write_index;
    reg flag_capture_busy,flag_capture_ready;
    reg [15:0] cnt_generation;
    reg [31:0] cnt_clock,reg_started,reg_target_frame;
    reg [31:0] reg_latency,reg_maximum,cnt_observations;
    reg [4:0] reg_event_key,reg_last_key;
    reg flag_waiting,flag_committed;
    wire [31:0] wire_elapsed=cnt_clock-reg_started;
    wire flag_bad_empty=reg_words!=0;
    assign o_response_valid=reg_state==RESPOND;
    assign o_response={reg_status,reg_response};
    assign o_latency=reg_latency;
    assign o_key_write=reg_state==EXECUTE && reg_opcode==1 && reg_status==0;
    assign o_key_index=reg_argument[4:0];
    assign o_key_data=reg_words[47:0];

    // The snapshot RAM has independent sample-write and sequential host-read ports.
    always @(posedge i_clk) begin
        if (flag_capture_busy && i_pcm_valid) mem_capture[reg_write_index]<=i_pcm_sample;
        if (reg_state==READ_ISSUE) reg_read_sample<=mem_capture[{reg_argument[5:0],reg_lane}];
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) reg_state<=IDLE;
        else reg_state<=dec_next_state;
    end
    always @(*) begin
        dec_next_state=reg_state;
        case(reg_state)
            IDLE: if(i_request) dec_next_state=VALIDATE;
            VALIDATE: dec_next_state=EXECUTE;
            EXECUTE: if(reg_status==0 && reg_opcode==5) dec_next_state=READ_ISSUE;
                else dec_next_state=RESPOND;
            READ_ISSUE: dec_next_state=READ_COLLECT;
            READ_COLLECT: dec_next_state=reg_lane==7 ? RESPOND : READ_ISSUE;
            RESPOND: dec_next_state=IDLE;
            default: dec_next_state=IDLE;
        endcase
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            reg_opcode<=0;reg_argument<=0;reg_status<=0;reg_words<=0;reg_response<=0;reg_lane<=0;
            reg_write_index<=0;flag_capture_busy<=0;flag_capture_ready<=0;cnt_generation<=0;
            cnt_clock<=0;reg_started<=0;reg_target_frame<=0;reg_latency<=0;reg_maximum<=0;cnt_observations<=0;
            reg_event_key<=0;reg_last_key<=0;flag_waiting<=0;flag_committed<=0;
        end else begin
            cnt_clock<=cnt_clock+1'b1;
            if (flag_capture_busy && i_pcm_valid) begin
                reg_write_index<=reg_write_index+1'b1;
                if(reg_write_index==511) begin flag_capture_busy<=0;flag_capture_ready<=1;end
            end
            // Coalesce observation requests only; the note path is never blocked.
            if(i_key_start && !flag_waiting) begin
                reg_started<=cnt_clock;reg_event_key<=i_event_key;flag_waiting<=1;flag_committed<=0;
            end
            if(i_key_finish && flag_waiting && i_event_key==reg_event_key) begin
                if(i_key_failed) begin flag_waiting<=0;flag_committed<=0;end
                else begin reg_target_frame<=i_event_frame;flag_committed<=1;end
            end
            if(flag_waiting && flag_committed && i_pcm_valid && i_pcm_frame==reg_target_frame) begin
                reg_latency<=wire_elapsed;
                if(wire_elapsed>reg_maximum) reg_maximum<=wire_elapsed;
                cnt_observations<=cnt_observations+1'b1;reg_last_key<=reg_event_key;
                flag_waiting<=0;flag_committed<=0;
            end
            case(reg_state)
                IDLE: if(i_request) begin
                    reg_opcode<=i_opcode;reg_argument<=i_argument;reg_words<=i_words;
                    reg_status<=0;reg_response<=0;reg_lane<=0;
                end
                VALIDATE: begin
                    case(reg_opcode)
                        0,2,3: if(reg_argument!=0 || flag_bad_empty) reg_status<=5;
                            else if(reg_opcode==2 && flag_capture_busy) reg_status<=10;
                        1: if(reg_argument>31 || reg_words[63:48]!=0 || reg_words[47:41]==0) reg_status<=5;
                        4: if(reg_argument>31 || flag_bad_empty) reg_status<=5;
                        5: if(reg_argument>63 || flag_bad_empty) reg_status<=5;
                            else if(!flag_capture_ready) reg_status<=10;
                        default: reg_status<=5;
                    endcase
                end
                EXECUTE: if(reg_status==0) begin
                    case(reg_opcode)
                        0: reg_response<={32'd1024,32'd50000000,32'd1,32'h53544d31};
                        1: reg_response<={64'd0,reg_words};
                        2: begin
                            flag_capture_busy<=1;flag_capture_ready<=0;reg_write_index<=0;
                            cnt_generation<=cnt_generation+1'b1;reg_response[15:0]<=cnt_generation+1'b1;
                        end
                        3: reg_response<={cnt_generation,8'd0,reg_last_key,(cnt_observations!=0),flag_capture_ready,flag_capture_busy,cnt_observations,reg_maximum,reg_latency};
                        4: reg_response<={80'd0,i_key_data};
                        default: reg_lane<=0;
                    endcase
                end
                READ_COLLECT: begin reg_response[reg_lane*16+:16]<=reg_read_sample;reg_lane<=reg_lane+1'b1;end
                default: reg_lane<=reg_lane;
            endcase
        end
    end
endmodule
