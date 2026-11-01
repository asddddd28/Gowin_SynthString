`timescale 1ns/1ps
// LatencyKeyThresholds: 两次完整扫描确认，按键状态仅由真实 ADC 样本更新。
// 合同和时序：../spec/LatencyKeyThresholds_spec.md。
module LatencyKeyThresholds(
 input i_clk, input i_rstn,
 input [4:0] i_key, input [11:0] i_raw, input i_valid,
 output o_candidate,output o_confirm,output o_cancel,
 output [31:0] o_pressed
);
 reg [24:0] mem_threshold[0:31]; // 下降方向、释放门限、按下门限。
 reg [31:0] reg_pressed_o,reg_qualify;
 wire [24:0] enc_threshold;
 wire flag_press_crossed,flag_release_crossed,flag_crossed;
 initial $readmemh("key_thresholds.hex",mem_threshold);
 assign enc_threshold=mem_threshold[i_key];
 assign flag_press_crossed=enc_threshold[24] ? i_raw<=enc_threshold[11:0] : i_raw>=enc_threshold[11:0];
 assign flag_release_crossed=enc_threshold[24] ? i_raw>=enc_threshold[23:12] : i_raw<=enc_threshold[23:12];
 assign flag_crossed=reg_pressed_o[i_key] ? flag_release_crossed : flag_press_crossed;
 assign o_pressed=reg_pressed_o;
 assign o_candidate=i_valid&&!reg_pressed_o[i_key]&&flag_crossed&&!reg_qualify[i_key];
 assign o_confirm=i_valid&&!reg_pressed_o[i_key]&&flag_crossed&&reg_qualify[i_key];
 assign o_cancel=i_valid&&!reg_pressed_o[i_key]&&!flag_crossed&&reg_qualify[i_key];
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn) begin reg_pressed_o<=0;reg_qualify<=0;end
  else if(i_valid) begin
   if(flag_crossed) begin
    if(reg_qualify[i_key]) begin reg_pressed_o[i_key]<=!reg_pressed_o[i_key];reg_qualify[i_key]<=0;end
    else reg_qualify[i_key]<=1;
   end else reg_qualify[i_key]<=0;
  end
 end
endmodule
