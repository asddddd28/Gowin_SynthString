`timescale 1ns / 1ps
// Mailbox master / 命令邮箱主控. Contract: spec/SynthAxiMaster_spec.md.
module SynthAxiMaster #(parameter C_WATCHDOG=65535)(
    input i_clk, input i_rstn,
    input [391:0] i_request, input i_request_valid, output o_request_ready,
    output [135:0] o_response, output o_response_valid, input i_response_ready,
    output [15:0] o_axi_awaddr, output o_axi_awvalid, input i_axi_awready,
    output [31:0] o_axi_wdata, output o_axi_wvalid, input i_axi_wready,
    input [1:0] i_axi_bresp, input i_axi_bvalid, output o_axi_bready,
    output [15:0] o_axi_araddr, output o_axi_arvalid, input i_axi_arready,
    input [31:0] i_axi_rdata, input [1:0] i_axi_rresp, input i_axi_rlast,
    input i_axi_rvalid, output o_axi_rready,
    output o_fault, output [31:0] o_completed
);
    localparam IDLE=0, PREPARE=1, ADDRESS_WRITE=2, DATA_WRITE=3, WRITE_RESPONSE=4;
    localparam ADDRESS_READ=5, READ_RESPONSE=6, FINISH=7;
    reg [3:0] reg_state, next_state;
    reg [391:0] reg_request;
    reg [4:0] reg_word;
    reg [2:0] reg_read_word;
    reg flag_poll, flag_pop;
    reg [15:0] reg_write_address, reg_read_address;
    reg [31:0] reg_write_data;
    reg [31:0] cnt_voice_sequence, cnt_fx_sequence;
    reg [31:0] cnt_watchdog, cnt_completed;
    reg flag_fault;
    reg [135:0] reg_response;
    wire flag_fx=reg_request[327:320]>=8'hc0 && reg_request[327:320]<=8'hc4;
    wire [31:0] wire_sequence=flag_fx ? cnt_fx_sequence : cnt_voice_sequence;
    wire flag_read_error=i_axi_rresp!=0 || !i_axi_rlast;
    wire flag_read_identity=(reg_read_word==4 && i_axi_rdata!=reg_request[391:360]) ||
        (reg_read_word==5 && i_axi_rdata!={24'd0,reg_request[327:320]});
    assign o_request_ready=reg_state==IDLE && !flag_fault;
    assign o_response=reg_response;
    assign o_response_valid=reg_state==FINISH;
    assign o_axi_awaddr=reg_write_address;
    assign o_axi_awvalid=reg_state==ADDRESS_WRITE;
    assign o_axi_wdata=reg_write_data;
    assign o_axi_wvalid=reg_state==DATA_WRITE;
    assign o_axi_bready=reg_state==WRITE_RESPONSE;
    assign o_axi_araddr=reg_read_address;
    assign o_axi_arvalid=reg_state==ADDRESS_READ;
    assign o_axi_rready=reg_state==READ_RESPONSE;
    assign o_fault=flag_fault;
    assign o_completed=cnt_completed;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) reg_state<=IDLE;
        else reg_state<=next_state;
    end
    always @(*) begin
        next_state=reg_state;
        case (reg_state)
            IDLE: if (i_request_valid && o_request_ready) next_state=PREPARE;
            PREPARE: if (flag_fault) next_state=FINISH;
                else next_state=reg_request[336] ? ADDRESS_READ : ADDRESS_WRITE;
            ADDRESS_WRITE: if (i_axi_awready) next_state=DATA_WRITE;
            DATA_WRITE: if (i_axi_wready) next_state=WRITE_RESPONSE;
            WRITE_RESPONSE: if (i_axi_bvalid) begin
                if (i_axi_bresp!=0 || flag_fault || flag_pop) next_state=FINISH;
                else if (reg_word==14) next_state=ADDRESS_READ;
                else next_state=PREPARE;
            end
            ADDRESS_READ: if (i_axi_arready) next_state=READ_RESPONSE;
            READ_RESPONSE: if (i_axi_rvalid) begin
                if (flag_read_error || flag_fault || reg_request[336]) next_state=FINISH;
                else if (!flag_poll && flag_read_identity) next_state=FINISH;
                else if (!flag_poll && reg_read_word==5) next_state=ADDRESS_WRITE;
                else next_state=ADDRESS_READ;
            end
            FINISH: if (i_response_ready) next_state=IDLE;
            default: next_state=IDLE;
        endcase
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            reg_request<=0;reg_word<=0;reg_read_word<=0;flag_poll<=0;flag_pop<=0;
            reg_write_address<=0;reg_read_address<=0;reg_write_data<=0;
            cnt_voice_sequence<=0;cnt_fx_sequence<=0;cnt_watchdog<=0;cnt_completed<=0;
            flag_fault<=0;reg_response<=0;
        end else begin
            // A timeout flags failure but never illegally withdraws an AXI VALID.
            if (reg_state==IDLE || reg_state==FINISH) cnt_watchdog<=0;
            else if (cnt_watchdog<C_WATCHDOG) cnt_watchdog<=cnt_watchdog+1'b1;
            else begin flag_fault<=1;reg_response[135:128]<=6;end
            case (reg_state)
                IDLE: if (i_request_valid && o_request_ready) begin
                    reg_request<=i_request;reg_response<=0;reg_word<=0;reg_read_word<=0;
                    flag_pop<=0;flag_poll<=1;
                end
                PREPARE: begin
                    reg_read_address<=reg_request[359:344];
                    if (reg_word<10) begin
                        reg_write_address<=16'h100+{9'd0,reg_word,2'd0};
                        reg_write_data<=reg_request[reg_word*32+:32];
                    end else begin
                        case (reg_word)
                            10: begin reg_write_address<=16'h128;reg_write_data<={24'd0,reg_request[327:320]};end
                            11: begin reg_write_address<=16'h12c;reg_write_data<=reg_request[391:360];end
                            12: begin reg_write_address<=16'h134;reg_write_data<={24'd1,reg_request[335:328]};end
                            13: begin reg_write_address<=16'h138;reg_write_data<=wire_sequence;end
                            default: begin reg_write_address<=16'h130;reg_write_data<=1;end
                        endcase
                    end
                end
                WRITE_RESPONSE: if (i_axi_bvalid) begin
                    if (i_axi_bresp!=0) begin flag_fault<=1;reg_response[135:128]<=6;end
                    else if (flag_pop) begin
                        if (flag_fx) cnt_fx_sequence<=cnt_fx_sequence+1'b1;
                        else cnt_voice_sequence<=cnt_voice_sequence+1'b1;
                    end else if (reg_word==14) reg_read_address<=16'h008;
                    else reg_word<=reg_word+1'b1;
                end
                READ_RESPONSE: if (i_axi_rvalid) begin
                    if (flag_read_error) begin flag_fault<=1;reg_response[135:128]<=6;end
                    else if (reg_request[336]) reg_response[31:0]<=i_axi_rdata;
                    else if (flag_poll) begin
                        if (i_axi_rdata[6:4]!=0) begin
                            flag_poll<=0;reg_read_word<=0;reg_read_address<=16'h200;
                        end
                    end else if (flag_read_identity) begin flag_fault<=1;reg_response[135:128]<=6;end
                    else begin
                        if (reg_read_word<4) reg_response[reg_read_word*32+:32]<=i_axi_rdata;
                        reg_read_word<=reg_read_word+1'b1;
                        reg_read_address<=reg_read_address+16'd4;
                        if (reg_read_word==5) begin
                            flag_pop<=1;reg_write_address<=16'h218;reg_write_data<=1;
                        end
                    end
                end
                FINISH: if (i_response_ready) cnt_completed<=cnt_completed+1'b1;
                default: reg_word<=reg_word;
            endcase
        end
    end
endmodule
