`timescale 1ns/1ps
module tb_studio_mixer;
 reg clk=0,rstn=0,valid=0,ready=0;
 always #10 clk=~clk;
 reg [167:0] vectors[0:399];
 reg [135:0] data=0;reg [20:0] tag=0;
 wire accept,returned;wire [63:0] result;wire [20:0] identity;
 integer sent=0,received=0,cycle=0;
 StudioOscMixer dut(.i_axis_aclk(clk),.i_axis_arstn(rstn),.i_s_axis_tdata(data),.i_s_axis_tuser(tag),
 .i_s_axis_tvalid(valid),.o_s_axis_tready(accept),.o_m_axis_tdata(result),.o_m_axis_tuser(identity),.o_m_axis_tvalid(returned),.i_m_axis_tready(ready));
 always @(negedge clk)begin
  cycle=cycle+1;ready=(cycle%7)!=0;
  if(rstn&&(!valid||accept))begin
   if(sent<400)begin valid=1;data=vectors[sent][167:32];tag=sent;end else valid=0;
  end
 end
 always @(posedge clk)if(rstn)begin
  if(valid&&accept)sent=sent+1;
  if(returned&&ready)begin
   if(identity!==received||result[31:0]!==vectors[received][31:0]||result[63:32]!=0)
    $fatal(1,"mix mismatch n=%d got=%h expected=%h identity=%d",received,result,vectors[received][31:0],identity);
   received=received+1;
   if(received==400)begin $display("PASS Studio mixer 400 independent vectors with backpressure");$finish;end
  end
 end
 initial begin $readmemh("mix_vectors.hex",vectors);repeat(4)@(negedge clk);rstn=1;end
 initial #1000000 $fatal(1,"mixer watchdog");
endmodule
