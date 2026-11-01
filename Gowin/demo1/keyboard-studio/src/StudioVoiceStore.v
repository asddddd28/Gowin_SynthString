`timescale 1ns/1ps
// StudioVoiceStore: synchronous banks. Boot writes clear state before audio starts.
module StudioVoiceStore #(parameter C_VOICES=32)(
 input i_clk,input i_rstn,input i_cfg_write,input [4:0] i_cfg_voice,input [511:0] i_cfg_data,
 input [4:0] i_read_voice,output [511:0] o_profile,output [383:0] o_state,
 input i_write,input [4:0] i_write_voice,input [2:0] i_write_stage,input [191:0] i_write_data,
 input i_event_consume,input [4:0] i_event_voice
);
 reg flag_write;
 reg [4:0] reg_write_voice;
 reg [2:0] reg_write_stage;
 reg [191:0] reg_write_data;
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin flag_write<=0;reg_write_voice<=0;reg_write_stage<=0;reg_write_data<=0;end
  else begin flag_write<=i_write;reg_write_voice<=i_write_voice;reg_write_stage<=i_write_stage;reg_write_data<=i_write_data;end
 end
 reg [511:0] mem_profile[0:C_VOICES-1],reg_profile;
 reg [1:0] mem_event[0:C_VOICES-1],reg_event;
 integer idx;
 assign o_profile={reg_profile[511:171],reg_event,reg_profile[168:0]};
 always @(posedge i_clk) begin
  if(i_cfg_write&&!i_cfg_data[483])mem_profile[i_cfg_voice]<=i_cfg_data;
  reg_profile<=mem_profile[i_read_voice];reg_event<=mem_event[i_read_voice];
 end
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn)begin for(idx=0;idx<C_VOICES;idx=idx+1)mem_event[idx]<=0;end
  else if(i_cfg_write)mem_event[i_cfg_voice]<=i_cfg_data[170:169];
  else if(i_event_consume)mem_event[i_event_voice]<=0;
 end
 reg [31:0] mem_phase_mod[0:C_VOICES-1],reg_phase_mod;
 assign o_state[31:0]=reg_phase_mod;
 always @(posedge i_clk)begin
  if(i_cfg_write&&i_cfg_data[482])mem_phase_mod[i_cfg_voice]<=0;
  else if(flag_write&&reg_write_stage==3'd0)mem_phase_mod[reg_write_voice]<=reg_write_data[31:0];
  reg_phase_mod<=mem_phase_mod[i_read_voice];
 end
 reg [31:0] mem_phase_carrier[0:C_VOICES-1],reg_phase_carrier;
 assign o_state[63:32]=reg_phase_carrier;
 always @(posedge i_clk)begin
  if(i_cfg_write&&i_cfg_data[482])mem_phase_carrier[i_cfg_voice]<=0;
  else if(flag_write&&reg_write_stage==3'd2)mem_phase_carrier[reg_write_voice]<=reg_write_data[31:0];
  reg_phase_carrier<=mem_phase_carrier[i_read_voice];
 end
 reg [34:0] mem_envelope[0:C_VOICES-1],reg_envelope;
 assign o_state[98:64]=reg_envelope;
 always @(posedge i_clk)begin
  if(i_cfg_write&&i_cfg_data[482])mem_envelope[i_cfg_voice]<=0;
  else if(flag_write&&reg_write_stage==3'd4)mem_envelope[reg_write_voice]<=reg_write_data[34:0];
  reg_envelope<=mem_envelope[i_read_voice];
 end
 reg [153:0] mem_filter[0:C_VOICES-1],reg_filter;
 assign o_state[252:99]=reg_filter;
 always @(posedge i_clk)begin
  if(i_cfg_write&&i_cfg_data[482])mem_filter[i_cfg_voice]<=0;
  else if(flag_write&&reg_write_stage==3'd6)mem_filter[reg_write_voice]<=reg_write_data[185:32];
  reg_filter<=mem_filter[i_read_voice];
 end
 reg [31:0] mem_wave_mod[0:C_VOICES-1],reg_wave_mod;
 assign o_state[284:253]=reg_wave_mod;
 always @(posedge i_clk)begin
  if(i_cfg_write&&i_cfg_data[482])mem_wave_mod[i_cfg_voice]<=0;
  else if(flag_write&&reg_write_stage==3'd1)mem_wave_mod[reg_write_voice]<=reg_write_data[31:0];
  reg_wave_mod<=mem_wave_mod[i_read_voice];
 end
 reg [31:0] mem_wave_carrier[0:C_VOICES-1],reg_wave_carrier;
 assign o_state[316:285]=reg_wave_carrier;
 always @(posedge i_clk)begin
  if(i_cfg_write&&i_cfg_data[482])mem_wave_carrier[i_cfg_voice]<=0;
  else if(flag_write&&reg_write_stage==3'd3)mem_wave_carrier[reg_write_voice]<=reg_write_data[31:0];
  reg_wave_carrier<=mem_wave_carrier[i_read_voice];
 end
 reg [31:0] mem_audio[0:C_VOICES-1],reg_audio;
 assign o_state[348:317]=reg_audio;
 always @(posedge i_clk)begin
  if(i_cfg_write&&i_cfg_data[482])mem_audio[i_cfg_voice]<=0;
  else if(flag_write&&reg_write_stage==3'd5)mem_audio[reg_write_voice]<=reg_write_data[31:0];
  reg_audio<=mem_audio[i_read_voice];
 end
 reg [34:0] mem_mod_envelope[0:C_VOICES-1],reg_mod_envelope;
 assign o_state[383:349]=reg_mod_envelope;
 always @(posedge i_clk)begin
  if(i_cfg_write&&i_cfg_data[482])mem_mod_envelope[i_cfg_voice]<=0;
  else if(flag_write&&reg_write_stage==3'd7)mem_mod_envelope[reg_write_voice]<=reg_write_data[34:0];
  reg_mod_envelope<=mem_mod_envelope[i_read_voice];
 end
endmodule
