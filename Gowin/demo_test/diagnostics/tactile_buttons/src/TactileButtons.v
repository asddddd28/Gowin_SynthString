`timescale 1ns / 1ps
// TactileButtons: standalone switch bring-up, no RGB or touchpad transactions.
// 六路只读输入独立去抖；共享串口；关闭RGB信号及板载喇叭功放。
module TactileButtons #(
    parameter [31:0] C_STABLE_CYCLES=32'd250000, // 五毫秒去抖
    parameter [31:0] C_REPORT_CYCLES=32'd1000000, // 五十赫兹遥测
    parameter [15:0] C_BAUD_CYCLES=16'd434 // DEBUG串口位周期
)(
    input i_clk, // 板上五十兆赫兹时钟
    input i_rstn, // KEY0低有效复位
    input [5:0] i_buttons, // SW1对应最低位，按下高有效
    output o_uart_tx, // 115200八数据位无校验一停止位
    output o_rgb, // 保持低电平，不生成RGB数据
    output o_pa_disable // 高电平关闭板载扬声器功放
);
    reg [1:0] reg_reset_release=0; // 异步复位后的两拍释放链
    reg [15:0] cnt_power=0; // FPGA配置后的确定性启动等待
    wire flag_reset_n=reg_reset_release[1] && cnt_power[15]; // 局部稳定复位
    wire [5:0] bus_raw; // 六路同步输入电平
    wire [5:0] bus_pressed; // 六路稳定检测结果
    wire [95:0] bus_presses; // SW1在最高十六位
    wire [95:0] bus_releases; // 与按下计数相同通道顺序
    wire [95:0] bus_edges; // 抖动边沿统计
    genvar idx_button; // 六个互不影响的采样通道
    assign o_rgb=1'b0; // RGB本轮不测试
    assign o_pa_disable=1'b1; // 防止切换固件后音频输出浮动
    // 上电初始化及外部复位均先等待启动计数再释放下游。
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin reg_reset_release<=0;cnt_power<=0;end
        else begin
            reg_reset_release<={reg_reset_release[0],1'b1};
            if (!cnt_power[15]) cnt_power<=cnt_power+1'b1;
        end
    end
    // 每颗开关各有独立计时器，可同时按下，不互相重置候选。
    generate
        for (idx_button=0;idx_button<6;idx_button=idx_button+1) begin:gen_buttons
            TactileInput #(.C_STABLE_CYCLES(C_STABLE_CYCLES)) Button_Inst(
                .i_clk(i_clk),.i_rstn(flag_reset_n),.i_switch(i_buttons[idx_button]),
                .o_raw(bus_raw[idx_button]),.o_pressed(bus_pressed[idx_button]),
                .o_presses(bus_presses[95-idx_button*16 -: 16]),
                .o_releases(bus_releases[95-idx_button*16 -: 16]),
                .o_edges(bus_edges[95-idx_button*16 -: 16]));
        end
    endgenerate
    // 一行快照覆盖六颗开关和全部计数器。
    TactileReport #(.C_REPORT_CYCLES(C_REPORT_CYCLES),.C_BAUD_CYCLES(C_BAUD_CYCLES)) Report_Inst(
        .i_clk(i_clk),.i_rstn(flag_reset_n),.i_raw(bus_raw),.i_pressed(bus_pressed),
        .i_presses(bus_presses),.i_releases(bus_releases),.i_edges(bus_edges),.o_tx(o_uart_tx));
endmodule
