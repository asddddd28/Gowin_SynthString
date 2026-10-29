`timescale 1ns / 1ps
// Atomic calibration banks and hysteretic key recognition.
// 备用区完整提交后切换；按下与释放都要求连续两次采样越过对应阈值。
module KeyController(
 input i_clk, input i_rstn,
 input [79:0] i_command, input i_command_valid, input i_crc_error,
 input [4:0] i_key, input [11:0] i_raw, input i_sample_valid,
 output o_ack, output [7:0] o_ack_seq, output [7:0] o_ack_result,
 output o_configured, output [7:0] o_generation,
 output [3:0] o_mode, output o_direction,
 output [31:0] o_pressed, output [31:0] o_press_pulse, output o_clear_effect,
 output o_game_start, output o_game_stop, output [1:0] o_game_type
);
reg [11:0] mem_rest[0:63],mem_bottom[0:63],mem_press[0:63],mem_release[0:63];
reg flag_active_bank,flag_staging,flag_configured_o;
reg [31:0] reg_mask,reg_pressed_o,reg_qualify,reg_press_pulse_o;
reg [7:0] reg_generation_o,reg_ack_seq_o,reg_ack_result_o;
reg [3:0] reg_mode_o;
reg flag_direction_o,flag_ack_o,flag_clear_o;
reg flag_cache;
reg flag_game_start_o,flag_game_stop_o;
reg [1:0] reg_game_type_o;
reg [79:0] reg_last_command;
reg [7:0] reg_last_result;
wire [5:0] enc_read_address,enc_write_address;
wire [11:0] enc_rest,enc_bottom,enc_press,enc_release;
wire flag_decreasing,flag_crossed,flag_range;
reg [7:0] enc_result;
assign enc_read_address={flag_active_bank,i_key};
assign enc_write_address={!flag_active_bank,i_command[60:56]};
assign enc_rest=i_command[55:44];assign enc_bottom=i_command[43:32];
assign enc_press=i_command[31:20];assign enc_release=i_command[19:8];
assign flag_decreasing=mem_bottom[enc_read_address]<mem_rest[enc_read_address];
assign flag_crossed=reg_pressed_o[i_key] ?
 (flag_decreasing ? i_raw>=mem_release[enc_read_address] : i_raw<=mem_release[enc_read_address]) :
 (flag_decreasing ? i_raw<=mem_press[enc_read_address] : i_raw>=mem_press[enc_read_address]);
assign flag_range=i_command[63:56]<32 &&
 ((enc_rest>enc_bottom && enc_rest-enc_bottom>=12'd100 && enc_bottom<=enc_press && enc_press<enc_release && enc_release<=enc_rest) ||
  (enc_bottom>enc_rest && enc_bottom-enc_rest>=12'd100 && enc_rest<=enc_release && enc_release<enc_press && enc_press<=enc_bottom));
assign o_ack=flag_ack_o;assign o_ack_seq=reg_ack_seq_o;assign o_ack_result=reg_ack_result_o;
assign o_configured=flag_configured_o;assign o_generation=reg_generation_o;
assign o_mode=reg_mode_o;assign o_direction=flag_direction_o;
assign o_pressed=reg_pressed_o;assign o_press_pulse=reg_press_pulse_o;assign o_clear_effect=flag_clear_o;
assign o_game_start=flag_game_start_o;assign o_game_stop=flag_game_stop_o;assign o_game_type=reg_game_type_o;
always @(*)begin
 enc_result=8'd0;
 case(i_command[71:64])
  8'h10:begin enc_result=0; end
  8'h11:begin
   if(!flag_staging)begin enc_result=2; end
   else if(!flag_range)begin enc_result=3; end
  end
  8'h12:begin if(!flag_staging || reg_mask!=32'hffffffff)begin enc_result=4; end end
  8'h20:begin if(i_command[7:4]>4 || i_command[3:0]>1)begin enc_result=3; end end
  8'h30:begin enc_result=0; end
  8'h41:begin
   if(!flag_configured_o)begin enc_result=2; end
   else if(i_command[63:56]<1 || i_command[63:56]>3)begin enc_result=3; end
  end
  8'h42:begin if(i_command[7:4]>4 || i_command[3:0]>1)begin enc_result=3; end end
  default:begin enc_result=6; end
 endcase
end
always @(posedge i_clk or negedge i_rstn)begin
 if(!i_rstn)begin
  flag_active_bank<=0;flag_staging<=0;flag_configured_o<=0;reg_mask<=0;
  reg_pressed_o<=0;reg_qualify<=0;reg_press_pulse_o<=0;reg_generation_o<=0;
  reg_mode_o<=1;flag_direction_o<=0;flag_ack_o<=0;flag_clear_o<=0;
  reg_ack_seq_o<=0;reg_ack_result_o<=0;flag_cache<=0;reg_last_command<=0;reg_last_result<=0;
  flag_game_start_o<=0;flag_game_stop_o<=0;reg_game_type_o<=0;
 end else begin
  flag_ack_o<=0;flag_clear_o<=0;reg_press_pulse_o<=0;
  flag_game_start_o<=0;flag_game_stop_o<=0;
  if(i_sample_valid && flag_configured_o)begin
   if(flag_crossed)begin
    if(reg_qualify[i_key])begin
     reg_pressed_o[i_key]<=!reg_pressed_o[i_key];reg_qualify[i_key]<=0;
     if(!reg_pressed_o[i_key])begin reg_press_pulse_o[i_key]<=1; end
    end else begin reg_qualify[i_key]<=1; end
   end else begin reg_qualify[i_key]<=0; end
  end
  if(i_command_valid)begin
   flag_ack_o<=1;reg_ack_seq_o<=i_command[79:72];
   if(i_crc_error)begin reg_ack_result_o<=1; end
   else if(flag_cache && i_command[79:72]==reg_last_command[79:72])begin
    if(i_command==reg_last_command)begin reg_ack_result_o<=reg_last_result; end
    else begin reg_ack_result_o<=7; end
   end else begin
    flag_cache<=1;reg_last_command<=i_command;reg_last_result<=enc_result;reg_ack_result_o<=enc_result;
    if(enc_result==0)begin
     case(i_command[71:64])
      8'h10:begin flag_staging<=1;reg_mask<=0; end
      8'h11:begin
       mem_rest[enc_write_address]<=enc_rest;mem_bottom[enc_write_address]<=enc_bottom;
       mem_press[enc_write_address]<=enc_press;mem_release[enc_write_address]<=enc_release;
       reg_mask[i_command[60:56]]<=1;
      end
      8'h12:begin
       flag_active_bank<=!flag_active_bank;flag_staging<=0;flag_configured_o<=1;
       reg_generation_o<=reg_generation_o+1'b1;reg_pressed_o<=0;reg_qualify<=0;
       reg_press_pulse_o<=0;flag_clear_o<=1;
       flag_game_stop_o<=1;
       if(reg_mode_o==5)begin reg_mode_o<=0; end
      end
      8'h20:begin
       reg_mode_o<=i_command[7:4];flag_direction_o<=i_command[0];flag_clear_o<=1;
       flag_game_stop_o<=1;
      end
      8'h41:begin
       reg_mode_o<=5;flag_direction_o<=0;flag_clear_o<=1;
       reg_game_type_o<=i_command[57:56];flag_game_start_o<=1;
      end
      8'h42:begin
       reg_mode_o<=i_command[7:4];flag_direction_o<=i_command[0];flag_clear_o<=1;
       flag_game_stop_o<=1;
      end
      default:begin end
     endcase
    end
   end
  end
 end
end
endmodule
