`timescale 1ns / 1ps
// Framed host control / 带CRC和重放保护的主机控制. Contract: spec/SynthUartControl_spec.md.
module SynthUartControl #(parameter C_UART_CYCLES=434,parameter C_GAP_CYCLES=C_UART_CYCLES*600)(
    input i_clk,input i_rstn,
    output [391:0] o_request,output o_request_valid,input i_request_ready,
    input [135:0] i_response,input i_response_valid,output o_response_ready,
    input i_rx,output o_tx,input i_initialized,input [127:0] i_status,
    output [31:0] o_bad_packets,output [31:0] o_replayed,
    output o_local_request,output [7:0] o_local_opcode,output [7:0] o_local_argument,output [63:0] o_local_words,
    input i_local_valid,input [135:0] i_local_response
);
    localparam IDLE=0,CHECK=1,SEND=2,WAIT_REPLY=3,PREPARE_TX=4,TX_LAUNCH=5,TX_WAIT=6;
    localparam DECODE=7,CLASSIFY=8,LOCAL_SEND=9,LOCAL_WAIT=10;
    reg [3:0] reg_state,next_state;
    wire [7:0] wire_rx;
    wire flag_rx_valid,flag_rx_error,flag_tx_busy;
    reg [5:0] reg_rx_index,reg_tx_index;
    reg [15:0] reg_rx_crc,reg_tx_crc;
    reg [7:0] reg_crc_low;
    reg [31:0] cnt_gap,cnt_bad,cnt_replayed;
    reg [399:0] reg_image,reg_packet,reg_cached_request;
    reg flag_packet,flag_session,flag_cache;
    reg [31:0] reg_sequence;
    reg [239:0] reg_tx_image,reg_cached_response;
    reg [391:0] reg_request;
    wire [7:0] wire_kind=reg_packet[31:24];
    wire [31:0] wire_sequence=reg_packet[63:32];
    wire [7:0] wire_opcode=reg_packet[71:64];
    wire [7:0] wire_argument=reg_packet[79:72];
    reg [24:0] reg_equal_parts;
    reg [9:0] reg_zero_words;
    reg flag_same_sequence,flag_next_sequence;
    reg flag_replay,flag_conflict,flag_bad_sequence,flag_bad_request;
    integer compare_index;
    wire flag_opcode=(wire_opcode>=8'ha0 && wire_opcode<=8'ha9) || (wire_opcode>=8'hb0 && wire_opcode<=8'hb3) || (wire_opcode>=8'hc0 && wire_opcode<=8'hc4) || wire_opcode==8'hd0 || wire_opcode==8'hd1;
    wire flag_reserved_note=(wire_opcode==8'ha4 || wire_opcode==8'ha5 || wire_opcode==8'ha6) && reg_packet[111];
    wire flag_not_ready=wire_kind!=2 && !i_initialized;
    wire [7:0] wire_tx_byte=reg_tx_index<30 ? reg_tx_image[reg_tx_index*8+:8] : (reg_tx_index==30 ? reg_tx_crc[7:0] : reg_tx_crc[15:8]);
    assign o_local_request=reg_state==LOCAL_SEND;
    assign o_local_opcode=wire_opcode;
    assign o_local_argument=wire_argument;
    assign o_local_words=reg_packet[143:80];
    assign o_request=reg_request;
    assign o_request_valid=reg_state==SEND;
    assign o_response_ready=reg_state==WAIT_REPLY;
    assign o_bad_packets=cnt_bad;
    assign o_replayed=cnt_replayed;
    function [15:0] crc_byte;
        input [15:0] initial_crc;
        input [7:0] data_byte;
        reg [15:0] work_crc;
        integer bit_index;
        begin
            work_crc=initial_crc^{data_byte,8'd0};
            for (bit_index=0;bit_index<8;bit_index=bit_index+1)
                work_crc=work_crc[15] ? (work_crc<<1)^16'h1021 : work_crc<<1;
            crc_byte=work_crc;
        end
    endfunction
    UartRx #(.C_CLOCK_HZ(C_UART_CYCLES*115200),.C_BAUD(115200)) Receiver_Inst(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_rx(i_rx),.o_byte(wire_rx),.o_valid(flag_rx_valid),.o_error(flag_rx_error)
    );
    EncoderUartTx #(.C_BAUD_CYCLES(C_UART_CYCLES)) Transmitter_Inst(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_start(reg_state==TX_LAUNCH && !flag_tx_busy),.i_data(wire_tx_byte),.o_busy(flag_tx_busy),.o_tx(o_tx)
    );
    // RX never modifies a command already accepted by the main controller.
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            reg_rx_index<=0;reg_rx_crc<=16'hffff;reg_crc_low<=0;cnt_gap<=0;cnt_bad<=0;
            reg_image<=0;reg_packet<=0;flag_packet<=0;
        end else begin
            flag_packet<=0;
            if (reg_rx_index!=0 && !flag_rx_valid) cnt_gap<=cnt_gap+1'b1;
            else cnt_gap<=0;
            if (flag_rx_error || (reg_rx_index!=0 && cnt_gap==C_GAP_CYCLES)) begin
                reg_rx_index<=0;cnt_bad<=cnt_bad+1'b1;cnt_gap<=0;
            end else if (flag_rx_valid) begin
                if (reg_rx_index==0) begin
                    if (wire_rx==8'h53) begin
                        reg_image[7:0]<=wire_rx;reg_rx_crc<=crc_byte(16'hffff,wire_rx);reg_rx_index<=1;
                    end
                end else if (reg_rx_index==1) begin
                    if (wire_rx==8'h59) begin
                        reg_image[15:8]<=wire_rx;reg_rx_crc<=crc_byte(reg_rx_crc,wire_rx);reg_rx_index<=2;
                    end else if (wire_rx==8'h53) reg_rx_crc<=crc_byte(16'hffff,wire_rx);
                    else reg_rx_index<=0;
                end else if (reg_rx_index<50) begin
                    reg_image[reg_rx_index*8+:8]<=wire_rx;
                    reg_rx_crc<=crc_byte(reg_rx_crc,wire_rx);reg_rx_index<=reg_rx_index+1'b1;
                end else if (reg_rx_index==50) begin reg_crc_low<=wire_rx;reg_rx_index<=51;end
                else begin
                    reg_rx_index<=0;
                    if ({wire_rx,reg_crc_low}==reg_rx_crc && reg_image[23:16]==5 && reg_state==IDLE && !flag_packet) begin
                        reg_packet<=reg_image;flag_packet<=1;
                    end else cnt_bad<=cnt_bad+1'b1;
                end
            end
        end
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) reg_state<=IDLE;
        else reg_state<=next_state;
    end
    always @(*) begin
        next_state=reg_state;
        case (reg_state)
            IDLE: if (flag_packet) next_state=DECODE;
            DECODE: next_state=CLASSIFY;
            CLASSIFY: next_state=CHECK;
            CHECK: if (flag_replay || flag_conflict || flag_bad_sequence || flag_bad_request || flag_not_ready || wire_kind==2) next_state=PREPARE_TX;
                else next_state=wire_kind==3 ? LOCAL_SEND : SEND;
            LOCAL_SEND: next_state=LOCAL_WAIT;
            LOCAL_WAIT: if(i_local_valid) next_state=PREPARE_TX;
            SEND: if (i_request_ready) next_state=WAIT_REPLY;
            WAIT_REPLY: if (i_response_valid) next_state=PREPARE_TX;
            PREPARE_TX: next_state=TX_LAUNCH;
            TX_LAUNCH: if (!flag_tx_busy) next_state=TX_WAIT;
            TX_WAIT: if (!flag_tx_busy) next_state=reg_tx_index==31 ? IDLE : TX_LAUNCH;
            default: next_state=IDLE;
        endcase
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            reg_tx_index<=0;reg_tx_crc<=16'hffff;cnt_replayed<=0;reg_cached_request<=0;
            flag_session<=0;flag_cache<=0;reg_sequence<=0;reg_tx_image<=0;reg_cached_response<=0;reg_request<=0;
            reg_equal_parts<=0;reg_zero_words<=0;flag_same_sequence<=0;flag_next_sequence<=0;
            flag_replay<=0;flag_conflict<=0;flag_bad_sequence<=0;flag_bad_request<=0;
        end else begin
            case (reg_state)
                DECODE: begin
                    for (compare_index=0;compare_index<25;compare_index=compare_index+1)
                        reg_equal_parts[compare_index]<=reg_packet[compare_index*16+:16]==reg_cached_request[compare_index*16+:16];
                    for (compare_index=0;compare_index<10;compare_index=compare_index+1)
                        reg_zero_words[compare_index]<=reg_packet[80+compare_index*32+:32]==0;
                    flag_same_sequence<=wire_sequence==reg_sequence;
                    flag_next_sequence<=wire_sequence==(flag_session ? reg_sequence+32'd1 : 32'd0);
                end
                CLASSIFY: begin
                    flag_replay<=flag_session && flag_same_sequence && (&reg_equal_parts);
                    flag_conflict<=flag_session && flag_same_sequence && !(&reg_equal_parts);
                    flag_bad_sequence<=!(flag_session && flag_same_sequence) && !flag_next_sequence;
                    flag_bad_request<=wire_kind>3 ||
                        (wire_kind==3 && !(&reg_zero_words[9:2])) ||
                        (wire_kind==0 && (!flag_opcode || flag_reserved_note)) ||
                        (wire_kind==1 && (wire_opcode!=0 || wire_argument!=0 || !(&reg_zero_words[9:1]) || reg_packet[111:80]>100 || reg_packet[81:80]!=0)) ||
                        (wire_kind==2 && (wire_opcode!=0 || wire_argument!=0 || !(&reg_zero_words)));
                end
                CHECK: begin
                    reg_tx_image<={16'd0,8'd0,wire_argument,wire_opcode,8'd0,128'd0,wire_sequence,wire_kind,8'd5,8'h52,8'h53};
                    flag_cache<=!flag_replay && !flag_conflict && !flag_bad_sequence;
                    if (flag_replay) begin
                        reg_tx_image<=reg_cached_response;reg_tx_image[216]<=1;cnt_replayed<=cnt_replayed+1'b1;
                    end else if (flag_conflict) reg_tx_image[199:192]<=2;
                    else if (flag_bad_sequence) reg_tx_image[199:192]<=3;
                    else if (flag_bad_request) reg_tx_image[199:192]<=5;
                    else if (flag_not_ready) reg_tx_image[199:192]<=7;
                    else if (wire_kind==2) reg_tx_image[191:64]<=i_status;
                    else begin
                        reg_request<={wire_sequence,reg_packet[95:80],7'd0,wire_kind==1,wire_argument,wire_opcode,reg_packet[399:80]};
                    end
                end
                LOCAL_WAIT: if(i_local_valid) begin
                    reg_tx_image[191:64]<=i_local_response[127:0];reg_tx_image[199:192]<=i_local_response[135:128];
                end
                WAIT_REPLY: if (i_response_valid) begin
                    reg_tx_image[191:64]<=i_response[127:0];reg_tx_image[199:192]<=i_response[135:128];
                end
                PREPARE_TX: begin
                    reg_tx_index<=0;reg_tx_crc<=16'hffff;
                    if (flag_cache) begin
                        flag_session<=1;reg_sequence<=wire_sequence;reg_cached_request<=reg_packet;reg_cached_response<=reg_tx_image;
                    end
                end
                TX_LAUNCH: if (!flag_tx_busy && reg_tx_index<30) reg_tx_crc<=crc_byte(reg_tx_crc,wire_tx_byte);
                TX_WAIT: if (!flag_tx_busy) reg_tx_index<=reg_tx_index+1'b1;
                default: reg_tx_index<=reg_tx_index;
            endcase
        end
    end
endmodule
