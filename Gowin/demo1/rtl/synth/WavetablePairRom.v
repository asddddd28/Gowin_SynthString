`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/12 00:11:00
// Design Name:     WavetablePairRom
// Module Name:     WavetablePairRom
// Description:     description/WavetablePairRom_Design.pdf
// Simulations:     testbench/vivado/2021.1/WavetablePairRom
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/12 00:11:00
// History:
// Time             Version     Revised by        Contents
// 2026/10/12       V1.0        Codex             Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月12日
// 设计名称:        WavetablePairRom
// 模块名称:        WavetablePairRom
// 模块说明:        Description/WavetablePairRom_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/WavetablePairRom
//
// 参考资料:        None
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年10月12日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月12日   V1.0        Codex             创建文件

module WavetablePairRom(
    input i_clk, // 样点计算时钟
    input i_rstn, // 算术流水复位
    input [31:0] i_phase, // 周期相位
    input [2:0] i_wave, // 兼容原波形选择
    input i_table_write, // 后台资源写入
    input [10:0] i_table_address, // 银行与点索引
    input [15:0] i_table_data, // 十六位量化样点
    input i_table_frame, // 写入的前后帧
    input i_table_bank, // 活动银行
    input i_table_available, // 资源有效标志
    input i_table_two, // 双帧资源已完整提交
    input [15:0] i_frame_fraction, // 同一四点事务的帧间权重
    output signed [17:0] o_sample // 九拍后音频幅度
);
    reg signed [17:0] reg_sine [0:1023]; // 原有正弦周期资源
    reg signed [17:0] reg_sine_first,reg_sine_second,reg_shape; // 同步读取基础波形
    wire signed [15:0] wire_first_a,wire_second_a,wire_first_b,wire_second_b; // 同一银行的四个点
    reg flag_sine,flag_custom,flag_two; // 与缓存读数一起采样的来源标志
    reg [15:0] reg_phase_fraction,reg_frame_fraction; // 缓存对应小数
    reg signed [17:0] reg_first_a,reg_second_a,reg_first_b,reg_second_b; // 交付算术核心的四点快照
    reg [15:0] reg_selected_phase,reg_selected_frame; // 第二拍与四点配对的小数
    wire [9:0] enc_next_address = i_phase[31:22] + 10'd1; // 基础正弦末点回绕
    wire [17:0] enc_triangle = i_phase[30] ? ~i_phase[29:12] : i_phase[29:12]; // 旧三角算法
    initial $readmemb("rtl/synth/sine.mem",reg_sine);
    WavetablePairCache Cache_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_write(i_table_write),
        .i_address(i_table_address),.i_frame(i_table_frame),.i_data(i_table_data),.i_phase(i_phase),.i_bank(i_table_bank),
        .o_first_a(wire_first_a),.o_second_a(wire_second_a),.o_first_b(wire_first_b),.o_second_b(wire_second_b));
    always @(posedge i_clk) begin
        reg_sine_first <= reg_sine[i_phase[31:22]];
        reg_sine_second <= reg_sine[enc_next_address];
        flag_sine <= (i_wave==0)||(i_wave==4&&!i_table_available);
        flag_custom <= (i_wave==4)&&i_table_available;
        flag_two <= (i_wave==4)&&i_table_available&&i_table_two;
        reg_phase_fraction <= ((i_wave==0)||(i_wave==4)) ? i_phase[21:6] : 16'd0;
        reg_frame_fraction <= i_frame_fraction;
        case(i_wave)
            3'd0: reg_shape <= 18'd0;
            3'd1: reg_shape <= i_phase[31] ? -18'sd131071 : 18'sd131071;
            3'd2: reg_shape <= {~i_phase[31],i_phase[30:14]};
            default: reg_shape <= i_phase[31] ? -$signed({1'b0,enc_triangle[17:1]}) : $signed({1'b0,enc_triangle[17:1]});
        endcase
    end
    always @(posedge i_clk) begin
        reg_first_a <= flag_custom ? {wire_first_a,2'b00} : (flag_sine ? reg_sine_first : reg_shape);
        reg_second_a <= flag_custom ? {wire_second_a,2'b00} : (flag_sine ? reg_sine_second : reg_shape);
        // 单帧/B未写入时明确复用A，不能用零权重乘未知B样点。
        reg_first_b <= flag_two ? {wire_first_b,2'b00} : (flag_custom ? {wire_first_a,2'b00} : (flag_sine ? reg_sine_first : reg_shape));
        reg_second_b <= flag_two ? {wire_second_b,2'b00} : (flag_custom ? {wire_second_a,2'b00} : (flag_sine ? reg_sine_second : reg_shape));
        reg_selected_phase <= reg_phase_fraction;
        reg_selected_frame <= flag_two ? reg_frame_fraction : 16'd0;
    end
    WavetableMorph Morph_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_valid(1'b1),
        .i_first_a(reg_first_a),.i_second_a(reg_second_a),.i_first_b(reg_first_b),.i_second_b(reg_second_b),
        .i_phase_fraction(reg_selected_phase),.i_frame_fraction(reg_selected_frame),.o_valid(),.o_sample(o_sample));
endmodule
