`timescale 1ns / 1ps
module tb_encoder_debug;
reg reg_clk=1'b0;
reg reg_rstn=1'b0;
reg [4:0] reg_a=5'd0;
reg [4:0] reg_b=5'd0;
wire wire_tx;
integer count_line=0;
integer count_byte=0;
integer index_bit;
integer phase_test=0;
reg [7:0] reg_received;
reg [271:0] reg_line;
reg [271:0] reg_expected;
always #10 reg_clk=~reg_clk;
EncoderDebug #(.C_FILTER_CYCLES(16'd8),.C_BAUD_CYCLES(16'd8),.C_REPORT_CYCLES(32'd20000)) dut (
    .i_clk(reg_clk),.i_rstn(reg_rstn),.i_encoder_a(reg_a),.i_encoder_b(reg_b),.o_uart_tx(wire_tx)
);

task set_phase;
    input integer channel;
    input [1:0] value;
    begin
        @(negedge reg_clk);
        reg_a[channel]=value[1]; reg_b[channel]=value[0];
        repeat(40) @(negedge reg_clk);
    end
endtask

task positive_cycle;
    input integer channel;
    begin
        set_phase(channel,2'b01); set_phase(channel,2'b11);
        set_phase(channel,2'b10); set_phase(channel,2'b00);
    end
endtask

// 独立UART接收器逐位检查，再比较完整五路ASCII快照。
initial begin
    forever begin
        @(negedge wire_tx);
        if (reg_rstn) begin
            repeat(4) @(posedge reg_clk);
            #1;
            if(wire_tx!==1'b0) $fatal(1,"UART start bit");
            for(index_bit=0; index_bit<8; index_bit=index_bit+1) begin
                repeat(8) @(posedge reg_clk);
                #1 reg_received[index_bit]=wire_tx;
            end
            repeat(8) @(posedge reg_clk);
            #1;
            if(wire_tx!==1'b1) $fatal(1,"UART stop bit");
            if (phase_test!=1) begin
                reg_line={reg_line[263:0],reg_received};
                count_byte=count_byte+1;
                if(count_byte==34) begin
                    if(phase_test==0) begin
                        case(count_line)
                            0: reg_expected={"E1 A0 F0 Q0008 P0009 N0001 X0000",8'h0d,8'h0a};
                            1: reg_expected={"E2 A0 F0 QFFFC P0000 N0004 X0000",8'h0d,8'h0a};
                            2: reg_expected={"E3 A3 F3 Q0000 P0000 N0000 X0001",8'h0d,8'h0a};
                            3: reg_expected={"E4 A0 F0 Q0004 P0004 N0000 X0000",8'h0d,8'h0a};
                            4: reg_expected={"E5 A0 F0 Q0004 P0004 N0000 X0000",8'h0d,8'h0a};
                            default: $fatal(1,"unexpected line");
                        endcase
                    end else begin
                        reg_expected={"E1 A3 F3 Q0000 P0000 N0000 X0000",8'h0d,8'h0a};
                        reg_expected[263:256]=8'd49+count_line;
                    end
                    if(reg_line!==reg_expected) begin
                        $display("expected %s got %s",reg_expected,reg_line);
                        $fatal(1,"UART snapshot mismatch");
                    end
                    $display("verified %s",reg_line);
                    count_line=count_line+1; count_byte=0;
                end
            end
        end
    end
end

initial begin
    repeat(10) @(negedge reg_clk);
    reg_rstn=1'b1;
    repeat(100) @(negedge reg_clk);
    if(dut.bus_position!==80'd0 || dut.bus_invalid!==80'd0) $fatal(1,"startup fake movement");
    // 毛刺持续两拍，比八拍门槛短，不能成为有效边沿。
    reg_b[0]=1'b1;
    repeat(2) @(negedge reg_clk);
    reg_b[0]=1'b0;
    repeat(40) @(negedge reg_clk);
    if(dut.bus_position!==80'd0) $fatal(1,"glitch accepted");
    positive_cycle(0);
    set_phase(1,2'b10); set_phase(1,2'b11); set_phase(1,2'b01); set_phase(1,2'b00);
    // 单触点往返后继续旋转，净位置应只增加四个边沿。
    set_phase(0,2'b01); set_phase(0,2'b00); positive_cycle(0);
    set_phase(2,2'b11);
    positive_cycle(3); positive_cycle(4);
    wait(count_line==5);
    phase_test=1;
    @(negedge wire_tx);
    repeat(12) @(negedge reg_clk);
    reg_rstn=1'b0;
    reg_a=5'b11111;reg_b=5'b11111;
    #1 if(wire_tx!==1'b1) $fatal(1,"reset did not abort UART");
    repeat(150) @(negedge reg_clk);
    count_line=0;count_byte=0;phase_test=2;
    reg_rstn=1'b1;
    wait(count_line==5);
    $display("PASS: five channels, directions, bounce, glitch, invalid transition, UART, mid-frame reset");
    $finish;
end
initial begin
    #5000000;
    $fatal(1,"test timeout");
end
endmodule
