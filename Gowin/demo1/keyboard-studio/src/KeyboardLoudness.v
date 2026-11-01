`timescale 1ns / 1ps
// Contract: spec/src/KeyboardLoudness_spec.md. Four-clock PCM output pipeline.
// The active envelope mask includes releases; no instantaneous held-key division.
module KeyboardLoudness(
 input i_clk,input i_rstn,input i_valid,input signed [23:0] i_sample,
 input [31:0] i_active,input [3:0] i_volume,
 output o_valid,output [23:0] o_sample,output [5:0] o_active_count,
 output [18:0] o_gain,output [23:0] o_input_peak,output [23:0] o_output_peak,output [31:0] o_clips
);
 reg [5:0] enc_count;
 reg [18:0] enc_norm,reg_gain,reg_target;
 reg [22:0] reg_target_product;
 reg [5:0] reg_count;
 reg [3:0] flag_valid;
 reg signed [43:0] reg_product;
 reg [43:0] reg_magnitude;
 reg [28:0] reg_rounded;
 reg flag_negative,flag_round_negative;
 reg [23:0] reg_sample,reg_input_peak,reg_output_peak;
 reg [31:0] cnt_clips;
 integer key_index;
 wire [23:0] enc_input_abs=i_sample[23] ? -i_sample : i_sample;
 wire [23:0] enc_output_abs=reg_sample[23] ? -reg_sample : reg_sample;
 assign o_valid=flag_valid[3];assign o_sample=reg_sample;assign o_gain=reg_gain;
 assign o_active_count=reg_count;assign o_clips=cnt_clips;
 assign o_input_peak=reg_input_peak;assign o_output_peak=reg_output_peak;
 always @(*)begin
  enc_count=0;
  for(key_index=0;key_index<32;key_index=key_index+1)enc_count=enc_count+i_active[key_index];
 end
 always @(*)begin
  case(reg_count)
   6'd0:enc_norm=19'd262144;
   6'd1:enc_norm=19'd262144;
   6'd2:enc_norm=19'd185363;
   6'd3:enc_norm=19'd151348;
   6'd4:enc_norm=19'd131072;
   6'd5:enc_norm=19'd117234;
   6'd6:enc_norm=19'd107019;
   6'd7:enc_norm=19'd99081;
   6'd8:enc_norm=19'd92681;
   6'd9:enc_norm=19'd87381;
   6'd10:enc_norm=19'd82897;
   6'd11:enc_norm=19'd79039;
   6'd12:enc_norm=19'd75674;
   6'd13:enc_norm=19'd72705;
   6'd14:enc_norm=19'd70060;
   6'd15:enc_norm=19'd67685;
   6'd16:enc_norm=19'd65536;
   6'd17:enc_norm=19'd63579;
   6'd18:enc_norm=19'd61787;
   6'd19:enc_norm=19'd60139;
   6'd20:enc_norm=19'd58617;
   6'd21:enc_norm=19'd57204;
   6'd22:enc_norm=19'd55889;
   6'd23:enc_norm=19'd54660;
   6'd24:enc_norm=19'd53509;
   6'd25:enc_norm=19'd52428;
   6'd26:enc_norm=19'd51410;
   6'd27:enc_norm=19'd50449;
   6'd28:enc_norm=19'd49540;
   6'd29:enc_norm=19'd48678;
   6'd30:enc_norm=19'd47860;
   6'd31:enc_norm=19'd47082;
   6'd32:enc_norm=19'd46340;
   default:enc_norm=19'd46340;
  endcase
 end
 // Parameter calculation is independent of the sample pipe and settles before PCM.
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin reg_count<=0;reg_target_product<=0;reg_target<=0;end
  else begin
   reg_count<=enc_count;
   reg_target_product<=enc_norm*(i_volume>8?4'd8:i_volume);
   reg_target<=reg_target_product>>3;
  end
 end
 // Gain falls with ~1.3 ms time constant and recovers with ~84 ms time constant.
 // Rounding up the step guarantees a final exact mute and avoids fixed-point stalls.
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)reg_gain<=0;
  else if(i_valid)begin
   if(reg_gain>reg_target)reg_gain<=reg_gain-((reg_gain-reg_target+19'd63)>>6);
   else if(reg_gain<reg_target)reg_gain<=reg_gain+((reg_target-reg_gain+19'd4095)>>12);
  end
 end
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin flag_valid<=0;reg_product<=0;reg_magnitude<=0;reg_rounded<=0;flag_negative<=0;flag_round_negative<=0;reg_sample<=0;cnt_clips<=0;end
  else begin
   flag_valid<={flag_valid[2:0],i_valid};
   if(i_valid)reg_product<=i_sample*$signed({1'b0,reg_gain});
   if(flag_valid[0])begin reg_magnitude<=reg_product[43]?-reg_product:reg_product;flag_negative<=reg_product[43];end
   if(flag_valid[1])begin reg_rounded<=(reg_magnitude+44'd32768)>>16;flag_round_negative<=flag_negative;end
   if(flag_valid[2])begin
    if(reg_rounded>29'h0700000)begin
     reg_sample<=flag_round_negative?-24'sh700000:24'sh700000;
     if(cnt_clips!=32'hffffffff)cnt_clips<=cnt_clips+1'b1;
    end else reg_sample<=flag_round_negative?-reg_rounded[23:0]:reg_rounded[23:0];
   end
  end
 end
 // Decaying peak holds are diagnostic sample peaks, not loudness/LUFS readings.
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin reg_input_peak<=0;reg_output_peak<=0;end
  else begin
   if(i_valid)begin
    if(enc_input_abs>reg_input_peak)reg_input_peak<=enc_input_abs;
    else reg_input_peak<=reg_input_peak-((reg_input_peak+24'd4095)>>12);
   end
   if(flag_valid[3])begin
    if(enc_output_abs>reg_output_peak)reg_output_peak<=enc_output_abs;
    else reg_output_peak<=reg_output_peak-((reg_output_peak+24'd4095)>>12);
   end
  end
 end
endmodule
