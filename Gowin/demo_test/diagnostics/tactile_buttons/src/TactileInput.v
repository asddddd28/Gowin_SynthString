`timescale 1ns / 1ps
// TactileInput: synchronize and debounce one active-high mechanical switch.
// 单键独立去抖，持续按住不重复累计；计数器按无符号十六位回绕。
module TactileInput #(
    parameter [31:0] C_STABLE_CYCLES = 32'd250000 // 连续稳定五毫秒
)(
    input i_clk, // 五十兆赫兹采样时钟
    input i_rstn, // 同步释放的低有效复位
    input i_switch, // 异步按钮电平，按下为高
    output o_raw, // 两级同步后的物理电平
    output o_pressed, // 达到稳定窗口后的按压状态
    output [15:0] o_presses, // 已确认的按下沿总数
    output [15:0] o_releases, // 已确认的松开沿总数
    output [15:0] o_edges // 同步原始输入的翻转总数
);
    reg reg_meta; // 第一同步级，仅用于抑制亚稳态传播
    reg reg_sync; // 第二同步级，作为唯一检测输入
    reg reg_previous; // 上一拍原始输入，用于捕获抖动沿
    reg reg_pressed_o; // 已确认的稳定状态
    reg [31:0] cnt_stable; // 不同于当前状态的连续采样数
    reg [15:0] cnt_presses_o; // 按下边沿累加器
    reg [15:0] cnt_releases_o; // 松开边沿累加器
    reg [15:0] cnt_edges_o; // 原始抖动翻转累加器
    wire flag_change = reg_sync != reg_pressed_o; // 稳定状态尚未跟随输入
    wire flag_commit = cnt_stable == C_STABLE_CYCLES - 32'd1; // 最后一个稳定采样
    assign o_raw = reg_sync; // 输出同步电平，不反馈外部引脚
    assign o_pressed = reg_pressed_o; // 输出确认后的逻辑状态
    assign o_presses = cnt_presses_o; // 按下次数可跨遥测间隔保留
    assign o_releases = cnt_releases_o; // 松开次数不依赖上位机刷新
    assign o_edges = cnt_edges_o; // 暴露抖动活动用于连接诊断

    // 异步输入仅经过此同步链进入其余逻辑。
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin reg_meta <= 1'b0; reg_sync <= 1'b0; end
        else begin reg_meta <= i_switch; reg_sync <= reg_meta; end
    end
    // 每次回到当前稳定状态即取消候选，双向使用相同窗口。
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin cnt_stable <= 0; reg_pressed_o <= 0; end
        else if (!flag_change) cnt_stable <= 0;
        else if (flag_commit) begin cnt_stable <= 0; reg_pressed_o <= reg_sync; end
        else cnt_stable <= cnt_stable + 1'b1;
    end
    // 只在确认边沿时累计，保持电平不会重复报告按下。
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin cnt_presses_o <= 0; cnt_releases_o <= 0; end
        else if (flag_change && flag_commit) begin
            if (reg_sync) cnt_presses_o <= cnt_presses_o + 1'b1;
            else cnt_releases_o <= cnt_releases_o + 1'b1;
        end
    end
    // 原始边沿计数包含被去抖窗口拒绝的窄脉冲。
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin reg_previous <= 0; cnt_edges_o <= 0; end
        else begin
            reg_previous <= reg_sync;
            if (reg_previous != reg_sync) cnt_edges_o <= cnt_edges_o + 1'b1;
        end
    end
endmodule
