`timescale 1ns/1ps
module tb_dx_envelope(output o_done);
    reg clk=0,rstn=0,valid=0,ready=0,done=0;
    reg [383:0] data=0;
    reg [31:0] tag=0;
    wire accept,result_valid,wave_ready;
    wire [95:0] result;
    wire [31:0] result_tag;
    reg [95:0] expected,held;
    integer fd,code,n,latency,max_latency=0,reset_stage;
    assign o_done=done;
    always #10 clk=!clk;
    AxisDxEnvelope Dut(.i_axis_aclk(clk),.i_axis_arstn(rstn),.i_s_axis_tdata(data),.i_s_axis_tuser(tag),
        .i_s_axis_tvalid(valid),.o_s_axis_tready(accept),.o_m_axis_tdata(result),.o_m_axis_tuser(result_tag),
        .o_m_axis_tvalid(result_valid),.i_m_axis_tready(ready));
    initial begin
        repeat(4) @(negedge clk);rstn=1;
        fd=$fopen("vectors/dx_envelope.txt","r");if(!fd)$fatal(1,"missing vectors");
        for(n=0;n<10096;n=n+1) begin
            @(negedge clk);code=$fscanf(fd,"%h %h\n",data,expected);tag=n;valid=1;
            if(code!=2)$fatal(1,"vector format");
            @(posedge clk);while(!accept)@(posedge clk);
            @(negedge clk);valid=0;latency=1;
            while(!result_valid)begin @(negedge clk);latency=latency+1;if(latency>12)$fatal(1,"deadline");end
            if(latency>max_latency)max_latency=latency;
            if(latency!=7)$fatal(1,"unexpected pipeline latency %0d",latency);
            if(result!==expected || result_tag!==tag)$fatal(1,"vector %0d expected %h got %h",n,expected,result);
            held=result;
            repeat(n%7)begin @(negedge clk);if(!result_valid || result!==held || result_tag!==tag)$fatal(1,"unstable stall");end
            ready=1;@(negedge clk);ready=0;
        end
        // 覆盖每个计算拍及结果等待拍；复位后重发同一参考请求，检查旧状态不会泄漏。
        for(reset_stage=1;reset_stage<=7;reset_stage=reset_stage+1)begin
            @(negedge clk);valid=1;
            @(posedge clk);if(!accept)$fatal(1,"reset probe refused");
            @(negedge clk);valid=0;
            repeat(reset_stage-1)@(negedge clk);rstn=0;
            repeat(2)@(negedge clk);rstn=1;
            repeat(20)begin @(negedge clk);if(result_valid)$fatal(1,"reset ghost");end
            valid=1;@(posedge clk);if(!accept)$fatal(1,"post-reset request refused");
            @(negedge clk);valid=0;
            repeat(7-1)@(negedge clk);
            if(!result_valid || result!==expected || result_tag!==tag)$fatal(1,"post-reset result mismatch");
            ready=1;@(negedge clk);ready=0;
        end
        $display("PASS dx_envelope vectors=10096 max_latency=%0d stalls=PASS reset_stages=7",max_latency);
        done=1;$finish;
    end
    initial begin #10000000;$fatal(1,"watchdog");end
endmodule
