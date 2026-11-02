`timescale 1ns/1ps
module tb_dx_operator(output o_done);
    reg clk=0,rstn=0,valid=0,ready=0,done=0;
    reg [671:0] data=0;
    reg [31:0] tag=0;
    wire accept,result_valid,wave_ready;
    wire [159:0] result;
    wire [31:0] result_tag;
    reg [159:0] expected,held;
    integer fd,code,n,latency,max_latency=0;
    assign o_done=done;
    always #10 clk=!clk;
    AxisFmOperator Dut(.i_axis_aclk(clk),.i_axis_arstn(rstn),.i_s_axis_tdata(data),.i_s_axis_tuser(tag),
        .i_s_axis_tvalid(valid),.o_s_axis_tready(accept),.o_m_axis_tdata(result),.o_m_axis_tuser(result_tag),
        .o_m_axis_tvalid(result_valid),.i_m_axis_tready(ready),.i_wave_write(1'b0),.i_wave_address(11'd0),.i_wave_data(32'd0),.o_wave_ready(wave_ready));
    initial begin
        repeat(4) @(negedge clk);rstn=1;
        fd=$fopen("vectors/dx_operator.txt","r");if(!fd)$fatal(1,"missing vectors");
        for(n=0;n<1600;n=n+1) begin
            @(negedge clk);code=$fscanf(fd,"%h %h\n",data,expected);tag=n;valid=1;
            if(code!=2)$fatal(1,"vector format");
            @(posedge clk);while(!accept)@(posedge clk);
            @(negedge clk);valid=0;latency=1;
            while(!result_valid)begin @(negedge clk);latency=latency+1;if(latency>12)$fatal(1,"deadline");end
            if(latency>max_latency)max_latency=latency;
            if(result!==expected || result_tag!==tag)$fatal(1,"vector %0d expected %h got %h",n,expected,result);
            held=result;
            repeat(n%7)begin @(negedge clk);if(!result_valid || result!==held || result_tag!==tag)$fatal(1,"unstable stall");end
            ready=1;@(negedge clk);ready=0;
        end
        valid=1;@(negedge clk);valid=0;repeat(2)@(negedge clk);rstn=0;
        repeat(2)@(negedge clk);rstn=1;
        repeat(20)begin @(negedge clk);if(result_valid)$fatal(1,"reset ghost");end
        $display("PASS dx_operator vectors=1600 max_latency=%0d stalls=PASS reset=PASS",max_latency);
        done=1;$finish;
    end
    initial begin #10000000;$fatal(1,"watchdog");end
endmodule
