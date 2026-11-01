`timescale 1ns/1ps
// Ordered AXIS pool. A lane owns a task only after its input handshake.
// The return cursor preserves global issue order while each lane retains its own credits.
module AxisComputePool #(
 parameter C_KIND=0,parameter C_CORES=1,
 parameter C_INPUT_WIDTH=128,parameter C_OUTPUT_WIDTH=32,
 parameter C_USER_WIDTH=21,parameter C_ADDR_WIDTH=3
)(
 input i_axis_aclk,input i_axis_arstn,
 input [C_INPUT_WIDTH-1:0] i_s_axis_tdata,input [C_USER_WIDTH-1:0] i_s_axis_tuser,
 input i_s_axis_tvalid,output o_s_axis_tready,
 output [C_OUTPUT_WIDTH-1:0] o_m_axis_tdata,output [C_USER_WIDTH-1:0] o_m_axis_tuser,
 output o_m_axis_tvalid,input i_m_axis_tready,
 input i_wave_write,input i_wave_frame,input [10:0] i_wave_address,input [15:0] i_wave_data
);
 reg [2:0] reg_dispatch,reg_retire;
 wire [C_CORES-1:0] flag_input_ready,flag_output_valid;
 wire [C_CORES*C_OUTPUT_WIDTH-1:0] wire_results;
 wire [C_CORES*C_USER_WIDTH-1:0] wire_users;
 wire flag_accept=i_s_axis_tvalid&&o_s_axis_tready;
 wire flag_retire=o_m_axis_tvalid&&i_m_axis_tready;
 assign o_s_axis_tready=i_axis_arstn&&flag_input_ready[reg_dispatch];
 assign o_m_axis_tvalid=i_axis_arstn&&flag_output_valid[reg_retire];
 assign o_m_axis_tdata=wire_results[reg_retire*C_OUTPUT_WIDTH+:C_OUTPUT_WIDTH];
 assign o_m_axis_tuser=wire_users[reg_retire*C_USER_WIDTH+:C_USER_WIDTH];
 always @(posedge i_axis_aclk or negedge i_axis_arstn)begin
  if(!i_axis_arstn)begin reg_dispatch<=0;reg_retire<=0;end
  else begin
   if(flag_accept)reg_dispatch<=reg_dispatch==C_CORES-1?0:reg_dispatch+1'b1;
   if(flag_retire)reg_retire<=reg_retire==C_CORES-1?0:reg_retire+1'b1;
  end
 end
 genvar lane;
 generate for(lane=0;lane<C_CORES;lane=lane+1)begin:CoreLane
  wire flag_lane_valid=i_s_axis_tvalid&&(reg_dispatch==lane)&&i_axis_arstn;
  wire flag_lane_ready=i_m_axis_tready&&(reg_retire==lane)&&i_axis_arstn;
  if(C_KIND==0)begin:Phase
   AxisPhaseFm #(.C_ADDR_WIDTH(C_ADDR_WIDTH)) Core_Inst(
    .i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(i_s_axis_tdata),.i_s_axis_tuser(i_s_axis_tuser),
    .i_s_axis_tvalid(flag_lane_valid),.o_s_axis_tready(flag_input_ready[lane]),
    .o_m_axis_tdata(wire_results[lane*C_OUTPUT_WIDTH+:C_OUTPUT_WIDTH]),.o_m_axis_tuser(wire_users[lane*C_USER_WIDTH+:C_USER_WIDTH]),
    .o_m_axis_tvalid(flag_output_valid[lane]),.i_m_axis_tready(flag_lane_ready));
  end else if(C_KIND==1)begin:Wave
   wire flag_lookup_valid,flag_lookup_ready;
   wire [159:0] wire_lookup_data;
   wire [20:0] wire_lookup_user;
   AxisWaveLookup Lookup_Inst(.i_clk(i_axis_aclk),.i_rstn(i_axis_arstn),
    .i_valid(flag_lane_valid),.o_ready(flag_input_ready[lane]),.i_query(i_s_axis_tdata),.i_user(i_s_axis_tuser),
    .o_valid(flag_lookup_valid),.i_ready(flag_lookup_ready),.o_data(wire_lookup_data),.o_user(wire_lookup_user),
    .i_write(i_wave_write),.i_frame(i_wave_frame),.i_address(i_wave_address),.i_data(i_wave_data));
   AxisWaveSample #(.C_ADDR_WIDTH(C_ADDR_WIDTH)) Core_Inst(
    .i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(wire_lookup_data),.i_s_axis_tuser(wire_lookup_user),
    .i_s_axis_tvalid(flag_lookup_valid),.o_s_axis_tready(flag_lookup_ready),
    .o_m_axis_tdata(wire_results[lane*C_OUTPUT_WIDTH+:C_OUTPUT_WIDTH]),.o_m_axis_tuser(wire_users[lane*C_USER_WIDTH+:C_USER_WIDTH]),
    .o_m_axis_tvalid(flag_output_valid[lane]),.i_m_axis_tready(flag_lane_ready));
  end else if(C_KIND==2)begin:Envelope
   AxisAdsr #(.C_ADDR_WIDTH(C_ADDR_WIDTH)) Core_Inst(
    .i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(i_s_axis_tdata),.i_s_axis_tuser(i_s_axis_tuser),
    .i_s_axis_tvalid(flag_lane_valid),.o_s_axis_tready(flag_input_ready[lane]),
    .o_m_axis_tdata(wire_results[lane*C_OUTPUT_WIDTH+:C_OUTPUT_WIDTH]),.o_m_axis_tuser(wire_users[lane*C_USER_WIDTH+:C_USER_WIDTH]),
    .o_m_axis_tvalid(flag_output_valid[lane]),.i_m_axis_tready(flag_lane_ready));
  end else if(C_KIND==3)begin:Modulation
   StudioOscMixer #(.C_ADDR_WIDTH(C_ADDR_WIDTH)) Core_Inst(
    .i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(i_s_axis_tdata),.i_s_axis_tuser(i_s_axis_tuser),
    .i_s_axis_tvalid(flag_lane_valid),.o_s_axis_tready(flag_input_ready[lane]),
    .o_m_axis_tdata(wire_results[lane*C_OUTPUT_WIDTH+:C_OUTPUT_WIDTH]),.o_m_axis_tuser(wire_users[lane*C_USER_WIDTH+:C_USER_WIDTH]),
    .o_m_axis_tvalid(flag_output_valid[lane]),.i_m_axis_tready(flag_lane_ready));
  end else if(C_KIND==4)begin:Filter
   AxisSvfSample #(.C_ADDR_WIDTH(C_ADDR_WIDTH),.C_USER_WIDTH(C_USER_WIDTH)) Core_Inst(
    .i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(i_s_axis_tdata),.i_s_axis_tuser(i_s_axis_tuser),
    .i_s_axis_tvalid(flag_lane_valid),.o_s_axis_tready(flag_input_ready[lane]),
    .o_m_axis_tdata(wire_results[lane*C_OUTPUT_WIDTH+:C_OUTPUT_WIDTH]),.o_m_axis_tuser(wire_users[lane*C_USER_WIDTH+:C_USER_WIDTH]),
    .o_m_axis_tvalid(flag_output_valid[lane]),.i_m_axis_tready(flag_lane_ready));
  end else begin:Vca
   AxisVoiceVca #(.C_ADDR_WIDTH(C_ADDR_WIDTH),.C_USER_WIDTH(C_USER_WIDTH)) Core_Inst(
    .i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(i_s_axis_tdata),.i_s_axis_tuser(i_s_axis_tuser),
    .i_s_axis_tvalid(flag_lane_valid),.o_s_axis_tready(flag_input_ready[lane]),
    .o_m_axis_tdata(wire_results[lane*C_OUTPUT_WIDTH+:C_OUTPUT_WIDTH]),.o_m_axis_tuser(wire_users[lane*C_USER_WIDTH+:C_USER_WIDTH]),
    .o_m_axis_tvalid(flag_output_valid[lane]),.i_m_axis_tready(flag_lane_ready));
  end
 end endgenerate
endmodule
