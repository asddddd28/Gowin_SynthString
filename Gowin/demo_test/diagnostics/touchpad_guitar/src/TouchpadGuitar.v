`timescale 1ns / 1ps
// TouchpadGuitar：双总线采样、硬件划弦、优先事件串口。
module TouchpadGuitar #(
    parameter [15:0] C_DIVIDER=99, C_BAUD=434,
    parameter integer C_BOOT=2500000, C_RETRY=50000000, C_RESET_WAIT=250000,
    parameter integer C_POLL=0, C_TIMEOUT=2000000, C_REPORT=1250000, C_MS=50000
)(
    input i_clk,
    input i_rstn,
    input [1:0] i_irq,
    inout [1:0] io_scl,
    inout [1:0] io_sda,
    output o_uart_tx
);
reg [1:0] reset_sync=0;
reg [15:0] power_count=0;
wire resetn=reset_sync[1] && power_count[15];
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin reset_sync<=0; power_count<=0; end
    else begin reset_sync<={reset_sync[0],1'b1}; if(!power_count[15]) power_count<=power_count+1'b1; end
end
reg [31:0] millisecond_count,milliseconds;
always @(posedge i_clk or negedge resetn) begin
    if(!resetn) begin millisecond_count<=0; milliseconds<=0; end
    else if(millisecond_count==C_MS-1) begin millisecond_count<=0; milliseconds<=milliseconds+1'b1; end
    else millisecond_count<=millisecond_count+1'b1;
end
wire [335:0] left_raw,right_raw;
wire [15:0] left_sequence,right_sequence;
wire [6:0] left_address,right_address;
wire [7:0] left_error,right_error;
MprScanner #(.C_DIVIDER(C_DIVIDER),.C_BOOT(C_BOOT),.C_RETRY(C_RETRY),.C_RESET_WAIT(C_RESET_WAIT),.C_POLL(C_POLL),.C_TIMEOUT(C_TIMEOUT)) left_sensor (
    .i_clk(i_clk),.i_rstn(resetn),.io_scl(io_scl[0]),.io_sda(io_sda[0]),
    .o_raw(left_raw),.o_sequence(left_sequence),.o_address(left_address),.o_error(left_error)
);
MprScanner #(.C_DIVIDER(C_DIVIDER),.C_BOOT(C_BOOT),.C_RETRY(C_RETRY),.C_RESET_WAIT(C_RESET_WAIT),.C_POLL(C_POLL),.C_TIMEOUT(C_TIMEOUT)) right_sensor (
    .i_clk(i_clk),.i_rstn(resetn),.io_scl(io_scl[1]),.io_sda(io_sda[1]),
    .o_raw(right_raw),.o_sequence(right_sequence),.o_address(right_address),.o_error(right_error)
);
wire left_event,right_event;
wire [5:0] left_mask,right_mask;
wire [3:0] left_flags,right_flags;
wire [9:0] left_x,left_y,right_x,right_y;
wire [15:0] left_sample,right_sample;
wire [31:0] left_time,right_time;
GuitarTracker left_tracker (
    .i_clk(i_clk),.i_rstn(resetn),.i_milliseconds(milliseconds),.i_raw(left_raw),.i_sequence(left_sequence),.i_error(left_error),
    .o_event(left_event),.o_mask(left_mask),.o_flags(left_flags),.o_x(left_x),.o_y(left_y),.o_sequence(left_sample),.o_time(left_time)
);
GuitarTracker right_tracker (
    .i_clk(i_clk),.i_rstn(resetn),.i_milliseconds(milliseconds),.i_raw(right_raw),.i_sequence(right_sequence),.i_error(right_error),
    .o_event(right_event),.o_mask(right_mask),.o_flags(right_flags),.o_x(right_x),.o_y(right_y),.o_sequence(right_sample),.o_time(right_time)
);
wire [95:0] left_event_data={12'b0,left_sample,left_time,left_flags,2'b0,left_mask,2'b0,left_x,2'b0,left_y};
wire [95:0] right_event_data={12'b0,right_sample,right_time,right_flags,2'b0,right_mask,2'b0,right_x,2'b0,right_y};
wire [95:0] left_head,right_head;
wire left_empty,right_empty;
wire [15:0] left_dropped,right_dropped;
reg left_pop,right_pop;
GuitarEventQueue left_queue (
    .i_clk(i_clk),.i_rstn(resetn),.i_push(left_event),.i_data(left_event_data),.i_pop(left_pop),
    .o_empty(left_empty),.o_data(left_head),.o_dropped(left_dropped)
);
GuitarEventQueue right_queue (
    .i_clk(i_clk),.i_rstn(resetn),.i_push(right_event),.i_data(right_event_data),.i_pop(right_pop),
    .o_empty(right_empty),.o_data(right_head),.o_dropped(right_dropped)
);
reg [5:0] lines_meta,lines_sync;
always @(posedge i_clk) begin lines_meta<={io_sda,io_scl,i_irq}; lines_sync<=lines_meta; end
reg [31:0] report_count;
reg report_side,side,active,short_frame,heartbeat_pending,event_prefer_right;
reg [15:0] left_packet,right_packet;
reg [371:0] payload;
reg [6:0] character_index;
reg [7:0] crc,uart_data,next_character;
reg [3:0] crc_count,nibble;
reg uart_start;
wire uart_busy;
wire [6:0] body_end=short_frame ? 7'd32 : 7'd95;
wire [6:0] first_payload=short_frame ? 7'd3 : 7'd2;
wire choose_right=left_empty || (!right_empty && event_prefer_right);
wire [95:0] event_head=choose_right ? right_head : left_head;
EncoderUartTx #(.C_BAUD_CYCLES(C_BAUD)) uart (
    .i_clk(i_clk),.i_rstn(resetn),.i_start(uart_start),.i_data(uart_data),.o_busy(uart_busy),.o_tx(o_uart_tx)
);
// 一个事件帧37字节；只有完整帧边界允许仲裁，避免串口帧拼接损坏。
always @(*) begin
    nibble=payload[371:368];
    if(character_index==body_end+1) nibble=crc[7:4];
    if(character_index==body_end+2) nibble=crc[3:0];
    next_character=nibble<10 ? 8'h30+{4'b0,nibble} : 8'h37+{4'b0,nibble};
    if(character_index==0) next_character=short_frame ? "G" : "T";
    else if(character_index==1) next_character=short_frame ? "1" : side ? "2" : "1";
    else if(short_frame && character_index==2) next_character=side ? "2" : "1";
    else if(character_index==body_end) next_character="*";
    else if(character_index==body_end+3) next_character=13;
    else if(character_index==body_end+4) next_character=10;
end
always @(posedge i_clk or negedge resetn) begin
    if(!resetn) begin
        report_count<=0; report_side<=1; side<=0; active<=0; short_frame<=0;
        heartbeat_pending<=0; event_prefer_right<=0; left_packet<=0; right_packet<=0;
        payload<=0; character_index<=0; crc<=0; crc_count<=0; uart_data<=0; uart_start<=0;
        left_pop<=0; right_pop<=0;
    end else begin
        uart_start<=0; left_pop<=0; right_pop<=0;
        if(report_count<C_REPORT) report_count<=report_count+1'b1;
        if(crc_count!=0) begin
            crc<=crc[7] ? {crc[6:0],1'b0}^8'h07 : {crc[6:0],1'b0}; crc_count<=crc_count-1'b1;
        end
        if(!active && !uart_busy && !uart_start) begin
            character_index<=0; crc<=0;
            if(!left_empty || !right_empty) begin
                active<=1; short_frame<=1; side<=choose_right; event_prefer_right<=!choose_right;
                payload<={choose_right ? right_packet : left_packet,event_head[83:0],choose_right ? right_dropped : left_dropped,256'b0};
                if(choose_right) begin right_pop<=1; right_packet<=right_packet+1'b1; end
                else begin left_pop<=1; left_packet<=left_packet+1'b1; end
            end else if(heartbeat_pending) begin
                active<=1; short_frame<=1; heartbeat_pending<=0; side<=report_side;
                if(report_side) begin
                    payload<={right_packet,right_sample,right_time,right_flags,8'b0,2'b0,right_x,2'b0,right_y,right_dropped,256'b0};
                    right_packet<=right_packet+1'b1;
                end else begin
                    payload<={left_packet,left_sample,left_time,left_flags,8'b0,2'b0,left_x,2'b0,left_y,left_dropped,256'b0};
                    left_packet<=left_packet+1'b1;
                end
            end else if(report_count==C_REPORT) begin
                report_count<=0; report_side<=!report_side; side<=!report_side;
                active<=1; short_frame<=0; heartbeat_pending<=1;
                if(report_side) payload<={left_sequence,1'b0,left_address,left_error,1'b0,lines_sync[4],lines_sync[2],lines_sync[0],left_raw};
                else payload<={right_sequence,1'b0,right_address,right_error,1'b0,lines_sync[5],lines_sync[3],lines_sync[1],right_raw};
            end
        end else if(active && !uart_busy && !uart_start && crc_count==0) begin
            uart_data<=next_character; uart_start<=1;
            if(character_index<body_end) begin crc<=crc^next_character; crc_count<=8; end
            if(character_index>=first_payload && character_index<body_end) payload<={payload[367:0],4'b0};
            if(character_index==body_end+4) active<=0;
            else character_index<=character_index+1'b1;
        end
    end
end
endmodule
