`timescale 1ns / 1ps
// TelemetryMux：可配置整行仲裁（1至8路）；优先级和普通流各有独立轮询游标。
module TelemetryMux #(
    parameter [15:0] C_BAUD=434,
    parameter integer C_CHANNELS=5
)(
    input i_clk,
    input i_rstn,
    input [C_CHANNELS-1:0] i_valid,
    input [C_CHANNELS*8-1:0] i_data,
    input [C_CHANNELS-1:0] i_priority,
    output [C_CHANNELS-1:0] o_ready,
    output o_tx
);
localparam S_IDLE=1'b0,S_FRAME=1'b1;
reg state,next_state;
reg [2:0] owner,normal_cursor,priority_cursor;
reg [1:0] priority_run;
reg [2:0] selected;
reg found;
reg [C_CHANNELS-1:0] candidates;
reg [2:0] cursor;
reg [C_CHANNELS-1:0] ready_o;
reg uart_start;
reg [7:0] uart_data;
wire uart_busy;
wire [C_CHANNELS-1:0] urgent=i_valid&i_priority;
wire [C_CHANNELS-1:0] ordinary=i_valid&~i_priority;
wire choose_priority=(|urgent) && (priority_run<3 || ordinary==0);
wire [7:0] owner_data=i_data[owner*8 +: 8];
wire transfer=i_valid[owner] && ready_o[owner];
integer offset,candidate;
assign o_ready=ready_o;
EncoderUartTx #(.C_BAUD_CYCLES(C_BAUD)) transmitter(
    .i_clk(i_clk),.i_rstn(i_rstn),.i_start(uart_start),.i_data(uart_data),.o_busy(uart_busy),.o_tx(o_tx));

// 优先流连续最多三个帧，随后为普通流保留一个完整帧。
always @(*) begin
    candidates=choose_priority ? urgent : ordinary;
    cursor=choose_priority ? priority_cursor : normal_cursor;
    selected=0;found=0;candidate=0;
    for(offset=0;offset<C_CHANNELS;offset=offset+1) begin
        candidate=cursor+offset;
        if(candidate>=C_CHANNELS) candidate=candidate-C_CHANNELS;
        if(!found && candidates[candidate]) begin selected=candidate;found=1;end
    end
end
always @(*) begin
    ready_o=0;
    if(state==S_FRAME && !uart_busy && !uart_start) ready_o[owner]=1;
end
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) state<=S_IDLE;
    else state<=next_state;
end
always @(*) begin
    next_state=state;
    case(state)
        S_IDLE: if(found && !uart_busy && !uart_start) next_state=S_FRAME;
        S_FRAME: if(transfer && owner_data==8'h0a) next_state=S_IDLE;
        default: next_state=S_IDLE;
    endcase
end
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin
        owner<=0;normal_cursor<=0;priority_cursor<=0;priority_run<=0;uart_start<=0;uart_data<=0;
    end else begin
        uart_start<=0;
        if(state==S_IDLE && next_state==S_FRAME) begin
            owner<=selected;
            if(choose_priority) begin
                priority_cursor<=selected==C_CHANNELS-1 ? 0 : selected+1'b1;
                if(priority_run<3) priority_run<=priority_run+1'b1;
            end else begin
                normal_cursor<=selected==C_CHANNELS-1 ? 0 : selected+1'b1; priority_run<=0;
            end
        end
        if(transfer) begin uart_data<=owner_data;uart_start<=1;end
    end
end
endmodule
