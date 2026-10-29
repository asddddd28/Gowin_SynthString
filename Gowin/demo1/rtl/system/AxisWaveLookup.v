`timescale 1ns/1ps
////////////////////////////////////English///////////////////////////////////////
// Company: Tang Synth project
// Engineer: Codex
// Create Date: 2026/10/28
// Design Name: AxisWaveLookup
// Module Name: AxisWaveLookup
// Description: spec/system/AxisWaveLookup_spec.md
// Simulations: sim/tb_axis_synth_system.v
// Referrences: docs/modular-pipeline/system.md
// Dependencies: sources-axis-system.f
// Version: V1.0
// Revision Date: 2026/10/28
// History: 2026/10/28 V1.0 Codex Create system interconnect.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属: Tang Synth 项目
// 开发人员: Codex
// 创建日期: 2026年10月28日
// 设计名称: AxisWaveLookup
// 模块名称: AxisWaveLookup
// 模块说明: spec/system/AxisWaveLookup_spec.md
// 仿真工程: sim/tb_axis_synth_system.v
// 参考资料: docs/modular-pipeline/system.md
// 依赖文件: sources-axis-system.f
// 当前版本: V1.0
// 修订日期: 2026年10月28日
// 修订历史: 2026年10月28日 V1.0 Codex 建立系统互联
module AxisWaveLookup (
 input i_clk, // 统一计算时钟
 input i_rstn, // 全系统低有效复位，释放须同步
 input i_valid, // 待读取的查询有效
 output o_ready, // 查询和返回寄存器有容量
 input [53:0] i_query, // 波形相位资源银行及帧比例
 input [20:0] i_user, // 与查询同行的事务身份
 output o_valid, // 完整波形任务已准备好
 input i_ready, // 波形计算器接收任务
 output [159:0] o_data, // 查询及同步读取的全部端点
 output [20:0] o_user, // 查询发射时保存的身份
 input i_write, // 安全空闲窗口内的波表写使能
 input i_frame, // 写入A或B帧
 input [10:0] i_address, // 银行及点地址
 input [15:0] i_data // 上传的波表采样
);

 reg flag_pending,flag_valid;
 reg [53:0] reg_query;
 reg [20:0] reg_user,user_o;
 reg [159:0] data_o;
 reg [17:0] reg_sine[0:1023]; // 固定正弦ROM，用户波表独立可写
 reg [17:0] reg_sine_first,reg_sine_next;
 wire [9:0] wire_neighbor;
 wire [15:0] wire_first_a,wire_next_a,wire_first_b,wire_next_b;
 wire flag_accept;
 initial $readmemb("rtl/synth/sine.mem",reg_sine);
 assign wire_neighbor=i_query[31:22]+10'd1;
 assign o_ready=!flag_pending&&(!flag_valid||i_ready);
 assign flag_accept=i_valid&&o_ready;
 assign o_valid=flag_valid;assign o_data=data_o;assign o_user=user_o;
 WavetablePairCache Cache_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_write(i_write),.i_frame(i_frame),.i_address(i_address),.i_data(i_data),.i_phase(i_query[31:0]),.i_bank(i_query[35]),.o_first_a(wire_first_a),.o_second_a(wire_next_a),.o_first_b(wire_first_b),.o_second_b(wire_next_b));
 always @(posedge i_clk) begin
  reg_sine_first<=reg_sine[i_query[31:22]];reg_sine_next<=reg_sine[wire_neighbor];
 end
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn) begin flag_pending<=0;flag_valid<=0;reg_query<=0;reg_user<=0;data_o<=0;user_o<=0;end
  else begin
   if(flag_valid&&i_ready) flag_valid<=0;
   flag_pending<=flag_accept;
   if(flag_accept) begin reg_query<=i_query;reg_user<=i_user;end
   if(flag_pending) begin
    data_o<={6'd0,reg_sine_first,reg_sine_next,wire_first_b,wire_next_b,wire_first_a,wire_next_a,reg_query};
    user_o<=reg_user;flag_valid<=1;
   end
  end
 end
endmodule
