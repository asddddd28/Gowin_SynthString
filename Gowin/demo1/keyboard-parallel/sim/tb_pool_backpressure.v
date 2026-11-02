`timescale 1ns/1ps
// Independent arithmetic scoreboard, long return stalls and reset cancellation.
module pool_backpressure_case #(parameter C_CORES=1)(input clk,output reg done=0);
 reg rstn=0,valid=0,ready=0;
 reg [127:0] data=0;reg [20:0] user=0;
 wire in_ready,out_valid;wire [31:0] result;wire [20:0] result_user;
 reg [31:0] expected[0:511];reg [20:0] tags[0:511];
 reg [31:0] previous_result;reg [20:0] previous_user;
 reg stalled=0;reg signed [63:0] product;
 integer sent=0,retired=0,cycles=0,random_state=271+47*C_CORES;
 integer blocked_input=0,blocked_output=0,reset_sent=0;
 AxisComputePool #(.C_KIND(0),.C_CORES(C_CORES),.C_INPUT_WIDTH(128),.C_OUTPUT_WIDTH(32),.C_ADDR_WIDTH(2)) dut(
 .i_axis_aclk(clk),.i_axis_arstn(rstn),.i_s_axis_tdata(data),.i_s_axis_tuser(user),
 .i_s_axis_tvalid(valid),.o_s_axis_tready(in_ready),.o_m_axis_tdata(result),.o_m_axis_tuser(result_user),
 .o_m_axis_tvalid(out_valid),.i_m_axis_tready(ready),.i_wave_write(1'b0),.i_wave_frame(1'b0),.i_wave_address(11'd0),.i_wave_data(16'd0));
 always @(posedge clk or negedge rstn)begin
  if(!rstn)begin sent=0;retired=0;stalled=0;end
  else begin
   if(stalled&&(!out_valid||result!==previous_result||result_user!==previous_user))$fatal(1,"unstable stalled output cores=%0d",C_CORES);
   if(valid&&in_ready)begin
    product=$signed(data[95:64])*$signed(data[127:96]);
    expected[sent]=data[31:0]+data[63:32]+(product>>>26);tags[sent]=user;sent=sent+1;
   end
   if(out_valid&&ready)begin
    if(retired>=sent||result!==expected[retired]||result_user!==tags[retired])$fatal(1,"pool order/arithmetic cores=%0d index=%0d",C_CORES,retired);
    retired=retired+1;
   end
   if(valid&&!in_ready)blocked_input=blocked_input+1;
   if(out_valid&&!ready)blocked_output=blocked_output+1;
   stalled=out_valid&&!ready;previous_result=result;previous_user=result_user;
  end
 end
 always @(negedge clk)if(rstn&&!done)begin
  cycles=cycles+1;random_state=(random_state*1103515245+12345)&32'h7fffffff;
  ready=(cycles>60)&&(cycles%97<42)&&(random_state%5!=0);
  if(!valid||in_ready)begin
   valid=sent<400&&(random_state%4!=0);user=sent+reset_sent*1024;
   data[31:0]=random_state*157;
   data[63:32]=random_state*73;
   data[95:64]=random_state*113;
   data[127:96]=random_state*193;
  end
 end
 initial begin
  repeat(4)@(negedge clk);#1;rstn=1;
  repeat(150)@(negedge clk);#1;
  if(sent==retired)$fatal(1,"reset test requires in-flight tasks");
  rstn=0;valid=0;ready=0;reset_sent=1;cycles=0;
  repeat(4)@(negedge clk);#1;rstn=1;
  wait(retired==400);@(negedge clk);#1;valid=0;ready=1;done=1;
  if(blocked_input==0||blocked_output==0)$fatal(1,"backpressure not exercised");
  $display("PASS pool cores=%0d ordered=%0d input_stalls=%0d output_stalls=%0d reset_cancel=1",C_CORES,retired,blocked_input,blocked_output);
 end
endmodule

module tb_pool_backpressure;
 reg clk=0;wire [3:0] done;
 always #10 clk=~clk;
 genvar n;
 generate for(n=0;n<4;n=n+1)begin:Cases
  pool_backpressure_case #(.C_CORES(n+1)) check_case(.clk(clk),.done(done[n]));
 end endgenerate
 initial begin wait(&done);repeat(10)@(negedge clk);$display("PASS all pool counts under backpressure");$finish;end
 initial #2000000 $fatal(1,"watchdog");
endmodule
