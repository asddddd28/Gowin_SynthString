`timescale 1ns / 1ps
// WS2812 GRB frame sender; pixel source is frozen by o_frame_tick.
// 50Hz刷新，0码高0.30us，1码高0.84us，每位1.26us。
module LedFrameTx #(parameter integer C_FRAME_CYCLES=1000000)(
 input i_clk,input i_rstn,input [23:0] i_grb,
 output [4:0] o_pixel,output o_frame_tick,output o_data
);
localparam [1:0] ST_WAIT=0,ST_LOAD=1,ST_SEND=2,ST_NEXT=3;
reg [1:0] state_current,state_next;
reg [31:0] cnt_frame;
reg [4:0] cnt_pixel,cnt_bit;
reg [5:0] cnt_slot;
reg [23:0] reg_shift;
reg reg_data_o;
assign o_pixel=cnt_pixel;
assign o_frame_tick=state_current==ST_WAIT && cnt_frame==C_FRAME_CYCLES-1;
assign o_data=reg_data_o;
always @(*)begin
 state_next=state_current;
 case(state_current)
  ST_WAIT:begin if(o_frame_tick)begin state_next=ST_LOAD; end end
  ST_LOAD:begin state_next=ST_SEND; end
  ST_SEND:begin if(cnt_slot==62 && cnt_bit==23)begin state_next=ST_NEXT; end end
  ST_NEXT:begin if(cnt_pixel==31)begin state_next=ST_WAIT; end else begin state_next=ST_LOAD; end end
  default:begin state_next=ST_WAIT; end
 endcase
end
always @(posedge i_clk or negedge i_rstn)begin
 if(!i_rstn)begin state_current<=ST_WAIT; end else begin state_current<=state_next; end
end
always @(posedge i_clk or negedge i_rstn)begin
 if(!i_rstn)begin cnt_frame<=0; end
 else if(cnt_frame==C_FRAME_CYCLES-1)begin cnt_frame<=0; end else begin cnt_frame<=cnt_frame+1'b1; end
end
always @(posedge i_clk or negedge i_rstn)begin
 if(!i_rstn)begin cnt_pixel<=0;cnt_bit<=0;cnt_slot<=0;reg_shift<=0;reg_data_o<=0; end
 else begin
  if(state_current==ST_WAIT)begin cnt_pixel<=0; end
  else if(state_current==ST_NEXT)begin cnt_pixel<=cnt_pixel+1'b1; end
  if(state_current!=ST_SEND)begin cnt_slot<=0;cnt_bit<=0;reg_data_o<=0; end
  else begin
   reg_data_o<=reg_shift[23] ? cnt_slot<42 : cnt_slot<15;
   if(cnt_slot==62)begin cnt_slot<=0;cnt_bit<=cnt_bit+1'b1;reg_shift<={reg_shift[22:0],1'b0}; end
   else begin cnt_slot<=cnt_slot+1'b1; end
  end
  if(state_current==ST_LOAD)begin reg_shift<=i_grb; end
 end
end
endmodule
