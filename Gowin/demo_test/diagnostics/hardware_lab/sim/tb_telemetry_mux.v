`timescale 1ns / 1ps
// 饱和五路流：检验整行不交错、两优先流不饿死三普通流。
module tb_telemetry_mux;
reg clk=0,rstn=0;
always #10 clk=~clk;
reg [4:0] second_byte=0;
wire [39:0] data;
wire [4:0] ready;
wire tx;
integer n,bit_index,frames=0,which=0,urgent_run=0;
integer counts [0:4];
reg [7:0] received;
reg newline=0;
genvar channel;
generate for(channel=0;channel<5;channel=channel+1) begin: streams
    assign data[channel*8 +: 8]=second_byte[channel] ? 8'd10 : 8'd65+channel;
end endgenerate
TelemetryMux #(.C_BAUD(8)) dut(clk,rstn,5'b11111,data,5'b01001,ready,tx);
always @(posedge clk) if(rstn) for(n=0;n<5;n=n+1) if(ready[n]) second_byte[n]<=!second_byte[n];
initial begin
    for(n=0;n<5;n=n+1)counts[n]=0;
    #100;rstn=1;
end
initial forever begin
    @(negedge tx);#240;
    for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin received[bit_index]=tx;#160;end
    if(tx!==1) $fatal(1,"UART stop");
    if(!newline) begin
        if(received<65 || received>69)$fatal(1,"Frame prefix");
        which=received-65;newline=1;
    end else begin
        if(received!=10)$fatal(1,"Interleaved frame");
        newline=0;counts[which]=counts[which]+1;frames=frames+1;
        if(which==0 || which==3)urgent_run=urgent_run+1;else urgent_run=0;
        if(urgent_run>3)$fatal(1,"Priority fairness violated");
        if(frames==64)begin
            for(n=0;n<5;n=n+1)if(counts[n]<5)$fatal(1,"Starved source%d",n);
            $display("PASS five streams saturated: atomic frames, max3 priority, all sources progress");$finish;
        end
    end
end
initial begin #10000000;$fatal(1,"Watchdog");end
endmodule
