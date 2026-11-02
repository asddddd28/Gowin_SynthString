`timescale 1ns/1ps
// Weighted oscillator mix or AM/ring. Q26 audio, Q16 oscillator gains.
module StudioOscMixer #(parameter C_ADDR_WIDTH=5)(
 input i_axis_aclk,input i_axis_arstn,input [135:0] i_s_axis_tdata,input [20:0] i_s_axis_tuser,
 input i_s_axis_tvalid,output o_s_axis_tready,output [63:0] o_m_axis_tdata,
 output [20:0] o_m_axis_tuser,output o_m_axis_tvalid,input i_m_axis_tready
);
 wire [135:0] data;wire launch;
 reg [6:0] valid;
 reg signed [31:0] modulator;
 reg [31:0] depth;
 reg signed [64:0] product;
 reg signed [31:0] factor;
 reg signed [63:0] carrier_product;
 reg signed [48:0] gain_carrier,gain_modulator;
 reg signed [49:0] sum;
 reg [31:0] result;
 reg [135:0] context_first,context_second,context_third,context_fourth;
 reg mix_delayed;
 wire signed [64:0] scaled=product>>>26;
 wire signed [64:0] distance=$signed({1'b0,context_second[95:64]})-scaled;
 wire signed [31:0] carrier_scaled=carrier_product>>>26;
 wire signed [49:0] output_scaled=sum>>>16;
 AxisFixedCore #(.C_INPUT_WIDTH(136),.C_OUTPUT_WIDTH(64),.C_USER_WIDTH(21),.C_ADDR_WIDTH(C_ADDR_WIDTH)) Queue_Inst(
 .i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(i_s_axis_tdata),.i_s_axis_tuser(i_s_axis_tuser),
 .i_s_axis_tvalid(i_s_axis_tvalid),.o_s_axis_tready(o_s_axis_tready),.o_m_axis_tdata(o_m_axis_tdata),
 .o_m_axis_tuser(o_m_axis_tuser),.o_m_axis_tvalid(o_m_axis_tvalid),.i_m_axis_tready(i_m_axis_tready),
 .o_core_valid(launch),.o_core_data(data),.i_core_valid(valid[6]),.i_core_data({32'd0,result}));
 always @(posedge i_axis_aclk or negedge i_axis_arstn)begin
  if(!i_axis_arstn)begin
   valid<=0;modulator<=0;depth<=0;product<=0;factor<=0;carrier_product<=0;
   gain_carrier<=0;gain_modulator<=0;sum<=0;result<=0;
   context_first<=0;context_second<=0;context_third<=0;context_fourth<=0;mix_delayed<=0;
  end else begin
   valid<={valid[5:0],launch};
   modulator<=$signed(data[63:32]);depth<=data[95:64];context_first<=data;
   product<=$signed({1'b0,depth})*modulator;context_second<=context_first;
   case(context_second[97:96])
    1:factor<=65'sd67108864-(distance>>>1);
    2:factor<=65'sd67108864-distance;
    default:factor<=32'sd67108864;
   endcase
   context_third<=context_second;
   carrier_product<=$signed(context_third[31:0])*factor;context_fourth<=context_third;
   gain_carrier<=carrier_scaled*$signed({1'b0,context_fourth[114:99]});
   gain_modulator<=$signed(context_fourth[63:32])*$signed({1'b0,context_fourth[130:115]});
   mix_delayed<=context_fourth[98];
   sum<=gain_carrier+(mix_delayed?gain_modulator:49'sd0);
   if(output_scaled>50'sd2147483647)result<=32'h7fffffff;
   else if(output_scaled< -50'sd2147483648)result<=32'h80000000;
   else result<=output_scaled[31:0];
  end
 end
endmodule
