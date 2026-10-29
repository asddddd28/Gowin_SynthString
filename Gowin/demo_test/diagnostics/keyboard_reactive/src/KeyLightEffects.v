`timescale 1ns / 1ps
// Four effects, frame snapshots, and deterministic newest-key interruption.
// 单键计时独立；涟漪、扫光与十字共享一个可被新按键打断的中心事件。
module KeyLightEffects(
 input i_clk,input i_rstn,input [31:0] i_press,input i_clear,
 input [3:0] i_mode,input i_direction,input i_frame_tick,input [4:0] i_pixel,
 output [23:0] o_grb
);
reg [5:0] mem_timer[0:31],mem_snapshot[0:31];
reg [5:0] reg_age,reg_age_snapshot;
reg [4:0] reg_origin,reg_origin_snapshot;
reg [7:0] reg_hue,reg_hue_snapshot;
reg [3:0] reg_mode_snapshot;
reg flag_direction_snapshot;
integer key_index;
integer enc_row,enc_col,enc_origin_row,enc_origin_col;
integer enc_row_distance,enc_col_distance,enc_distance,enc_radius,enc_position,enc_weight;
integer enc_phase,enc_ramp,enc_red,enc_green,enc_blue;
reg [23:0] reg_grb_o;
assign o_grb=reg_grb_o;
always @(posedge i_clk or negedge i_rstn)begin
 if(!i_rstn)begin
  for(key_index=0;key_index<32;key_index=key_index+1)begin mem_timer[key_index]<=0;mem_snapshot[key_index]<=0; end
  reg_age<=63;reg_age_snapshot<=63;reg_origin<=0;reg_origin_snapshot<=0;
  reg_hue<=0;reg_hue_snapshot<=0;reg_mode_snapshot<=0;flag_direction_snapshot<=0;
 end else begin
  if(i_frame_tick)begin
   reg_age_snapshot<=reg_age;reg_origin_snapshot<=reg_origin;reg_hue_snapshot<=reg_hue;
   reg_mode_snapshot<=i_mode;flag_direction_snapshot<=i_direction;
   if(reg_age<63)begin reg_age<=reg_age+1'b1; end
   for(key_index=0;key_index<32;key_index=key_index+1)begin
    mem_snapshot[key_index]<=mem_timer[key_index];
    if(mem_timer[key_index]!=0)begin mem_timer[key_index]<=mem_timer[key_index]-1'b1; end
   end
  end
  for(key_index=0;key_index<32;key_index=key_index+1)begin
   if(i_press[key_index])begin
    mem_timer[key_index]<=50;reg_age<=0;reg_origin<=key_index;
    reg_hue<=reg_hue>=160 ? 0 : reg_hue+8'd32;
   end
  end
  if(i_clear)begin
   for(key_index=0;key_index<32;key_index=key_index+1)begin mem_timer[key_index]<=0;mem_snapshot[key_index]<=0; end
   reg_age<=63;reg_age_snapshot<=63;
  end
 end
end
// 从固定帧快照计算一颗灯，整个发送帧内不受新按键改变。
always @(*)begin
 enc_row=i_pixel/8;enc_col=i_pixel%8;
 enc_origin_row=reg_origin_snapshot/8;enc_origin_col=reg_origin_snapshot%8;
 enc_row_distance=enc_row>=enc_origin_row ? enc_row-enc_origin_row : enc_origin_row-enc_row;
 enc_col_distance=enc_col>=enc_origin_col ? enc_col-enc_origin_col : enc_origin_col-enc_col;
 enc_distance=enc_row_distance+enc_col_distance;
 enc_radius=reg_age_snapshot/3;
 enc_position=reg_age_snapshot/2;
 enc_weight=0;
 case(reg_mode_snapshot)
  1:begin if(mem_snapshot[i_pixel]!=0)begin enc_weight=32; end end
  2,4:begin
   if(reg_age_snapshot<36 && (reg_mode_snapshot==2 || enc_row_distance==0 || enc_col_distance==0))begin
    if(enc_distance==enc_radius)begin enc_weight=32; end
    else if(enc_distance+1==enc_radius)begin enc_weight=12; end
   end
  end
  3:begin
   if(flag_direction_snapshot)begin enc_distance=enc_position-enc_row; end
   else begin enc_distance=enc_position-enc_col; end
   if(reg_age_snapshot < (flag_direction_snapshot ? 14 : 22))begin
    case(enc_distance)
     0:enc_weight=32;1:enc_weight=16;2:enc_weight=4;default:enc_weight=0;
    endcase
   end
  end
  default:begin enc_weight=0; end
 endcase
 enc_phase=reg_mode_snapshot==1 ? i_pixel*5 : (reg_hue_snapshot+reg_age_snapshot*4)%256;
 if(enc_phase>=192)begin enc_phase=enc_phase-192; end
 enc_ramp=enc_phase%32;
 enc_red=0;enc_green=0;enc_blue=0;
 case(enc_phase/32)
  0:begin enc_red=32;enc_green=enc_ramp; end
  1:begin enc_red=32-enc_ramp;enc_green=32; end
  2:begin enc_green=32;enc_blue=enc_ramp; end
  3:begin enc_green=32-enc_ramp;enc_blue=32; end
  4:begin enc_red=enc_ramp;enc_blue=32; end
  default:begin enc_red=32;enc_blue=32-enc_ramp; end
 endcase
 enc_red=enc_red*enc_weight/32;enc_green=enc_green*enc_weight/32;enc_blue=enc_blue*enc_weight/32;
 reg_grb_o={enc_green[7:0],enc_red[7:0],enc_blue[7:0]};
end
endmodule
