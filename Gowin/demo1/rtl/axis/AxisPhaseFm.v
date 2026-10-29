`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/28 22:16:18
// Design Name:     AxisPhaseFm
// Module Name:     AxisPhaseFm
// Description:     description/AxisPhaseFm_Design.pdf
// Simulations:     testbench/vivado/2021.1/AxisPhaseFm
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
// 设计名称:        AxisPhaseFm
// 模块名称:        AxisPhaseFm
// 模块说明:        Description/AxisPhaseFm_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/AxisPhaseFm
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

module AxisPhaseFm #(
 parameter C_ADDR_WIDTH = 6 // 信用池地址宽度，2至256个任务槽
)(
 input i_axis_aclk, // 与下游同域的计算时钟
 input i_axis_arstn, // 同时清除算术流水和所有旧任务资格
 input [127:0] i_s_axis_tdata, // 本次计算的参数及历史状态快照
 input [20:0] i_s_axis_tuser, // 不依赖声部固定绑定的调用者票据
 input i_s_axis_tvalid, // 源端持有完整任务直到接纳
 output o_s_axis_tready, // 可以锁存任务并预留返回位置
 output [31:0] o_m_axis_tdata, // 数值结果和必要的新状态
 output [20:0] o_m_axis_tuser, // 与返回对应的原请求票据
 output o_m_axis_tvalid, // 最早未消费任务已经计算完成
 input i_m_axis_tready // 结果提交端愿意接收队首
);
 wire [127:0] wire_snapshot; // 仅在核心发射沿采样的操作字段
 wire flag_launch; // 返回空间已预留的发射脉冲

 reg [2:0] flag_pipeline; // 三个算术沿的同行有效资格
 reg signed [63:0] reg_product; // 调制幅度与有符号频偏的全宽积
 reg signed [63:0] reg_delta; // 移除Q26小数后的有符号相位增量
 reg [63:0] reg_base; // 基础增量及旧相位在乘法沿锁存
 reg [63:0] reg_base_wait; // 基础状态对齐量化后的频偏
 reg [31:0] reg_result; // 模二的三十二次方相位新状态
 wire signed [31:0] wire_modulator; // 调制音频以有符号Q26解释
 wire signed [31:0] wire_depth; // 频偏单位是每采样相位累加字
 assign wire_modulator = wire_snapshot[95:64]; // 不把负半周解释为巨大正数
 assign wire_depth = wire_snapshot[127:96]; // 允许负深度反转调制极性

 // 返回适配器保护不可停顿核心，保留整包身份直到消费。
 AxisFixedCore #(.C_INPUT_WIDTH(128),.C_OUTPUT_WIDTH(32),.C_USER_WIDTH(21),.C_ADDR_WIDTH(C_ADDR_WIDTH)) AxisFixedCore_Inst (
  .i_axis_aclk(i_axis_aclk), .i_axis_arstn(i_axis_arstn),
  .i_s_axis_tdata(i_s_axis_tdata), .i_s_axis_tuser(i_s_axis_tuser), .i_s_axis_tvalid(i_s_axis_tvalid), .o_s_axis_tready(o_s_axis_tready),
  .o_m_axis_tdata(o_m_axis_tdata), .o_m_axis_tuser(o_m_axis_tuser), .o_m_axis_tvalid(o_m_axis_tvalid), .i_m_axis_tready(i_m_axis_tready),
  .o_core_valid(flag_launch), .o_core_data(wire_snapshot), .i_core_valid(flag_pipeline[2]), .i_core_data(reg_result)
 );

 // 积分前先完整乘法和算术缩放，最后只保留相位模数低位。
 always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
  if(!i_axis_arstn) begin
   flag_pipeline <= 3'd0; reg_product <= 64'd0; reg_delta <= 64'd0;
   reg_base <= 64'd0; reg_base_wait <= 64'd0; reg_result <= 32'd0;
  end else begin
   flag_pipeline <= {flag_pipeline[1:0],flag_launch};
   reg_product <= wire_modulator * wire_depth;
   reg_base <= wire_snapshot[63:0];
   reg_delta <= reg_product >>> 26;
   reg_base_wait <= reg_base;
   reg_result <= reg_base_wait[31:0] + reg_base_wait[63:32] + reg_delta[31:0];
  end
 end

endmodule
