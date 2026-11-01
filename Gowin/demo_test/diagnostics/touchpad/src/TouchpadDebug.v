`timescale 1ns / 1ps
// TouchpadDebug：双独立总线，带 CRC 的左右触摸板原始遥测。
module TouchpadDebug #(
    parameter [15:0] C_DIVIDER=999, C_BAUD=434,
    parameter [7:0] C_SAMPLE_BASE=8'h00,
    parameter integer C_BOOT=2500000, C_RETRY=50000000, C_RESET_WAIT=250000,
    parameter integer C_POLL=1000000, C_TIMEOUT=5000000, C_REPORT=1250000
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
    else begin
        reset_sync<={reset_sync[0],1'b1};
        if(!power_count[15]) power_count<=power_count+1'b1;
    end
end
wire [335:0] left_raw,right_raw;
wire [15:0] left_sequence,right_sequence;
wire [6:0] left_address,right_address;
wire [7:0] left_error,right_error;
MprScanner #(.C_DIVIDER(C_DIVIDER),.C_SAMPLE_BASE(C_SAMPLE_BASE),.C_BOOT(C_BOOT),.C_RETRY(C_RETRY),.C_RESET_WAIT(C_RESET_WAIT),.C_POLL(C_POLL),.C_TIMEOUT(C_TIMEOUT)) left_sensor (
    .i_clk(i_clk),.i_rstn(resetn),.io_scl(io_scl[0]),.io_sda(io_sda[0]),
    .o_raw(left_raw),.o_sequence(left_sequence),.o_address(left_address),.o_error(left_error)
);
MprScanner #(.C_DIVIDER(C_DIVIDER),.C_SAMPLE_BASE(C_SAMPLE_BASE),.C_BOOT(C_BOOT),.C_RETRY(C_RETRY),.C_RESET_WAIT(C_RESET_WAIT),.C_POLL(C_POLL),.C_TIMEOUT(C_TIMEOUT)) right_sensor (
    .i_clk(i_clk),.i_rstn(resetn),.io_scl(io_scl[1]),.io_sda(io_sda[1]),
    .o_raw(right_raw),.o_sequence(right_sequence),.o_address(right_address),.o_error(right_error)
);
reg [5:0] lines_meta,lines_sync;
always @(posedge i_clk) begin
    lines_meta<={io_sda,io_scl,i_irq};
    lines_sync<=lines_meta;
end
reg [31:0] report_count;
reg side,active;
reg [371:0] payload;
reg [6:0] character_index;
reg [7:0] crc,uart_data;
reg [3:0] crc_count;
reg uart_start;
wire uart_busy;
reg [7:0] next_character;
reg [3:0] nibble;
EncoderUartTx #(.C_BAUD_CYCLES(C_BAUD)) uart (
    .i_clk(i_clk),.i_rstn(resetn),.i_start(uart_start),.i_data(uart_data),.o_busy(uart_busy),.o_tx(o_uart_tx)
);
// 95 个正文字符后追加 *CRC 和换行；快照在一整帧期间保持一致。
always @(*) begin
    nibble=payload[371:368];
    if(character_index==96) nibble=crc[7:4];
    if(character_index==97) nibble=crc[3:0];
    next_character=nibble<10 ? 8'h30+{4'b0,nibble} : 8'h41+{4'b0,nibble}-8'd10;
    case(character_index)
        0: next_character=C_SAMPLE_BASE==0 ? "T" : "D";
        1: next_character=side ? "2" : "1";
        95: next_character="*";
        98: next_character=13;
        99: next_character=10;
        default: begin end
    endcase
end
always @(posedge i_clk or negedge resetn) begin
    if(!resetn) begin
        report_count<=0; side<=1; active<=0; payload<=0; character_index<=0;
        crc<=0; crc_count<=0; uart_data<=0; uart_start<=0;
    end else begin
        uart_start<=0;
        if(report_count<C_REPORT) report_count<=report_count+1'b1;
        if(crc_count!=0) begin
            crc<=crc[7] ? {crc[6:0],1'b0}^8'h07 : {crc[6:0],1'b0};
            crc_count<=crc_count-1'b1;
        end
        if(!active && !uart_busy && report_count==C_REPORT) begin
            report_count<=0; side<=!side; active<=1; character_index<=0; crc<=0;
            if(side) payload<={left_sequence,1'b0,left_address,left_error,1'b0,lines_sync[4],lines_sync[2],lines_sync[0],left_raw};
            else payload<={right_sequence,1'b0,right_address,right_error,1'b0,lines_sync[5],lines_sync[3],lines_sync[1],right_raw};
        end else if(active && !uart_busy && !uart_start && crc_count==0) begin
            uart_data<=next_character; uart_start<=1;
            if(character_index<95) begin crc<=crc^next_character; crc_count<=8; end
            if(character_index>=2 && character_index<95) payload<={payload[367:0],4'b0};
            if(character_index==99) active<=0;
            else character_index<=character_index+1'b1;
        end
    end
end
endmodule
