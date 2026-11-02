`timescale 1ns / 1ps
// 32-voice bounded sum; register input, final sum and scaling before saturation.
module KeyboardFrameMixer #(parameter C_MIX_SHIFT=5)(
 input i_clk,input i_rstn,input i_start,input i_valid,input [31:0] i_sample,input i_last,
 output o_pcm_valid,input i_pcm_ready,output [23:0] o_pcm_left,output [23:0] o_pcm_right
);
 reg signed [31:0] reg_input;
 reg signed [39:0] reg_sum,reg_final;
 reg signed [45:0] reg_scaled;
 reg flag_input,flag_last,flag_final,flag_scaled,flag_output;
 reg [23:0] reg_pcm;
 wire signed [39:0] enc_sum=reg_sum+{{8{reg_input[31]}},reg_input};
 assign o_pcm_valid=flag_output;assign o_pcm_left=reg_pcm;assign o_pcm_right=reg_pcm;
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin reg_input<=0;flag_input<=0;flag_last<=0;reg_sum<=0;reg_final<=0;flag_final<=0;reg_scaled<=0;flag_scaled<=0;flag_output<=0;reg_pcm<=0;end
  else begin
   flag_input<=i_valid;flag_final<=flag_input&&flag_last;flag_scaled<=flag_final;
   if(i_valid)begin reg_input<=i_sample;flag_last<=i_last;end
   if(i_start)reg_sum<=0;
   else if(flag_input)begin reg_sum<=enc_sum;if(flag_last)reg_final<=enc_sum;end
   if(flag_final)reg_scaled<=($signed({{6{reg_final[39]}},reg_final})>>>C_MIX_SHIFT)<<<6;
   if(flag_output&&i_pcm_ready)flag_output<=0;
   if(flag_scaled)begin
    flag_output<=1;
    if(reg_scaled>46'sd8388607)reg_pcm<=24'h7fffff;
    else if(reg_scaled< -46'sd8388608)reg_pcm<=24'h800000;
    else reg_pcm<=reg_scaled[23:0];
   end
  end
 end
endmodule
