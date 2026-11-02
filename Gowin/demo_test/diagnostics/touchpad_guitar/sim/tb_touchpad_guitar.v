`timescale 1ns / 1ps
// 行为从机检查真实 SCL/SDA 边沿，独立于主机内部字节握手。
module MprBehavior #(parameter [6:0] ADDRESS=7'h5a)(input scl,inout sda,input enable,output reg [31:0] reads=0);
reg drive=0,active=0,reading=0,selected=0;
reg [7:0] memory[0:255];
reg [7:0] incoming=0,pointer=0,outgoing=0;
integer count=0,stage=0,k;
reg master_nack=0;
assign sda=drive ? 1'b0 : 1'bz;
initial begin
    for(k=0;k<256;k=k+1) memory[k]=0;
    memory[8'h5c]=8'h10; memory[8'h5d]=8'h24;
    memory[0]=8'h21;
    for(k=0;k<12;k=k+1) begin
        memory[4+k*2]=(700+k)&255;
        memory[5+k*2]=(700+k)>>8;
        memory[30+k]=180+k;
    end
end
always @(negedge sda) if(scl===1'b1) begin
    active=1; reading=0; selected=0; count=0; stage=0; incoming=0;
end
always @(posedge sda) if(scl===1'b1) begin active=0; drive=0; end
always @(posedge scl) if(active) begin
    count=count+1;
    if(count<=8 && !reading) incoming={incoming[6:0],sda};
    if(count==9 && reading) master_nack=sda;
end
always @(negedge scl) if(active) begin
    if(reading) begin
        if(count<8) drive=!outgoing[7-count];
        else if(count==8) drive=0;
        else begin
            reads=reads+1;
            if(master_nack) begin reading=0; selected=0; drive=0; end
            else begin pointer=pointer+1; outgoing=memory[pointer]; drive=!outgoing[7]; end
            count=0;
        end
    end else begin
        if(count==8) begin
            if(stage==0) selected=enable && incoming[7:1]==ADDRESS;
            drive=selected && enable;
        end else if(count==9) begin
            drive=0;
            if(selected && enable) begin
                if(stage==0) begin
                    if(incoming[0]) begin reading=1; outgoing=memory[pointer]; drive=!outgoing[7]; end
                    else stage=1;
                end else if(stage==1) begin pointer=incoming; stage=2; end
                else begin memory[pointer]=incoming; pointer=pointer+1; end
            end
            count=0; incoming=0;
        end
    end
end
endmodule

module tb_touchpad_guitar;
reg clk=0,rstn=0;
always #10 clk=~clk;
tri1 [1:0] scl,sda;
reg right_enable=1,hold_right=0;
assign scl[1]=hold_right ? 1'b0:1'bz;
wire tx;
wire [31:0] reads_left,reads_right;
TouchpadGuitar #(.C_DIVIDER(4),.C_BAUD(8),.C_BOOT(100),.C_RETRY(5000),
    .C_RESET_WAIT(200),.C_POLL(10000),.C_TIMEOUT(100000),.C_REPORT(30000)) dut (
    .i_clk(clk),.i_rstn(rstn),.i_irq(2'b10),.io_scl(scl),.io_sda(sda),.o_uart_tx(tx)
);
MprBehavior #(.ADDRESS(7'h5a)) left_sensor(scl[0],sda[0],1'b1,reads_left);
MprBehavior #(.ADDRESS(7'h5c)) right_sensor(scl[1],sda[1],right_enable,reads_right);
integer output_file,bit_index,frames=0;
reg [7:0] received;
reg [15:0] left_previous;
initial output_file=$fopen("uart.bin","wb");
initial forever begin
    @(negedge tx); #240;
    for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
        received[bit_index]=tx; #160;
    end
    if(tx!==1'b1) $fatal(1,"UART stop bit invalid");
    $fwrite(output_file,"%c",received);
    if(received==10) frames=frames+1;
end
initial begin
    #200 rstn=1;
    wait(dut.left_sequence>=3 && dut.right_sequence>=3);
    if(dut.left_error!=0 || dut.right_error!=0) $fatal(1,"Sensor did not configure");
    if(dut.right_address!=7'h5c) $fatal(1,"Address scan failed");
    if(left_sensor.memory[8'h41]!=12 || left_sensor.memory[8'h58]!=6 || left_sensor.memory[8'h5e]!=8'h8c) $fatal(1,"Configuration invalid");
    if(dut.left_raw[335:328]!=8'h21 || dut.left_raw[303:288]!=16'hbc02 || dut.left_raw[95:88]!=180) $fatal(1,"Burst byte order invalid");
    $display("PASS dual scan 5A/5C, config/readback, burst bytes");
    left_sensor.memory[0]=8'h10; left_sensor.memory[1]=8'h01;
    right_sensor.memory[0]=8'h10; right_sensor.memory[1]=8'h01;
    #2000000;
    if(dut.left_tracker.x_o!=922 || dut.right_tracker.x_o!=922) $fatal(1,"Position pipeline failed");
    if(dut.left_packet<1 || dut.right_packet<1) $fatal(1,"Event UART not transmitting");
    $display("PASS simultaneous left/right hardware crossings and event UART");
    right_enable=0; left_previous=dut.left_sequence;
    wait(dut.right_error==5 || dut.right_error==1);
    #1000000;
    if(dut.left_sequence<=left_previous || dut.left_error!=0) $fatal(1,"Right NACK blocked left");
    $display("PASS NACK isolation");
    hold_right=1; left_previous=dut.left_sequence;
    wait(dut.right_error==2);
    if(dut.left_sequence<=left_previous) $fatal(1,"Clock stretch blocked left");
    $display("PASS bounded stuck-clock timeout");
    hold_right=0; right_enable=1;
    wait(dut.right_error==0);
    right_sensor.memory[8'h5e]=0;
    wait(dut.right_error==4);
    wait(dut.right_error==0);
    if(right_sensor.memory[8'h5e]!=8'h8c) $fatal(1,"Conversion reset not repaired");
    $display("PASS periodic ECR verification and reconfiguration");
    #1000000;
    if(frames<10) $fatal(1,"Insufficient UART frames");
    $display("PASS recovery; UART frames=%0d",frames);
    $fclose(output_file); $finish;
end
initial begin #200000000; $fatal(1,"Simulation watchdog"); end
endmodule
