`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/12 00:11:00
// Design Name:     WavetablePairCache
// Module Name:     WavetablePairCache
// Description:     description/WavetablePairCache_Design.pdf
// Simulations:     testbench/vivado/2021.1/WavetablePairCache
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
// 设计名称:        WavetablePairCache
// 模块名称:        WavetablePairCache
// 模块说明:        Description/WavetablePairCache_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/WavetablePairCache
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

module WavetablePairCache(
    input i_clk, // 缓存时钟
    input i_rstn, // 奇偶标志的低有效复位
    input i_write, // 写入一个上传样点
    input [10:0] i_address, // 银行和周期内索引
    input i_frame, // 前帧或后帧
    input [15:0] i_data, // 有符号十六位载荷
    input [31:0] i_phase, // 四邻点共同相位
    input i_bank, // 读请求的银行
    output signed [15:0] o_first_a, // 前帧起点
    output signed [15:0] o_second_a, // 前帧周期邻点
    output signed [15:0] o_first_b, // 后帧同相位起点
    output signed [15:0] o_second_b // 后帧同相位邻点
);
    reg signed [15:0] reg_even_a [0:1023]; // 前帧两个银行的偶样点
    reg signed [15:0] reg_odd_a [0:1023]; // 前帧两个银行的奇样点
    reg signed [15:0] reg_even_b [0:1023]; // 后帧两个银行的偶样点
    reg signed [15:0] reg_odd_b [0:1023]; // 后帧两个银行的奇样点
    reg signed [15:0] reg_read_even_a; // 前帧偶口同步读数
    reg signed [15:0] reg_read_odd_a; // 前帧奇口同步读数
    reg signed [15:0] reg_read_even_b; // 后帧偶口同步读数
    reg signed [15:0] reg_read_odd_b; // 后帧奇口同步读数
    reg flag_odd = 1'b0; // 与四个 RAM 读数对齐的相位奇偶
    wire [8:0] enc_even_index; // 奇起点取下一个偶点，九位自然回绕
    wire signed [15:0] first_a_o; // 前帧周期起点
    wire signed [15:0] second_a_o; // 前帧周期邻点
    wire signed [15:0] first_b_o; // 后帧周期起点
    wire signed [15:0] second_b_o; // 后帧周期邻点
    assign enc_even_index = i_phase[31:23] + {8'd0,i_phase[22]}; // 末点的偶邻点回到本银行
    assign first_a_o = flag_odd ? reg_read_odd_a : reg_read_even_a; // 恢复前帧逻辑顺序
    assign second_a_o = flag_odd ? reg_read_even_a : reg_read_odd_a; // 前帧另一邻点
    assign first_b_o = flag_odd ? reg_read_odd_b : reg_read_even_b; // 后帧同相位起点
    assign second_b_o = flag_odd ? reg_read_even_b : reg_read_odd_b; // 后帧对应邻点
    assign o_first_a = first_a_o; // 输出前帧起点
    assign o_second_a = second_a_o; // 输出前帧邻点
    assign o_first_b = first_b_o; // 输出后帧起点
    assign o_second_b = second_b_o; // 输出后帧邻点
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) flag_odd <= 1'b0; // 复位选择标志，RAM 内容不清除
        else flag_odd <= i_phase[22]; // 同拍跟随四路读请求
    end
    // 每个数组仅一个写口和一个同步读口；不复位 RAM 及 RAM 输出寄存器。
    always @(posedge i_clk) begin
        if(i_write && !i_frame && !i_address[0]) reg_even_a[i_address[10:1]] <= i_data; // 上传前帧偶点
        reg_read_even_a <= reg_even_a[{i_bank,enc_even_index}]; // 前帧偶邻点
    end
    always @(posedge i_clk) begin
        if(i_write && !i_frame && i_address[0]) reg_odd_a[i_address[10:1]] <= i_data; // 上传前帧奇点
        reg_read_odd_a <= reg_odd_a[{i_bank,i_phase[31:23]}]; // 前帧奇邻点
    end
    always @(posedge i_clk) begin
        if(i_write && i_frame && !i_address[0]) reg_even_b[i_address[10:1]] <= i_data; // 上传后帧偶点
        reg_read_even_b <= reg_even_b[{i_bank,enc_even_index}]; // 后帧偶邻点
    end
    always @(posedge i_clk) begin
        if(i_write && i_frame && i_address[0]) reg_odd_b[i_address[10:1]] <= i_data; // 上传后帧奇点
        reg_read_odd_b <= reg_odd_b[{i_bank,i_phase[31:23]}]; // 后帧奇邻点
    end
endmodule
