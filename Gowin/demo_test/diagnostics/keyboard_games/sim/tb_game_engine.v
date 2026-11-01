`timescale 1ns / 1ps
module tb_game_engine;
reg clk=0,rstn=0,start=0,stop=0,tick=0;
reg [1:0] game=0;
reg [31:0] press=0,pressed=0;
wire [63:0] pixels;
wire [127:0] status;
reg [15:0] forced_seed=0;
integer n,index,slot;
reg [31:0] occupied_fixture;
reg [63:0] display_pixels=0;
reg display_tick=0,display_enable=0;
reg [4:0] display_key=0;
wire display_active;
wire [23:0] display_grb;
always #10 clk=~clk;
GameEngine dut(.i_clk(clk),.i_rstn(rstn),.i_start(start),.i_stop(stop),.i_game(game),
 .i_frame_tick(tick),.i_press(press),.i_pressed(pressed),.o_pixels(pixels),.o_status(status));
GameDisplay display(.i_clk(clk),.i_rstn(rstn),.i_enable(display_enable),.i_frame_tick(display_tick),
 .i_pixels(display_pixels),.i_pixel(display_key),.o_active(display_active),.o_grb(display_grb));
task frames;
 input integer count;
 integer f;
 begin
  for(f=0;f<count;f=f+1)begin
   @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(40)@(negedge clk);
  end
 end
endtask
task hit;
 input [31:0] mask;
 begin @(negedge clk);press=mask;pressed=mask;@(negedge clk);press=0;repeat(3)@(negedge clk);end
endtask
task begin_game;
 input [1:0] chosen;
 input [15:0] seed;
 begin
  @(negedge clk);forced_seed=seed;force dut.reg_random=forced_seed;
  game=chosen;start=1;press=0;@(negedge clk);start=0;repeat(40)@(negedge clk);
  if(status[119:112]!=1 || status[111:104]!=3 || status[95:80]!=0)begin $display("FAIL start/countdown");$finish;end
  frames(149);
  if(status[119:112]!=1 || status[111:104]!=1)begin $display("FAIL early countdown end");$finish;end
  frames(1);
  if(status[119:112]!=2)begin $display("FAIL countdown duration");$finish;end
 end
endtask
task snake_fixture;
 input integer shape;
 begin
  @(negedge clk);
  dut.mem_body[0]=9;dut.mem_body[1]=10;dut.mem_body[2]=18;dut.mem_body[3]=17;
  dut.reg_occupied=32'h00060600;dut.reg_length=4;dut.reg_direction=shape==0?1:3;
  dut.flag_turn=0;dut.cnt_move=0;dut.reg_move_limit=25;dut.flag_spawn=0;
  dut.flag_apple=1;dut.reg_apple=0;
 end
endtask
initial begin
 #101;rstn=1;
 // Deterministic seed chooses apple at11, directly ahead of the initial head10.
 begin_game(1,11);release dut.reg_random;
 if(dut.reg_apple!=11 || pixels[45:44]!=3 || pixels[61:60]!=3)begin $display("FAIL snake spawn/control palette");$finish;end
 hit(32'b1<<29);frames(25);
 if(dut.mem_body[0]!=11 || dut.reg_length!=4 || status[95:80]!=10)begin $display("FAIL snake grow/reversal");$finish;end
 hit(32'b1<<22);hit(32'b1<<29);frames(24);
 if(dut.mem_body[0]!=3 || dut.reg_direction!=0)begin $display("FAIL queued turn limit");$finish;end
 frames(24);
 if(status[119:112]!=3 || status[103:96]!=1 || pixels!=64'hAAAAAAAAAAAAAAAA)begin $display("FAIL wall collision/red");$finish;end
 frames(10);if(pixels!=0)begin $display("FAIL result blink off");$finish;end
 begin_game(1,0);release dut.reg_random;snake_fixture(0);frames(25);
 if(status[119:112]!=2 || dut.mem_body[0]!=17)begin $display("FAIL moving into vacating tail");$finish;end
 begin_game(1,0);release dut.reg_random;snake_fixture(1);frames(25);
 if(status[119:112]!=3 || status[103:96]!=2)begin $display("FAIL snake self collision");$finish;end
 // Near-full-board fixture exercises the last legal apple and win path.
 begin_game(1,11);release dut.reg_random;@(negedge clk);
 occupied_fixture=~32'hE0400800;dut.reg_occupied=occupied_fixture;dut.reg_length=27;
 dut.mem_body[0]=10;slot=1;
 for(index=0;index<32;index=index+1)if(occupied_fixture[index] && index!=10)begin dut.mem_body[slot]=index;slot=slot+1;end
 dut.reg_apple=11;dut.flag_apple=1;dut.flag_spawn=0;dut.cnt_move=0;dut.reg_direction=3;dut.flag_turn=0;
 frames(25);
 if(status[119:112]!=4 || status[103:96]!=6 || dut.reg_length!=28)begin $display("FAIL snake win");$finish;end
 // Each color scores its declared amount, exactly once per disappearing target.
 for(n=1;n<=3;n=n+1)begin
  pressed=0;begin_game(2,n);
  if(pixels[n*2+:2]!=n)begin $display("FAIL mole color %0d",n);$finish;end
  hit(32'b1<<n);release dut.reg_random;
  if(status[95:80]!=(n==1?10:n==2?30:20))begin $display("FAIL mole score");$finish;end
  repeat(100)@(negedge clk);
  if(pixels[n*2+:2]!=0)begin $display("FAIL hit did not remove mole");$finish;end
 end
 // Simultaneous hit sum and hit-on-expiry priority use a controlled target fixture.
 begin_game(2,1);release dut.reg_random;@(negedge clk);dut.flag_spawn=0;
 for(index=0;index<32;index=index+1)begin dut.mem_target[index]=0;dut.mem_life[index]=0;end
 dut.mem_target[0]=1;dut.mem_target[1]=2;dut.mem_target[2]=3;
 dut.mem_life[0]=1;dut.mem_life[1]=1;dut.mem_life[2]=1;
 press=7;tick=1;@(negedge clk);press=0;tick=0;
 if(status[95:80]!=60 || status[79:72]!=0)begin $display("FAIL simultaneous score/expiry priority");$finish;end
 @(negedge clk);dut.mem_target[0]=1;dut.mem_life[0]=1;frames(1);
 if(status[79:72]!=1)begin $display("FAIL missed target count");$finish;end
 // Held keys cannot receive new targets. Exactly3000 ticks make the60-second game.
 pressed=32'hFFFFFFFF;begin_game(2,5);release dut.reg_random;
 frames(2999);
 if(pixels!=0 || status[119:112]!=2 || status[111:104]!=1)begin $display("FAIL held-key exclusion or early finish");$finish;end
 frames(1);
 if(status[119:112]!=3 || status[111:104]!=0 || status[95:80]!=0)begin $display("FAIL60second result");$finish;end
 frames(100);if(pixels!=0)begin $display("FAIL result settled off");$finish;end
 // Piano: only bottom eight keys act; successful press advances all four rows.
 pressed=0;begin_game(3,0);release dut.reg_random;
 hit(1);if(status[95:80]!=0)begin $display("FAIL upper row accepted");$finish;end
 hit(32'b1<<26);
 if(status[95:80]!=1 || dut.mem_note[3]!=5 || dut.mem_note[2]!=3 || dut.mem_note[1]!=0)begin $display("FAIL piano correct/shift");$finish;end
 frames(20);if(status[95:80]!=1)begin $display("FAIL held piano repeats");$finish;end
 hit(32'b1<<24);
 if(status[119:112]!=3 || status[103:96]!=3 || pixels!=64'hAAAAAAAAAAAAAAAA)begin $display("FAIL piano wrong/red");$finish;end
 begin_game(3,0);release dut.reg_random;frames(89);
 if(status[119:112]!=2)begin $display("FAIL early piano deadline");$finish;end
 frames(1);if(status[119:112]!=3 || status[103:96]!=4)begin $display("FAIL piano timeout");$finish;end
 begin_game(3,0);release dut.reg_random;hit((32'b1<<26)|(32'b1<<25));
 if(status[119:112]!=3 || status[103:96]!=3)begin $display("FAIL multi-key piano mistake");$finish;end
 begin_game(3,0);release dut.reg_random;frames(89);
 @(negedge clk);press=32'b1<<26;tick=1;@(negedge clk);press=0;tick=0;
 if(status[119:112]!=2 || status[95:80]!=1)begin $display("FAIL last-tick piano hit");$finish;end
 @(negedge clk);stop=1;@(negedge clk);stop=0;
 if(status[119:112]!=0 || status[103:96]!=5 || pixels!=0)begin $display("FAIL stop");$finish;end
 // Display palette and complete-frame snapshot, independent of game mutations.
 display_pixels=64'hE4;display_enable=1;display_tick=1;@(negedge clk);display_tick=0;
 for(index=0;index<4;index=index+1)begin
  display_key=index;#1;
  case(index)
   0:if(display_grb!=0)begin $display("FAIL palette black");$finish;end
   1:if(display_grb!=24'h200000)begin $display("FAIL palette green");$finish;end
   2:if(display_grb!=24'h002000)begin $display("FAIL palette red");$finish;end
   3:if(display_grb!=24'h200020)begin $display("FAIL palette cyan");$finish;end
  endcase
 end
 display_pixels=0;display_enable=0;#21;
 if(!display_active || display_grb!=24'h200020)begin $display("FAIL frame tearing");$finish;end
 rstn=0;#1;if(status!=0 || display_active || display_grb!=0)begin $display("FAIL reset");$finish;end
 $display("PASS autonomous games: countdown150ticks; snake grow/turn/reverse/wall/self/vacating-tail/full-board; mole three scores/simultaneous/expiry/held exclusion/exact3000ticks; piano shift/upper ignored/wrong/multiple/timeout/deadline; result blink, stop, reset, palette frame snapshot");$finish;
end
initial begin #20000000;$display("FAIL game test timeout");$finish;end
endmodule
