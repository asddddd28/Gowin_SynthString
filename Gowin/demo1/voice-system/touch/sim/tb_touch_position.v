`timescale 1ns / 1ps
module tb_touch_position;
    reg clk=0,rstn=0;always #10 clk=~clk;
    reg [335:0] raw=0;reg [15:0] sequence=0;reg [7:0] error=0;
    wire update,touch;wire [9:0] x,y;integer n;
    TouchPosition dut(.i_clk(clk),.i_rstn(rstn),.i_raw(raw),.i_sequence(sequence),.i_error(error),.o_update(update),.o_touch(touch),.o_x(x),.o_y(y));
    task sample;input [11:0] mask;
        begin
            @(negedge clk);raw=0;raw[335:328]=mask[7:0];raw[323:320]=mask[11:8];
            for(n=0;n<12;n=n+1)begin raw[303-n*16-:8]=8'd180;raw[295-n*16-:8]=8'd2;raw[95-n*8-:8]=8'd200;end
            sequence=sequence+1;wait(update);@(negedge clk);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rstn=1;
        sample(12'h021);if(!touch || x!=0 || y!=0)$fatal(1,"origin %d %d",x,y);
        sample(12'h810);if(!touch || x!=1023 || y!=1023)$fatal(1,"far corner %d %d",x,y);
        sample(12'h084);if(!touch || x!=512 || y!=341)$fatal(1,"axis mapping %d %d",x,y);
        sample(12'h0c6);if(!touch || x!=384 || y!=256)$fatal(1,"weighted pair %d %d",x,y);
        sample(12'h085);if(touch)$fatal(1,"split contacts accepted");
        sample(0);if(touch)$fatal(1,"no touch");
        error=1;repeat(5)@(negedge clk);if(touch)$fatal(1,"error invalidation");
        $display("PASS touch position: endpoints, orientation, centroid, disjoint rejection, release/error");$finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
