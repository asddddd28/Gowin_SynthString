`timescale 1ns / 1ps
module tb_keyboard_loudness(output o_done);
 reg clk=0,rstn=0,valid=0,done=0;
 reg [23:0] sample=0;
 reg [31:0] active=0;
 reg [3:0] volume=0;
 wire outvalid;wire [23:0] result,peak_in,peak_out;
 wire [5:0] count;wire [18:0] gain;wire [31:0] clips;
 integer file_id,status,rows=0,n,v,expected_gain,expected_clips;
 reg [23:0] input_sample,expected;
 assign o_done=done;
 always #10 clk=~clk;
 KeyboardLoudness dut(.i_clk(clk),.i_rstn(rstn),.i_valid(valid),.i_sample(sample),.i_active(active),.i_volume(volume),
 .o_valid(outvalid),.o_sample(result),.o_active_count(count),.o_gain(gain),.o_input_peak(peak_in),.o_output_peak(peak_out),.o_clips(clips));
 initial begin
  file_id=$fopen("loudness_vectors.txt","r");if(file_id==0)$fatal(1,"missing vectors");
  repeat(4)@(negedge clk);rstn=1;
  while(!$feof(file_id))begin
   status=$fscanf(file_id,"%h %h %h %h %h %h\n",n,v,input_sample,expected,expected_gain,expected_clips);
   if(status!=6)$fatal(1,"bad vector");
   active=n==32?32'hffffffff:((32'h1<<n)-1);volume=v;
   repeat(8)@(negedge clk);
   if(gain!==expected_gain||count!==n)$fatal(1,"gain/count row %d gain %d expected %d",rows,gain,expected_gain);
   sample=input_sample;valid=1;@(negedge clk);valid=0;
   repeat(3)@(negedge clk);
   if(!outvalid||result!==expected||clips!==expected_clips)$fatal(1,"PCM row %d got %h expected %h clips %d/%d",rows,result,expected,clips,expected_clips);
   @(negedge clk);if(outvalid)$fatal(1,"duplicate output");rows=rows+1;
  end
  // Reset cancels an in-flight sample and clears metering/clip history.
  valid=1;@(negedge clk);valid=0;rstn=0;@(negedge clk);
  if(outvalid||result||clips||gain)$fatal(1,"reset failed");
  $display("PASS loudness independent reference rows=%0d",rows);done=1;$finish;
 end
endmodule
