`timescale 1ns / 1ps
module tb_keyboard_mixer(output o_done);
 reg clk=0,rstn=0,start=0,valid=0,last=0,ready=0,done=0;
 reg [31:0] sample=0,random_word=32'h1598acd3;
 wire old_valid,new_valid;wire [23:0] old_left,new_left;
 integer frame,voice;
 assign o_done=done;always #10 clk=~clk;
 SynthFrameMixer #(.C_MIX_SHIFT(5)) old_dut(.i_clk(clk),.i_rstn(rstn),.i_start(start),.i_valid(valid),.i_sample(sample),.i_last(last),.o_pcm_valid(old_valid),.i_pcm_ready(ready),.o_pcm_left(old_left),.o_pcm_right());
 KeyboardFrameMixer #(.C_MIX_SHIFT(5)) new_dut(.i_clk(clk),.i_rstn(rstn),.i_start(start),.i_valid(valid),.i_sample(sample),.i_last(last),.o_pcm_valid(new_valid),.i_pcm_ready(ready),.o_pcm_left(new_left),.o_pcm_right());
 initial begin
  repeat(4)@(negedge clk);rstn=1;
  for(frame=0;frame<256;frame=frame+1)begin
   start=1;@(negedge clk);start=0;
   for(voice=0;voice<32;voice=voice+1)begin
    random_word={random_word[30:0],random_word[31]^random_word[21]^random_word[1]^random_word[0]};
    case(frame%6)
     0:sample=32'h7fffffff;1:sample=32'h80000000;
     2:sample=voice[0]?32'h7fffffff:32'h80000000;
     3:sample=0;4:sample=$signed(random_word)>>>13;default:sample=random_word;
    endcase
    valid=1;last=voice==31;@(negedge clk);valid=0;last=0;
    if(voice%3==0)repeat(2)@(negedge clk);
   end
   while(!new_valid)@(negedge clk);
   if(!old_valid||old_left!==new_left)$fatal(1,"mixer mismatch frame %d old %h new %h",frame,old_left,new_left);
   repeat(4)begin @(negedge clk);if(!new_valid||new_left!==old_left)$fatal(1,"hold under backpressure");end
   ready=1;@(negedge clk);ready=0;
  end
  rstn=0;@(negedge clk);if(new_valid||new_left)$fatal(1,"reset");
  $display("PASS mixer arithmetic equivalence 256 frames / 8192 signed inputs with stalls, saturation, hold and reset");done=1;$finish;
 end
 initial #2000000 $fatal(1,"watchdog");
endmodule
