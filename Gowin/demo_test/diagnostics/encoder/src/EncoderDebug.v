`timescale 1ns / 1ps
// EncoderDebug：五路独立计数，每100ms用ASCII串口报告诊断快照。
module EncoderDebug #(
    parameter [15:0] C_FILTER_CYCLES = 16'd2500, // AB稳定过滤50us
    parameter [15:0] C_BAUD_CYCLES = 16'd434,    // 串口115200 8N1
    parameter [31:0] C_REPORT_CYCLES = 32'd5000000 // 每100ms启动一轮报告
)(
    input i_clk,                  // V22板载50MHz
    input i_rstn,                 // AA13板载低有效复位
    input [4:0] i_encoder_a,       // 依次对应编码器1至5的A端
    input [4:0] i_encoder_b,       // 依次对应编码器1至5的B端
    output o_uart_tx              // U15连接板载USB-UART
);
localparam [2:0] ST_IDLE=3'd0, ST_LATCH=3'd1, ST_SEND=3'd2,
    ST_BUSY=3'd3, ST_WAIT=3'd4, ST_ADVANCE=3'd5;
reg [1:0] reg_reset_release;       // 异步拉低、两拍同步释放
wire flag_reset_n;
wire [9:0] bus_raw, bus_filtered; // 每路占两位，低位编码器在低地址
wire [79:0] bus_position, bus_positive, bus_negative, bus_invalid;
reg [2:0] state_current, state_next;
reg [31:0] cnt_report;            // 与串口发送独立的周期计数
reg [2:0] cnt_encoder;            // 当前报告的编码器索引0至4
reg [5:0] cnt_character;          // 固定34字节行中的字符位置
reg [1:0] reg_raw, reg_filtered;  // 一行开始时锁存的相位
reg [15:0] reg_position, reg_positive, reg_negative, reg_invalid;
reg [7:0] enc_character;          // 固定模板和十六进制数生成的字节
reg [3:0] enc_nibble;             // 当前数值字段的一个十六进制位
wire [7:0] enc_hex;
wire flag_uart_busy;
wire flag_uart_start;
genvar idx_encoder;

assign flag_reset_n = reg_reset_release[1];
assign flag_uart_start = (state_current == ST_SEND);
assign enc_hex = (enc_nibble < 4'd10) ? (8'd48 + {4'd0,enc_nibble}) : (8'd55 + {4'd0,enc_nibble});

// 板载按键释放经过主时钟同步，所有下游共享这一复位。
always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        reg_reset_release <= 2'b00;
    end else begin
        reg_reset_release <= {reg_reset_release[0],1'b1};
    end
end

// 每个编码器使用独立状态与计数器，避免多路同时旋转互相阻塞。
generate
    for (idx_encoder=0; idx_encoder<5; idx_encoder=idx_encoder+1) begin: gen_encoder
        EncoderChannel #(.C_FILTER_CYCLES(C_FILTER_CYCLES)) u_channel (
            .i_clk(i_clk), .i_rstn(flag_reset_n),
            .i_phase({i_encoder_a[idx_encoder],i_encoder_b[idx_encoder]}),
            .o_raw(bus_raw[idx_encoder*2 +: 2]),
            .o_filtered(bus_filtered[idx_encoder*2 +: 2]),
            .o_position(bus_position[idx_encoder*16 +: 16]),
            .o_positive(bus_positive[idx_encoder*16 +: 16]),
            .o_negative(bus_negative[idx_encoder*16 +: 16]),
            .o_invalid(bus_invalid[idx_encoder*16 +: 16])
        );
    end
endgenerate

// 一个UART实例轮流发送五路快照；报告节流避免占满调试器缓存。
EncoderUartTx #(.C_BAUD_CYCLES(C_BAUD_CYCLES)) u_uart (
    .i_clk(i_clk), .i_rstn(flag_reset_n), .i_start(flag_uart_start),
    .i_data(enc_character), .o_busy(flag_uart_busy), .o_tx(o_uart_tx)
);

// 固定报告周期，忙时到期会跳过该次而不会覆盖未发完的数据。
always @(posedge i_clk or negedge flag_reset_n) begin
    if (!flag_reset_n) begin
        cnt_report <= 32'd0;
    end else if (cnt_report == C_REPORT_CYCLES - 32'd1) begin
        cnt_report <= 32'd0;
    end else begin
        cnt_report <= cnt_report + 32'd1;
    end
end

// 三段状态机的状态寄存器。
always @(posedge i_clk or negedge flag_reset_n) begin
    if (!flag_reset_n) begin
        state_current <= ST_IDLE;
    end else begin
        state_current <= state_next;
    end
end

// 先等待UART确认接受，再等待停止位结束，避免重复或漏发字符。
always @(*) begin
    state_next = state_current;
    case (state_current)
        ST_IDLE: begin
            if (cnt_report == C_REPORT_CYCLES - 32'd1) begin state_next=ST_LATCH; end
        end
        ST_LATCH: begin state_next=ST_SEND; end
        ST_SEND: begin state_next=ST_BUSY; end
        ST_BUSY: begin
            if (flag_uart_busy) begin state_next=ST_WAIT; end
        end
        ST_WAIT: begin
            if (!flag_uart_busy) begin state_next=ST_ADVANCE; end
        end
        ST_ADVANCE: begin
            if (cnt_character != 6'd33) begin state_next=ST_SEND; end
            else if (cnt_encoder != 3'd4) begin state_next=ST_LATCH; end
            else begin state_next=ST_IDLE; end
        end
        default: begin state_next=ST_IDLE; end
    endcase
end

// 每行锁存完整计数值，避免四个十六进制字符来自不同时间。
always @(posedge i_clk or negedge flag_reset_n) begin
    if (!flag_reset_n) begin
        cnt_encoder<=3'd0; cnt_character<=6'd0;
        reg_raw<=2'd0; reg_filtered<=2'd0;
        reg_position<=16'd0; reg_positive<=16'd0;
        reg_negative<=16'd0; reg_invalid<=16'd0;
    end else begin
        case (state_current)
            ST_IDLE: begin cnt_encoder<=3'd0; cnt_character<=6'd0; end
            ST_LATCH: begin
                cnt_character<=6'd0;
                reg_raw<=bus_raw[cnt_encoder*2 +: 2];
                reg_filtered<=bus_filtered[cnt_encoder*2 +: 2];
                reg_position<=bus_position[cnt_encoder*16 +: 16];
                reg_positive<=bus_positive[cnt_encoder*16 +: 16];
                reg_negative<=bus_negative[cnt_encoder*16 +: 16];
                reg_invalid<=bus_invalid[cnt_encoder*16 +: 16];
            end
            ST_ADVANCE: begin
                if (cnt_character==6'd33) begin cnt_encoder<=cnt_encoder+3'd1; end
                else begin cnt_character<=cnt_character+6'd1; end
            end
            default: begin end
        endcase
    end
end

// 字段按大端十六进制输出，主机把Q解释为16位有符号数。
always @(*) begin
    enc_nibble=4'd0;
    case (cnt_character)
        6'd10: begin enc_nibble=reg_position[15:12]; end
        6'd11: begin enc_nibble=reg_position[11:8]; end
        6'd12: begin enc_nibble=reg_position[7:4]; end
        6'd13: begin enc_nibble=reg_position[3:0]; end
        6'd16: begin enc_nibble=reg_positive[15:12]; end
        6'd17: begin enc_nibble=reg_positive[11:8]; end
        6'd18: begin enc_nibble=reg_positive[7:4]; end
        6'd19: begin enc_nibble=reg_positive[3:0]; end
        6'd22: begin enc_nibble=reg_negative[15:12]; end
        6'd23: begin enc_nibble=reg_negative[11:8]; end
        6'd24: begin enc_nibble=reg_negative[7:4]; end
        6'd25: begin enc_nibble=reg_negative[3:0]; end
        6'd28: begin enc_nibble=reg_invalid[15:12]; end
        6'd29: begin enc_nibble=reg_invalid[11:8]; end
        6'd30: begin enc_nibble=reg_invalid[7:4]; end
        6'd31: begin enc_nibble=reg_invalid[3:0]; end
        default: begin enc_nibble=4'd0; end
    endcase
end

// E编号、原始AB、过滤AB、净位置、正反边沿数、非法跳变数。
always @(*) begin
    enc_character=enc_hex;
    case (cnt_character)
        6'd0: begin enc_character="E"; end
        6'd1: begin enc_character=8'd49+{5'd0,cnt_encoder}; end
        6'd2,6'd5,6'd8,6'd14,6'd20,6'd26: begin enc_character=8'd32; end
        6'd3: begin enc_character="A"; end
        6'd4: begin enc_character=8'd48+{6'd0,reg_raw}; end
        6'd6: begin enc_character="F"; end
        6'd7: begin enc_character=8'd48+{6'd0,reg_filtered}; end
        6'd9: begin enc_character="Q"; end
        6'd15: begin enc_character="P"; end
        6'd21: begin enc_character="N"; end
        6'd27: begin enc_character="X"; end
        6'd32: begin enc_character=8'h0d; end
        6'd33: begin enc_character=8'h0a; end
        default: begin enc_character=enc_hex; end
    endcase
end
endmodule
