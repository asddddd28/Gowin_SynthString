`timescale 1ns / 1ps
module tb_guitar_queue;
reg clk=0,rstn=0,push=0,pop=0;
reg [95:0] data=0;
wire empty;
wire [95:0] head;
wire [15:0] dropped;
integer k;
always #10 clk=~clk;
GuitarEventQueue dut(clk,rstn,push,data,pop,empty,head,dropped);
initial begin
    #100;rstn=1;
    for(k=0;k<16;k=k+1) begin @(negedge clk);push=1;data=k; end
    @(negedge clk);data=99;
    @(negedge clk);push=0;
    if(dropped!=1) $fatal(1,"Full queue failed to count overflow");
    if(head!=0) $fatal(1,"FIFO order broken");
    push=1;pop=1;data=16;
    @(negedge clk);push=0;pop=0;
    if(dropped!=1 || head!=1) $fatal(1,"Concurrent full push/pop failed");
    for(k=1;k<=16;k=k+1) begin
        if(head!=k) $fatal(1,"FIFO item mismatch %d",k);
        pop=1;@(negedge clk);
    end
    pop=0;
    if(!empty) $fatal(1,"FIFO not empty");
    $display("PASS FIFO order, full overflow, simultaneous push/pop");$finish;
end
endmodule
