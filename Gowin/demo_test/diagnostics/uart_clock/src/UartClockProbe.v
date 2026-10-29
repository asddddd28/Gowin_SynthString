`timescale 1ns/1ps
// Independent clock/UART probe. H=KEY0 released, L=KEY0 asserted.
module UartClockProbe(input wire i_clk,input wire i_rstn,output wire o_uart_tx);
reg [8:0] cnt_baud=0;
reg [3:0] cnt_bit=0;
reg [9:0] reg_frame=10'h3ff;
reg [1:0] reg_button=0;
always @(posedge i_clk) begin
 reg_button <= {reg_button[0],i_rstn};
 if(cnt_baud==433) begin
  cnt_baud<=0;
  if(cnt_bit==9) begin
   cnt_bit<=0;
   reg_frame<={1'b1,(reg_button[1] ? 8'h48 : 8'h4c),1'b0};
  end else begin cnt_bit<=cnt_bit+1'b1; reg_frame<={1'b1,reg_frame[9:1]}; end
 end else cnt_baud<=cnt_baud+1'b1;
end
assign o_uart_tx=reg_frame[0];
endmodule
