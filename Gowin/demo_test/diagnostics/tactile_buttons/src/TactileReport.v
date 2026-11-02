`timescale 1ns / 1ps
// TactileReport: coherent six-switch snapshots with CRC-protected ASCII UART.
// 六键共享快照，串行计算校验，不停止输入侧的连续去抖和计数。
module TactileReport #(
    parameter [31:0] C_REPORT_CYCLES = 32'd1000000, // 二十毫秒快照周期
    parameter [15:0] C_BAUD_CYCLES = 16'd434 // 五十兆赫兹下的115200串口
)(
    input i_clk, // 遥测与UART共用时钟
    input i_rstn, // 低有效内部复位
    input [5:0] i_raw, // 六键同步物理电平
    input [5:0] i_pressed, // 六键去抖后的按压电平
    input [95:0] i_presses, // 高位起按SW1至SW6排列
    input [95:0] i_releases, // 对应六键松开沿计数
    input [95:0] i_edges, // 对应六键原始翻转计数
    output o_tx // 板载DEBUG发送引脚
);
    localparam [3:0] ST_IDLE=0, ST_CAPTURE=1, ST_SELECT=2, ST_CRC=3;
    localparam [3:0] ST_SEND=4, ST_ACCEPT=5, ST_WAIT=6, ST_ADVANCE=7;
    reg [3:0] state_current, state_next; // 三段式发送控制状态
    reg [31:0] cnt_report; // 周期节拍计数
    reg [15:0] cnt_sequence; // 实际发送快照序号
    reg [319:0] reg_snapshot; // 发送期间仅移位，不读取变化中的输入
    reg [6:0] cnt_character; // 固定八十七字节的当前位置
    reg [2:0] cnt_crc_bit; // 当前ASCII字节的校验位步数
    reg [7:0] reg_crc; // ASCII报文体的CRC余数
    reg [7:0] reg_character; // 本字节在整个UART忙周期内保持
    reg [3:0] enc_nibble; // 数据或CRC的待编码半字节
    reg [7:0] enc_character; // 根据字符索引选择的编码结果
    wire [7:0] enc_hex; // 半字节转换为大写十六进制
    wire flag_busy; // 真实UART停止位完成标志
    wire flag_start = state_current == ST_SEND; // 每字符仅提交一拍
    wire flag_tick = cnt_report == C_REPORT_CYCLES - 32'd1; // 周期终点
    assign enc_hex = enc_nibble < 10 ? 8'd48 + {4'd0,enc_nibble} : 8'd55 + {4'd0,enc_nibble};

    // 忙时跳过周期，绝不覆盖当前正在发送的快照。
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) cnt_report <= 0;
        else if (flag_tick) cnt_report <= 0;
        else cnt_report <= cnt_report + 1'b1;
    end
    // 状态寄存器只接受完整的下一状态决策。
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) state_current <= ST_IDLE;
        else state_current <= state_next;
    end
    // 等待UART忙的上升和下降，确保没有重复提交或丢失停止位。
    always @(*) begin
        state_next = state_current;
        case (state_current)
            ST_IDLE: if (flag_tick) state_next=ST_CAPTURE;
            ST_CAPTURE: state_next=ST_SELECT;
            ST_SELECT: if (cnt_character<82) state_next=ST_CRC; else state_next=ST_SEND;
            ST_CRC: if (cnt_crc_bit==7) state_next=ST_SEND;
            ST_SEND: state_next=ST_ACCEPT;
            ST_ACCEPT: if (flag_busy) state_next=ST_WAIT;
            ST_WAIT: if (!flag_busy) state_next=ST_ADVANCE;
            ST_ADVANCE: if (cnt_character==86) state_next=ST_IDLE; else state_next=ST_SELECT;
            default: state_next=ST_IDLE;
        endcase
    end
    // 全字段同拍锁存，数据段每发送一个半字节才移位。
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin reg_snapshot<=0;cnt_sequence<=0;cnt_character<=0;end
        else if (state_current==ST_CAPTURE) begin
            reg_snapshot<={cnt_sequence,2'b00,i_raw,2'b00,i_pressed,i_presses,i_releases,i_edges};
            cnt_sequence<=cnt_sequence+1'b1;
            cnt_character<=0;
        end else if (state_current==ST_ADVANCE) begin
            cnt_character<=cnt_character+1'b1;
            if (cnt_character>=2 && cnt_character<82) reg_snapshot<={reg_snapshot[315:0],4'b0000};
        end
    end
    // CRC仅覆盖B1开头至最后一个数据半字节，星号及CRC文本不参与。
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin reg_crc<=0;cnt_crc_bit<=0;reg_character<=0;end
        else if (state_current==ST_CAPTURE) begin reg_crc<=0;cnt_crc_bit<=0;end
        else if (state_current==ST_SELECT) begin
            reg_character<=enc_character;
            cnt_crc_bit<=0;
            if (cnt_character<82) reg_crc<=reg_crc^enc_character;
        end else if (state_current==ST_CRC) begin
            reg_crc<={reg_crc[6:0],1'b0} ^ (reg_crc[7] ? 8'h07 : 8'h00);
            cnt_crc_bit<=cnt_crc_bit+1'b1;
        end
    end
    // 帧尾CRC读取独立寄存器，避免快照移空后丢失校验值。
    always @(*) begin
        enc_nibble=reg_snapshot[319:316];
        case (cnt_character)
            83:enc_nibble=reg_crc[7:4];
            84:enc_nibble=reg_crc[3:0];
            default:enc_nibble=reg_snapshot[319:316];
        endcase
    end
    // 固定头尾之外的所有字段统一使用大写十六进制。
    always @(*) begin
        enc_character=enc_hex;
        case (cnt_character)
            0:enc_character="B";
            1:enc_character="1";
            82:enc_character="*";
            85:enc_character=13;
            86:enc_character=10;
            default:enc_character=enc_hex;
        endcase
    end
    // 沿用已验证的串口物理发送器；报告器只在空闲时启动。
    EncoderUartTx #(.C_BAUD_CYCLES(C_BAUD_CYCLES)) Uart_Inst(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_start(flag_start),.i_data(reg_character),
        .o_busy(flag_busy),.o_tx(o_tx));
endmodule
