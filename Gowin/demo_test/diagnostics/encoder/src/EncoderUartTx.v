`timescale 1ns / 1ps
// EncoderUartTx：空闲时接受单拍start，输出完整8N1字节。
module EncoderUartTx #(
    parameter [15:0] C_BAUD_CYCLES = 16'd434 // 50MHz时约115207波特
)(
    input i_clk,                   // UART位时间基准
    input i_rstn,                  // 低有效复位，立即恢复空闲高
    input i_start,                 // 空闲时为高则锁存字节
    input [7:0] i_data,            // 低位先发的有效载荷
    output o_busy,                 // 包括起始、数据、停止位的忙标志
    output o_tx                    // UART串行输出
);
reg [9:0] reg_shift;               // 停止位、数据、起始位组合帧
reg [3:0] cnt_bit;                 // 当前发送位编号0到9
reg [15:0] cnt_baud;               // 位内主时钟计数
reg flag_busy_o;                  // 完成停止位后清零
assign o_tx = reg_shift[0];
assign o_busy = flag_busy_o;

// 发送期间忽略start，确保未完成的字节不会被覆盖。
always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        reg_shift <= 10'h3ff;
        cnt_bit <= 4'd0;
        cnt_baud <= 16'd0;
        flag_busy_o <= 1'b0;
    end else if (!flag_busy_o) begin
        if (i_start) begin
            reg_shift <= {1'b1, i_data, 1'b0};
            cnt_bit <= 4'd0;
            cnt_baud <= 16'd0;
            flag_busy_o <= 1'b1;
        end
    end else if (cnt_baud == C_BAUD_CYCLES - 16'd1) begin
        cnt_baud <= 16'd0;
        reg_shift <= {1'b1, reg_shift[9:1]};
        if (cnt_bit == 4'd9) begin
            flag_busy_o <= 1'b0;
        end else begin
            cnt_bit <= cnt_bit + 4'd1;
        end
    end else begin
        cnt_baud <= cnt_baud + 16'd1;
    end
end
endmodule
