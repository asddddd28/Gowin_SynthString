`timescale 1ns/1ps
// KeyboardVoiceBridge: 32 个逻辑声部独立保存状态，共享现有 AXIS 运算器。
// 合同和时序：../spec/KeyboardVoiceBridge_spec.md。
module KeyboardVoiceBridge(
 input i_clk,input i_rstn,input [31:0] i_pressed,input i_frame_done,
 output o_cfg_valid,input i_cfg_ready,output [4:0] o_cfg_voice,
 output [375:0] o_cfg_data,output o_initialized,
 output [31:0] o_delivered,output [31:0] o_events
);
 localparam [2:0] C_BOOT=0,C_BOOT_SEND=1,C_SCAN=2,C_SEND=3,C_WAIT=4;
 reg [2:0] state_current,state_next;
 reg [4:0] cnt_key,reg_voice_o;
 reg [375:0] mem_profile[0:31],reg_profile_o;
 reg [31:0] reg_delivered_o,cnt_events_o;
 reg flag_target,flag_initialized_o;
 wire flag_transfer,flag_changed;
 initial $readmemh("note_profiles.hex",mem_profile);
 assign o_cfg_valid=state_current==C_BOOT_SEND || state_current==C_SEND;
 assign flag_transfer=o_cfg_valid&&i_cfg_ready;
 assign flag_changed=i_pressed[cnt_key]!=reg_delivered_o[cnt_key];
 assign o_cfg_voice=reg_voice_o;assign o_cfg_data=reg_profile_o;
 assign o_initialized=flag_initialized_o;
 assign o_delivered=reg_delivered_o;assign o_events=cnt_events_o;
 always @(*) begin
  state_next=state_current;
  case(state_current)
   C_BOOT:state_next=C_BOOT_SEND;
   C_BOOT_SEND:if(flag_transfer)begin if(cnt_key==31)state_next=C_SCAN;else state_next=C_BOOT;end
   C_SCAN:if(flag_changed)state_next=C_SEND;
   C_SEND:if(flag_transfer)state_next=C_WAIT;
   C_WAIT:if(i_frame_done)state_next=C_SCAN;
   default:state_next=C_BOOT;
  endcase
 end
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn)state_current<=C_BOOT;else state_current<=state_next;
 end
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn)begin
   cnt_key<=0;reg_voice_o<=0;reg_profile_o<=0;reg_delivered_o<=0;
   cnt_events_o<=0;flag_target<=0;flag_initialized_o<=0;
  end else begin
   case(state_current)
    C_BOOT:begin reg_voice_o<=cnt_key;reg_profile_o<=mem_profile[cnt_key];end
    C_BOOT_SEND:if(flag_transfer)begin
     cnt_key<=cnt_key+1'b1;
     if(cnt_key==31)flag_initialized_o<=1;
    end
    C_SCAN:begin
     if(flag_changed)begin
      reg_voice_o<=cnt_key;flag_target<=i_pressed[cnt_key];
      reg_profile_o<=mem_profile[cnt_key];
      reg_profile_o[170:169]<=i_pressed[cnt_key]?2'd1:2'd2;
     end else cnt_key<=cnt_key+1'b1;
    end
    C_SEND:if(flag_transfer)begin
     reg_delivered_o[reg_voice_o]<=flag_target;cnt_events_o<=cnt_events_o+1'b1;
    end
    C_WAIT:if(i_frame_done)cnt_key<=cnt_key+1'b1;
    default:begin end
   endcase
  end
 end
endmodule
