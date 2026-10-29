`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/28 22:16:18
// Design Name:     AxisAdsr
// Module Name:     AxisAdsr
// Description:     description/AxisAdsr_Design.pdf
// Simulations:     testbench/vivado/2021.1/AxisAdsr
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
// 设计名称:        AxisAdsr
// 模块名称:        AxisAdsr
// 模块说明:        Description/AxisAdsr_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/AxisAdsr
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

module AxisAdsr #(
 parameter C_ADDR_WIDTH = 6 // 信用池地址宽度，2至256个任务槽
)(
 input i_axis_aclk, // 与下游同域的计算时钟
 input i_axis_arstn, // 同时清除算术流水和所有旧任务资格
 input [111:0] i_s_axis_tdata, // 本次计算的参数及历史状态快照
 input [20:0] i_s_axis_tuser, // 不依赖声部固定绑定的调用者票据
 input i_s_axis_tvalid, // 源端持有完整任务直到接纳
 output o_s_axis_tready, // 可以锁存任务并预留返回位置
 output [63:0] o_m_axis_tdata, // 数值结果和必要的新状态
 output [20:0] o_m_axis_tuser, // 与返回对应的原请求票据
 output o_m_axis_tvalid, // 最早未消费任务已经计算完成
 input i_m_axis_tready // 结果提交端愿意接收队首
);
 wire [111:0] wire_snapshot; // 仅在核心发射沿采样的操作字段
 wire flag_launch; // 返回空间已预留的发射脉冲

 reg flag_busy; // 旧核心解码期间不能覆盖正在使用的输入快照
 reg [1:0] flag_pipeline; // 锁存沿和解码沿之后才允许读取组合结果
 reg [31:0] reg_level; // 当前包络完整Q18.14状态
 reg [2:0] reg_stage; // 应用本次门控事件后的阶段
 reg [72:0] reg_parameters; // precise及ADSR参数始终保持到返回采样
 reg flag_error; // 非法阶段被旧核心归零，但必须向调用者报告
 wire flag_adapter_ready; // 信用池是否能够容纳另一个任务
 wire flag_source_valid; // 参数锁存器空闲时才对适配器宣告任务
 wire [1:0] wire_event; // 零保持、一重触发、二释音、三偷音
 wire [2:0] wire_stage; // 根据事件选择本采样所处阶段
 wire [31:0] wire_level; // 旧核心已解码步长对应的下一幅度
 wire [2:0] wire_next_stage; // 与下一幅度一同交付的阶段
 wire [63:0] wire_result; // 完整状态、错误及可直接用作VCA的18位音量
 wire [17:0] enc_attack; // 大指数在进入旧33位解码器前归一到饱和步长
 wire [17:0] enc_decay; // 衰减的编码保护避免左移溢出后变慢
 wire [17:0] enc_release; // 释放参数也采用同样的满幅饱和语义
 wire [42:0] wire_attack_step; // 完整容纳最大五位指数展开
 wire [42:0] wire_decay_step; // 饱和判断在截断之前完成
 wire [42:0] wire_release_step; // 小尾数大指数也保留正确数值
 assign wire_attack_step = {32'd0,wire_snapshot[46:36]} << wire_snapshot[51:47];
 assign wire_decay_step = {32'd0,wire_snapshot[64:54]} << wire_snapshot[69:65];
 assign wire_release_step = {32'd0,wire_snapshot[100:90]} << wire_snapshot[105:101];
 assign enc_attack = (wire_snapshot[35] && wire_attack_step > 43'd4294950912) ? 18'h0b7ff : wire_snapshot[53:36];
 assign enc_decay = (wire_snapshot[35] && wire_decay_step > 43'd4294950912) ? 18'h0b7ff : wire_snapshot[71:54];
 assign enc_release = (wire_snapshot[35] && wire_release_step > 43'd4294950912) ? 18'h0b7ff : wire_snapshot[107:90];
 assign flag_source_valid = i_s_axis_tvalid && !flag_busy; // 未完成事务期间源端保持原包
 assign o_s_axis_tready = flag_adapter_ready && !flag_busy; // 空锁存器及空返回槽同时成立
 assign wire_event = wire_snapshot[109:108]; // 事件只在发射沿影响这一份状态
 assign wire_stage = wire_event == 2'd1 ? 3'd1 : ((wire_event == 2'd2 && wire_snapshot[34:32] != 3'd0) ? 3'd4 : ((wire_event == 2'd3 && wire_snapshot[34:32] != 3'd0) ? 3'd5 : wire_snapshot[34:32]));
 assign wire_result = {10'd0,wire_level[31:14],flag_error,wire_next_stage,wire_level}; // 高精度反馈与音量视图来自同一结果

 // 返回适配器保护不可停顿核心，保留整包身份直到消费。
 AxisFixedCore #(.C_INPUT_WIDTH(112),.C_OUTPUT_WIDTH(64),.C_USER_WIDTH(21),.C_ADDR_WIDTH(C_ADDR_WIDTH)) AxisFixedCore_Inst (
  .i_axis_aclk(i_axis_aclk), .i_axis_arstn(i_axis_arstn),
  .i_s_axis_tdata(i_s_axis_tdata), .i_s_axis_tuser(i_s_axis_tuser), .i_s_axis_tvalid(flag_source_valid), .o_s_axis_tready(flag_adapter_ready),
  .o_m_axis_tdata(o_m_axis_tdata), .o_m_axis_tuser(o_m_axis_tuser), .o_m_axis_tvalid(o_m_axis_tvalid), .i_m_axis_tready(i_m_axis_tready),
  .o_core_valid(flag_launch), .o_core_data(wire_snapshot), .i_core_valid(flag_pipeline[1]), .i_core_data(wire_result)
 );

 // 同一个物理包络核心依次服务不同状态实例，II为三个时钟。
 always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
  if(!i_axis_arstn) begin
   flag_busy <= 1'b0; flag_pipeline <= 2'd0; reg_level <= 32'd0;
   reg_stage <= 3'd0; reg_parameters <= 73'd0; flag_error <= 1'b0;
  end else begin
   flag_pipeline <= {flag_pipeline[0],flag_launch};
   if(flag_launch) begin
    flag_busy <= 1'b1; reg_level <= wire_event == 2'd1 ? 32'd0 : wire_snapshot[31:0];
    reg_stage <= wire_stage; reg_parameters <= {enc_release,wire_snapshot[89:72],enc_decay,enc_attack,wire_snapshot[35]}; flag_error <= wire_stage > 3'd5;
   end else if(flag_pipeline[1]) flag_busy <= 1'b0;
  end
 end
 // 参数先锁存，下一沿解码，再下一沿由信用池捕获完整结果。
 EnvelopePrecision EnvelopePrecision_Inst (
  .i_clk(i_axis_aclk),.i_rstn(i_axis_arstn),.i_precise(reg_parameters[0]),.i_stage(reg_stage),.i_level(reg_level),
  .i_attack(reg_parameters[18:1]),.i_decay(reg_parameters[36:19]),.i_sustain(reg_parameters[54:37]),.i_release(reg_parameters[72:55]),
  .o_stage(wire_next_stage),.o_level(wire_level)
 );

endmodule
