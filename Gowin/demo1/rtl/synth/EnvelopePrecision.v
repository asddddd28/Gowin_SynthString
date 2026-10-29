`timescale 1ns / 1ps
////////////////////////////////////English///////////////////////////////////////
// Company:         Tang Synth project
// Engineer:        Codex
// Create Date:     2026/10/11 12:00:00
// Design Name:     Tang Synth precision envelope
// Module Name:     EnvelopePrecision
// Description:     spec/synth/EnvelopePrecision_spec.md
// Simulations:     sim/tb_precision.v
// Referrences:     docs/precision_protocol.md
// Dependencies:    None
// Version:         V1.0
// Revision Date:   2026/10/11 12:00:00
// History:         2026/10/11 V1.0 Codex Fractional ADSR with legacy steps
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Tang Synth 项目
// 开发人员:        Codex
// 创建日期:        2026年10月11日
// 设计名称:        分数步长包络
// 模块名称:        EnvelopePrecision
// 模块说明:        spec/synth/EnvelopePrecision_spec.md
// 仿真工程:        sim/tb_precision.v
// 参考资料:        docs/precision_protocol.md
// 依赖文件:        无外部模块
// 当前版本:        V1.0
// 修订日期:        2026年10月11日
// 修订历史:        2026年10月11日 V1.0 Codex 新增兼容整数步长的分数包络
module EnvelopePrecision (
    input         i_clk, // 在调用者已有的波形等待拍解码步长
    input         i_rstn, // 低有效复位，清除尚未解码的速度
    input         i_precise, // 一表示采用紧凑分数步长，零表示旧整数步长
    input  [2:0]  i_stage, // 当前包络阶段，零为空闲
    input  [31:0] i_level, // Q18.14 幅度，低十四位保存跨采样余数
    input  [17:0] i_attack, // 起音步长，新编码仅使用低十六位
    input  [17:0] i_decay, // 衰减段下降速度
    input  [17:0] i_sustain, // 保持段目标，仍使用旧十八位幅度单位
    input  [17:0] i_release, // 以满幅为参考的释放速度
    output [2:0]  o_stage, // 饱和及归零后的下一阶段
    output [31:0] o_level // 下一采样的幅度和分数余量
);
//---------------配置参数区域---------------//
    localparam [31:0] C_PEAK = 32'hffffc000; // 十八位满幅乘以分数比例
    localparam [31:0] C_STEAL = 32'h08000000; // 偷音沿用最多三十二个采样的淡出步长
//---------------编码信号区域---------------//
    wire [17:0] enc_selected_step; // 根据正在执行的阶段选择一个步长解码
    wire [32:0] enc_fraction_step; // 十一位尾数左移五位指数，额外一位检测超满幅
    wire [31:0] enc_step; // 旧步长和新编码转换为相同的 Q18.14 单位
    reg [31:0] reg_step; // 切断变长移位至幅度加减比较的组合路径
    wire [31:0] enc_sustain; // 保持电平不引入参数量化变化
    wire [32:0] enc_attack_sum; // 上升运算保留进位，避免满幅回绕
    wire [32:0] enc_decay_limit; // 下降边界使用扩展加法
//---------------译码信号区域---------------//
    reg [2:0] dec_stage; // 组合逻辑输出的阶段选择结果
    reg [31:0] dec_level; // 带饱和的下一幅度状态
//-------------其他信号连线区域-------------//
    assign enc_selected_step = i_stage == 1 ? i_attack : (i_stage == 2 ? i_decay : i_release); // 释放及空闲共用释放字段
    assign enc_fraction_step = {22'd0, enc_selected_step[10:0]} << enc_selected_step[15:11]; // 所有合法指数由上传控制器限制到二十二
    assign enc_step = i_precise ? (enc_fraction_step > C_PEAK ? C_PEAK : enc_fraction_step[31:0]) : {enc_selected_step, 14'd0}; // 超满幅速度等价于一步完成
    assign enc_sustain = {i_sustain, 14'd0}; // 十八位保持幅度转换为完整状态
    assign enc_attack_sum = {1'b0, i_level} + {1'b0, reg_step}; // 扩展两侧确保进位不丢失
    assign enc_decay_limit = {1'b0, enc_sustain} + {1'b0, reg_step}; // 下一次下降触及保持值时结束衰减
//-------------输出信号连线区域-------------//
    assign o_stage = dec_stage; // 步长解码一拍后，由调用者捕获下一阶段
    assign o_level = dec_level; // 输入须从解码拍保持到调用者捕获输出
//-------------主要任务处理区域-------------//
    always @(posedge i_clk or negedge i_rstn) begin // LOAD 后的 WAVE 拍完成解码，MOD_ENV 再捕获运算结果
        if (!i_rstn) reg_step <= 0;
        else reg_step <= enc_step;
    end
    always @(*) begin // 每个分支均赋值，纯组合算术不保存隐藏状态
        dec_stage = i_stage;
        dec_level = i_level;
        case (i_stage)
            1: begin
                if (reg_step == 0 || enc_attack_sum >= {1'b0, C_PEAK}) begin
                    dec_level = C_PEAK;
                    dec_stage = 2;
                end else dec_level = enc_attack_sum[31:0];
            end
            2: begin
                if (reg_step == 0 || {1'b0, i_level} <= enc_decay_limit) begin
                    dec_level = enc_sustain;
                    dec_stage = 3;
                end else dec_level = i_level - reg_step;
            end
            3: dec_level = enc_sustain;
            4: begin
                if (reg_step == 0 || i_level <= reg_step) begin
                    dec_level = 0;
                    dec_stage = 0;
                end else dec_level = i_level - reg_step;
            end
            5: begin
                if (i_level <= C_STEAL) begin
                    dec_level = 0;
                    dec_stage = 0;
                end else dec_level = i_level - C_STEAL;
            end
            default: begin
                dec_level = 0;
                dec_stage = 0;
            end
        endcase
    end
endmodule
