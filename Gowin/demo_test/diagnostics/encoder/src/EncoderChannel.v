`timescale 1ns / 1ps
// EncoderChannel：同步、稳定时间过滤和正交边沿诊断计数。
module EncoderChannel #(
    parameter [15:0] C_FILTER_CYCLES = 16'd2500 // 默认稳定50us后接受整组AB
)(
    input i_clk,                  // 同一50MHz处理时钟
    input i_rstn,                 // 已同步释放的低有效复位
    input [1:0] i_phase,          // 异步输入，位1为A，位0为B
    output [1:0] o_raw,           // 两级同步后的实时相位
    output [1:0] o_filtered,      // 已接受的稳定相位
    output [15:0] o_position,     // 有符号二补码净边沿数
    output [15:0] o_positive,     // 正向边沿累计，模65536
    output [15:0] o_negative,     // 反向边沿累计，模65536
    output [15:0] o_invalid       // 双位跳变累计，模65536
);
reg [1:0] reg_phase_meta;         // 首级亚稳态隔离寄存器
reg [1:0] reg_phase_sync;         // 第二级采样值用于后续逻辑
reg [1:0] reg_candidate;          // 正在等待稳定的候选相位
reg [15:0] cnt_stable;            // 候选值连续不变的时钟数
reg flag_initialized;            // 首次稳定不计算为旋转
reg [1:0] reg_filtered_o;         // 最近一次接受的相位
reg [15:0] reg_position_o;        // 所有合法边沿的代数和
reg [15:0] reg_positive_o;        // 正序Gray边沿累计
reg [15:0] reg_negative_o;        // 逆序Gray边沿累计
reg [15:0] reg_invalid_o;         // 对角跳变累计

assign o_raw = reg_phase_sync;
assign o_filtered = reg_filtered_o;
assign o_position = reg_position_o;
assign o_positive = reg_positive_o;
assign o_negative = reg_negative_o;
assign o_invalid = reg_invalid_o;

// 外部机械触点进入两级同步器，不能直接参与组合译码。
always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        reg_phase_meta <= 2'b11;
        reg_phase_sync <= 2'b11;
    end else begin
        reg_phase_meta <= i_phase;
        reg_phase_sync <= reg_phase_meta;
    end
end

// 只有整组AB稳定后才提交；反弹的往返边沿在净位置中相互抵消。
always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        reg_candidate <= 2'b11;
        cnt_stable <= 16'd0;
        flag_initialized <= 1'b0;
        reg_filtered_o <= 2'b11;
        reg_position_o <= 16'd0;
        reg_positive_o <= 16'd0;
        reg_negative_o <= 16'd0;
        reg_invalid_o <= 16'd0;
    end else if (reg_phase_sync != reg_candidate) begin
        reg_candidate <= reg_phase_sync;
        cnt_stable <= 16'd0;
    end else if (cnt_stable < C_FILTER_CYCLES - 16'd1) begin
        cnt_stable <= cnt_stable + 16'd1;
    end else if (!flag_initialized) begin
        reg_filtered_o <= reg_candidate;
        flag_initialized <= 1'b1;
    end else if (reg_candidate != reg_filtered_o) begin
        reg_filtered_o <= reg_candidate;
        case ({reg_filtered_o, reg_candidate})
            4'b0001, 4'b0111, 4'b1110, 4'b1000: begin
                reg_position_o <= reg_position_o + 16'd1;
                reg_positive_o <= reg_positive_o + 16'd1;
            end
            4'b0010, 4'b1011, 4'b1101, 4'b0100: begin
                reg_position_o <= reg_position_o - 16'd1;
                reg_negative_o <= reg_negative_o + 16'd1;
            end
            default: begin
                reg_invalid_o <= reg_invalid_o + 16'd1;
            end
        endcase
    end
end
endmodule
