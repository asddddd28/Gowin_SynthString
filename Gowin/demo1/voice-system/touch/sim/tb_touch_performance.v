`timescale 1ns / 1ps
module tb_touch_performance;
    reg clk=0,rstn=0,next_mode=0,silent=0,request=0,keys_idle=1;
    always #10 clk=~clk;
    reg [1:0] update=0,touch=0;
    reg [19:0] x=0,y=0;
    reg [15:0] error=0;
    reg [31:0] pressed=0,delivered=0;
    reg [7:0] opcode=0,argument=0;
    reg [63:0] words=0;
    wire [31:0] played,pitch;
    wire [17:0] gain;
    wire [19:0] cutoff;
    wire [1:0] mode;
    wire active,valid;wire [135:0] response;
    integer n;
    SynthTouchPerformance #(.C_MS(10)) dut(.i_clk(clk),.i_rstn(rstn),.i_next_mode(next_mode),.i_silent(silent),
        .i_update(update),.i_touch(touch),.i_x(x),.i_y(y),.i_error(error),.i_pressed(pressed),.i_delivered(delivered),.i_keys_idle(keys_idle),
        .o_pressed(played),.o_mode(mode),.o_gain(gain),.o_pitch(pitch),.o_cutoff(cutoff),.o_cutoff_active(active),
        .i_request(request),.i_opcode(opcode),.i_argument(argument),.i_words(words),.o_response_valid(valid),.o_response(response));
    task command;input [7:0] op;input [63:0] data;
        begin @(negedge clk);opcode=op;words=data;request=1;@(negedge clk);request=0;if(!valid)$fatal(1,"missing ACK");end
    endtask
    task point;input present;input [9:0] px,py;
        begin @(negedge clk);x={10'd0,px};y={10'd0,py};touch={1'b0,present};update=1;@(negedge clk);update=0;repeat(5)@(negedge clk);end
    endtask
    task hold_point;input present;input [9:0] px,py;
        begin for(n=0;n<24;n=n+1)begin point(present,px,py);repeat(50)@(negedge clk);end end
    endtask
    initial begin
        repeat(4)@(negedge clk);rstn=1;
        command(8'h30,0);if(response[31:0]!==32'h544f5531)$fatal(1,"capability");
        hold_point(1,1023,0);if(gain<81890 || gain>81904)$fatal(1,"gain high %d",gain);
        hold_point(1,0,1023);if(gain>49190 || gain<49168)$fatal(1,"gain low %d",gain);
        hold_point(0,0,0);if(gain!==65536)$fatal(1,"gain release %d",gain);
        command(8'h31,64'h0040152000000001);hold_point(1,1023,0);if($signed(pitch)<=0)$fatal(1,"pitch high");
        hold_point(1,0,1023);if($signed(pitch)>=0)$fatal(1,"pitch low");
        command(8'h31,64'h0040152000000002);hold_point(1,1023,0);if($signed(cutoff)<=0 || !active)$fatal(1,"cutoff high");
        hold_point(0,0,0);if($signed(cutoff)!=0 || active)$fatal(1,"cutoff release");
        command(8'h31,64'h0040152000000003);pressed=32'h10801009;repeat(5)@(negedge clk);
        point(1,512,0);if(played!=0)$fatal(1,"touchdown sounded");
        point(1,512,1023);repeat(8)@(negedge clk);if(played!==32'h10801008)$fatal(1,"four rows/rightmost %h",played);
        delivered=played;repeat(140)@(negedge clk);keys_idle=0;
        point(1,512,0);repeat(10)@(negedge clk);if(played!=0)$fatal(1,"retrigger needs release");
        delivered=0;repeat(20)@(negedge clk);if(played!=0)$fatal(1,"in-flight transaction ignored");
        keys_idle=1;repeat(8)@(negedge clk);if(played!==32'h10801008)$fatal(1,"pending row lost");
        delivered=played;pressed=0;repeat(8)@(negedge clk);if(played!=0)$fatal(1,"key release stuck");delivered=0;
        repeat(410)@(negedge clk);pressed=8;point(1,512,1023);if(played!=0)$fatal(1,"stale jump plucked");
        error=1;repeat(8)@(negedge clk);error=0;point(1,512,0);if(played!=0)$fatal(1,"error recovery plucked");
        command(8'h31,64'h0040152000000013);repeat(5)@(negedge clk);
        point(1,512,0);if(played!=0)$fatal(1,"orientation edit caused a false pluck");
        point(1,512,1023);repeat(8)@(negedge clk);if(played!=8)$fatal(1,"flipped orientation did not resume crossings");
        delivered=played;
        @(negedge clk);next_mode=1;@(negedge clk);next_mode=0;repeat(5)@(negedge clk);
        if(mode!=0 || played!=0)$fatal(1,"mode switch resounded held key");pressed=0;repeat(3)@(negedge clk);pressed=8;repeat(3)@(negedge clk);if(played!=8)$fatal(1,"normal keyboard did not resume");
        command(8'h31,64'h00ff152000000001);if(response[135:128]!=5 || mode!=0)$fatal(1,"invalid config changed mode");
        command(8'h31,64'h0040152000000000);
        for(n=0;n<24;n=n+1)begin
            @(negedge clk);x={10'd1023,10'd0};y=0;touch=2;update=2;
            @(negedge clk);update=0;repeat(50)@(negedge clk);
        end
        if(gain<81800)$fatal(1,"right pad continuous modulation missing");
        for(n=0;n<24;n=n+1)begin
            @(negedge clk);x={10'd1023,10'd0};y={10'd0,10'd1023};touch=3;update=3;
            @(negedge clk);update=0;repeat(50)@(negedge clk);
        end
        if(gain>49300)$fatal(1,"left pad priority missing");
        $display("PASS touch performance: gain/pitch/cutoff, neutral return, four rows, retrigger ACK, stale/error, mode, invalid config");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
