`timescale 1ns/1ps
// Studio patches are committed to program RAM; sounding snapshots live in the engine.
module KeyboardVoiceBridge(
 input i_clk,input i_rstn,input [31:0] i_pressed,input i_frame_done,
 input i_patch_valid,output o_patch_ready,input [4:0] i_patch_key,input [511:0] i_patch_data,
 input [223:0] i_velocity,
 output o_cfg_valid,input i_cfg_ready,output [4:0] o_cfg_voice,
 output [511:0] o_cfg_data,output o_initialized,output [31:0] o_delivered,output [31:0] o_events
);
 localparam [2:0] C_BOOT=0,C_BOOT_LOAD=1,C_BOOT_SEND=2,C_SCAN=3,C_LOAD=4,C_SEND=5,C_WAIT=6;
 reg [2:0] state_current,state_next;
 reg [4:0] cnt_key,reg_voice;
 reg [511:0] mem_profile[0:31],reg_read,reg_profile;
 reg [31:0] reg_delivered,cnt_events;
 reg flag_target,flag_initialized;
 wire flag_transfer=o_cfg_valid&&i_cfg_ready;
 wire flag_changed=i_pressed[cnt_key]!=reg_delivered[cnt_key];
 initial $readmemh("note_profiles.hex",mem_profile);
 assign o_patch_ready=state_current==C_SCAN&&!flag_changed;
 assign o_cfg_valid=state_current==C_BOOT_SEND||state_current==C_SEND;
 assign o_cfg_voice=reg_voice;assign o_cfg_data=reg_profile;
 assign o_initialized=flag_initialized;assign o_delivered=reg_delivered;assign o_events=cnt_events;
 always @(posedge i_clk)begin
  reg_read<=mem_profile[cnt_key];
  if(i_patch_valid&&o_patch_ready)mem_profile[i_patch_key]<=i_patch_data;
 end
 always @(*)begin
  state_next=state_current;
  case(state_current)
   C_BOOT:state_next=C_BOOT_LOAD;
   C_BOOT_LOAD:state_next=C_BOOT_SEND;
   C_BOOT_SEND:if(flag_transfer)state_next=cnt_key==31?C_SCAN:C_BOOT;
   C_SCAN:if(flag_changed)state_next=C_LOAD;
   C_LOAD:state_next=C_SEND;
   C_SEND:if(flag_transfer)state_next=C_WAIT;
   C_WAIT:if(i_frame_done)state_next=C_SCAN;
   default:state_next=C_BOOT;
  endcase
 end
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)state_current<=C_BOOT;else state_current<=state_next;
 end
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin cnt_key<=0;reg_voice<=0;reg_profile<=0;reg_delivered<=0;cnt_events<=0;flag_target<=0;flag_initialized<=0;end
  else case(state_current)
   C_BOOT_LOAD:begin reg_voice<=cnt_key;reg_profile<=reg_read;reg_profile[482]<=1;end
   C_BOOT_SEND:if(flag_transfer)begin cnt_key<=cnt_key+1'b1;if(cnt_key==31)flag_initialized<=1;end
   C_SCAN:if(!flag_changed)cnt_key<=cnt_key+1'b1;
   C_LOAD:begin
    reg_voice<=cnt_key;reg_profile<=reg_read;flag_target<=i_pressed[cnt_key];
    reg_profile[170:169]<=i_pressed[cnt_key]?2'd1:2'd2;
    reg_profile[367:361]<=i_velocity[cnt_key*7+:7];
    reg_profile[483]<=!i_pressed[cnt_key];
   end
   C_SEND:if(flag_transfer)begin reg_delivered[reg_voice]<=flag_target;cnt_events<=cnt_events+1'b1;end
   C_WAIT:if(i_frame_done)cnt_key<=cnt_key+1'b1;
   default:begin end
  endcase
 end
endmodule
