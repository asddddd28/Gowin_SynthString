`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/28 22:16:18
// Design Name:     AxisWaveSample
// Module Name:     AxisWaveSample
// Description:     description/AxisWaveSample_Design.pdf
// Simulations:     testbench/vivado/2021.1/AxisWaveSample
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/28 22:16:18
// History:
// Time             Version     Revised by        Contents
// 2026/10/28       V1.0        Codex              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月28日
// 设计名称:        AxisWaveSample
// 模块名称:        AxisWaveSample
// 模块说明:        Description/AxisWaveSample_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/AxisWaveSample
//
// 参考资料:        None
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年10月28日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月28日   V1.0        Codex              创建文件

module AxisWaveSample #(
 parameter C_ADDR_WIDTH = 6 // 信用池地址宽度，2至256个任务槽
)(
 input i_axis_aclk, // 与下游同域的计算时钟
 input i_axis_arstn, // 同时清除算术流水和所有旧任务资格
 input [159:0] i_s_axis_tdata, // 本次计算的参数及历史状态快照
 input [20:0] i_s_axis_tuser, // 不依赖声部固定绑定的调用者票据
 input i_s_axis_tvalid, // 源端持有完整任务直到接纳
 output o_s_axis_tready, // 可以锁存任务并预留返回位置
 output [31:0] o_m_axis_tdata, // 数值结果和必要的新状态
 output [20:0] o_m_axis_tuser, // 与返回对应的原请求票据
 output o_m_axis_tvalid, // 最早未消费任务已经计算完成
 input i_m_axis_tready // 结果提交端愿意接收队首
);
 wire [159:0] wire_snapshot; // 仅在核心发射沿采样的操作字段
 wire flag_launch; // 返回空间已预留的发射脉冲

 reg [99:0] reg_endpoints; // 同一请求的两个16位点对及正弦18位点对
 wire flag_wave_return; // 旧波表核心第八采样沿的结果资格
 wire signed [17:0] wire_wave; // 插值后的有符号Q17波形
 wire [31:0] wire_result; // 精确提升为后续滤波器的Q26输入
 assign wire_result = {{5{wire_wave[17]}},wire_wave,9'd0}; // 增加小数位不丢失样值精度

 // 返回适配器保护不可停顿核心，保留整包身份直到消费。
 AxisFixedCore #(.C_INPUT_WIDTH(160),.C_OUTPUT_WIDTH(32),.C_USER_WIDTH(21),.C_ADDR_WIDTH(C_ADDR_WIDTH)) AxisFixedCore_Inst (
  .i_axis_aclk(i_axis_aclk), .i_axis_arstn(i_axis_arstn),
  .i_s_axis_tdata(i_s_axis_tdata), .i_s_axis_tuser(i_s_axis_tuser), .i_s_axis_tvalid(i_s_axis_tvalid), .o_s_axis_tready(o_s_axis_tready),
  .o_m_axis_tdata(o_m_axis_tdata), .o_m_axis_tuser(o_m_axis_tuser), .o_m_axis_tvalid(o_m_axis_tvalid), .i_m_axis_tready(i_m_axis_tready),
  .o_core_valid(flag_launch), .o_core_data(wire_snapshot), .i_core_valid(flag_wave_return), .i_core_data(wire_result)
 );

 // 旧查询接口的邻点晚一沿，本适配器把同拍快照显式延迟对齐。
 always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
  if(!i_axis_arstn) reg_endpoints <= 100'd0;
  else reg_endpoints <= wire_snapshot[153:54];
 end
 // 波表存储在外部；这里复用源选择、相位插值和帧间插值算术。
 WavetablePairRead WavetablePairRead_Inst (
  .i_clk(i_axis_aclk),.i_rstn(i_axis_arstn),.i_valid(flag_launch),.i_query(wire_snapshot[53:0]),
  .i_pair_a(reg_endpoints[31:0]),.i_pair_b(reg_endpoints[63:32]),.i_sine_pair(reg_endpoints[99:64]),
  .o_valid(flag_wave_return),.o_sample(wire_wave)
 );

endmodule
