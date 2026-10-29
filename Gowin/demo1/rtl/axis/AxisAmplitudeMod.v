`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/28 22:16:18
// Design Name:     AxisAmplitudeMod
// Module Name:     AxisAmplitudeMod
// Description:     description/AxisAmplitudeMod_Design.pdf
// Simulations:     testbench/vivado/2021.1/AxisAmplitudeMod
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
// 设计名称:        AxisAmplitudeMod
// 模块名称:        AxisAmplitudeMod
// 模块说明:        Description/AxisAmplitudeMod_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/AxisAmplitudeMod
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

module AxisAmplitudeMod #(
 parameter C_ADDR_WIDTH = 6 // 信用池地址宽度，2至256个任务槽
)(
 input i_axis_aclk, // 与下游同域的计算时钟
 input i_axis_arstn, // 同时清除算术流水和所有旧任务资格
 input [103:0] i_s_axis_tdata, // 本次计算的参数及历史状态快照
 input [20:0] i_s_axis_tuser, // 不依赖声部固定绑定的调用者票据
 input i_s_axis_tvalid, // 源端持有完整任务直到接纳
 output o_s_axis_tready, // 可以锁存任务并预留返回位置
 output [63:0] o_m_axis_tdata, // 数值结果和必要的新状态
 output [20:0] o_m_axis_tuser, // 与返回对应的原请求票据
 output o_m_axis_tvalid, // 最早未消费任务已经计算完成
 input i_m_axis_tready // 结果提交端愿意接收队首
);
 wire [103:0] wire_snapshot; // 仅在核心发射沿采样的操作字段
 wire flag_launch; // 返回空间已预留的发射脉冲

 reg [4:0] flag_pipeline; // 五个算术采样沿的有效资格
 reg signed [31:0] reg_modulator; // 限定在正负单位幅度内的调制源
 reg signed [32:0] reg_depth; // 深度正号扩展后进入乘法
 reg signed [64:0] reg_mod_product; // 深度乘调制源保留完整精度
 reg signed [31:0] reg_factor; // AM或环形交叉渐变的Q26增益
 reg signed [63:0] reg_audio_product; // 载波乘增益的有符号完整乘积
 reg [35:0] reg_context; // 参数钳位、非法模式、模式及载波
 reg [35:0] reg_context_wait; // 上下文对齐调制乘积
 reg [33:0] reg_carrier_wait; // 两个状态位与载波对齐增益
 reg [1:0] reg_status; // 参数状态继续对齐最终乘积
 reg [31:0] reg_depth_wait; // 基础深度与调制乘积共同进入增益公式
 reg [63:0] reg_result; // 饱和后的音频和诊断状态
 wire signed [31:0] wire_modulator; // 当前输入的有符号调制音频
 wire signed [31:0] wire_carrier; // 与增益同行的载波
 wire signed [64:0] wire_mod_scaled; // 去除调制乘积的二十六位小数
 wire signed [64:0] wire_distance; // 深度与调制量之差，最大二倍单位幅度
 wire signed [63:0] wire_audio_scaled; // 输出量纲回到Q26后的宽样值
 assign wire_modulator = wire_snapshot[63:32];
 assign wire_carrier = reg_carrier_wait[31:0];
 assign wire_mod_scaled = reg_mod_product >>> 26;
 assign wire_distance = $signed({1'b0,reg_depth_wait}) - wire_mod_scaled;
 assign wire_audio_scaled = reg_audio_product >>> 26;

 // 返回适配器保护不可停顿核心，保留整包身份直到消费。
 AxisFixedCore #(.C_INPUT_WIDTH(104),.C_OUTPUT_WIDTH(64),.C_USER_WIDTH(21),.C_ADDR_WIDTH(C_ADDR_WIDTH)) AxisFixedCore_Inst (
  .i_axis_aclk(i_axis_aclk), .i_axis_arstn(i_axis_arstn),
  .i_s_axis_tdata(i_s_axis_tdata), .i_s_axis_tuser(i_s_axis_tuser), .i_s_axis_tvalid(i_s_axis_tvalid), .o_s_axis_tready(o_s_axis_tready),
  .o_m_axis_tdata(o_m_axis_tdata), .o_m_axis_tuser(o_m_axis_tuser), .o_m_axis_tvalid(o_m_axis_tvalid), .i_m_axis_tready(i_m_axis_tready),
  .o_core_valid(flag_launch), .o_core_data(wire_snapshot), .i_core_valid(flag_pipeline[4]), .i_core_data(reg_result)
 );

 // 参数限幅、调制乘法、增益、载波乘法及输出饱和分别寄存。
 always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
  if(!i_axis_arstn) begin
   flag_pipeline <= 5'd0; reg_modulator <= 32'd0; reg_depth <= 33'd0; reg_mod_product <= 65'd0;
   reg_factor <= 32'd0; reg_audio_product <= 64'd0; reg_context <= 36'd0; reg_context_wait <= 36'd0;
   reg_carrier_wait <= 34'd0; reg_status <= 2'd0; reg_depth_wait <= 32'd0; reg_result <= 64'd0;
  end else begin
   flag_pipeline <= {flag_pipeline[3:0],flag_launch};
   reg_modulator <= wire_modulator > 32'sd67108864 ? 32'sd67108864 : (wire_modulator < -32'sd67108864 ? -32'sd67108864 : wire_modulator);
   reg_depth <= wire_snapshot[95:64] > 32'd67108864 ? 33'd67108864 : {1'b0,wire_snapshot[95:64]};
   reg_context <= {(wire_modulator > 32'sd67108864 || wire_modulator < -32'sd67108864 || wire_snapshot[95:64] > 32'd67108864),(wire_snapshot[97:96] == 2'd3),wire_snapshot[97:96],wire_snapshot[31:0]};
   reg_mod_product <= reg_depth * reg_modulator;
   reg_depth_wait <= reg_depth[31:0]; reg_context_wait <= reg_context;
   case(reg_context_wait[33:32])
    2'd1: reg_factor <= 65'sd67108864 - (wire_distance >>> 1);
    2'd2: reg_factor <= 65'sd67108864 - wire_distance;
    default: reg_factor <= 32'sd67108864;
   endcase
   reg_carrier_wait <= {reg_context_wait[35:34],reg_context_wait[31:0]};
   reg_audio_product <= wire_carrier * reg_factor;
   reg_status <= reg_carrier_wait[33:32];
   if(wire_audio_scaled > 64'sd2147483647) reg_result <= {29'd0,reg_status[0],reg_status[1],1'b1,32'h7fffffff};
   else if(wire_audio_scaled < -64'sd2147483648) reg_result <= {29'd0,reg_status[0],reg_status[1],1'b1,32'h80000000};
   else reg_result <= {29'd0,reg_status[0],reg_status[1],1'b0,wire_audio_scaled[31:0]};
  end
 end

endmodule
