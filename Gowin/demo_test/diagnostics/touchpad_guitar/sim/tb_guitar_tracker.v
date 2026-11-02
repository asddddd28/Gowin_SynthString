`timescale 1ns / 1ps
module tb_guitar_tracker;
reg clk=0,rstn=0;
always #10 clk=~clk;
reg [31:0] milliseconds=0;
reg [335:0] raw=0;
reg [15:0] sequence_number=0;
reg [7:0] error=0;
wire event_valid;
wire [5:0] mask;
wire [3:0] flags;
wire [9:0] x,y;
wire [15:0] sample_sequence;
wire [31:0] event_time;
integer events=0,k;
reg [5:0] last_mask;
GuitarTracker dut(clk,rstn,milliseconds,raw,sequence_number,error,event_valid,mask,flags,x,y,sample_sequence,event_time);
always @(posedge clk) if(event_valid) begin events=events+1; last_mask=mask; end
task sample;
    input [11:0] touch;
    input [31:0] stamp;
    input [5:0] expected;
    integer previous;
    begin
        previous=events;
        @(negedge clk);
        raw[335:328]=touch[7:0]; raw[327:320]={4'b0,touch[11:8]};
        milliseconds=stamp; sequence_number=sequence_number+1'b1;
        repeat(70) @(negedge clk);
        if(expected==0 && events!=previous) $fatal(1,"Unexpected pluck at %d",stamp);
        if(expected!=0 && (events!=previous+1 || last_mask!=expected))
            $fatal(1,"Missed crossing at %d expected %h got %h events %d/%d x=%d y=%d",stamp,expected,last_mask,events,previous,x,y);
    end
endtask
initial begin
    for(k=0;k<12;k=k+1) begin
        raw[303-k*16 -: 8]=8'hbc; raw[295-k*16 -: 8]=2; raw[95-k*8 -: 8]=180;
    end
    #100;rstn=1;
    sample(12'h101,0,0);
    if(x!=102 || y!=512) $fatal(1,"Centroid / byte order invalid");
    sample(12'h110,4,6'b000111);
    sample(12'h110,8,0);
    sample(12'h101,20,6'b000111);
    if(flags[2]!=0) $fatal(1,"Reverse direction incorrect");
    sample(0,21,0);sample(12'h110,24,0);
    sample(12'h110,70,0);sample(12'h101,74,7);
    sample(12'h105,90,0);sample(12'h110,94,0);
    error=1;repeat(2) @(negedge clk);error=0;
    sample(12'h101,110,0);
    sample(12'h021,114,6'b001000);
    sample(12'h801,130,6'b111000);
    if(y!=951) $fatal(1,"Column division incorrect");
    // Adjacent equally weighted electrodes surround the middle string: hysteresis must suppress jitter.
    sample(0,150,0);sample(12'h106,154,0);sample(12'h10c,158,2);
    $display("PASS hardware centroid, multi-string, reverse, dwell, lift, timeout, fault, disjoint contacts, both axes");
    $finish;
end
initial begin #1000000;$fatal(1,"Watchdog");end
endmodule
