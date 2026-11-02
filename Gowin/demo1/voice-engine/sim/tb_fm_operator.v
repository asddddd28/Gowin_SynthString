`timescale 1ns/1ps
module tb_fm_operator(output o_done);
    reg clk=0, rstn=0, valid=0, ready=0, done=0;
    reg [671:0] data=0;
    reg [31:0] tag=0;
    reg wave_write=0;
    reg [10:0] wave_address=0;
    reg [31:0] wave_data=0;
    wire wave_ready;
    wire accept, result_valid;
    wire [159:0] result;
    wire [31:0] result_tag;
    reg [159:0] expected, held;
    integer fd, code, n, waits, latency, min_latency=999, max_latency=0;
    assign o_done=done;
    always #10 clk=!clk;
    AxisFmOperator Dut(.i_axis_aclk(clk),.i_axis_arstn(rstn),
        .i_s_axis_tdata(data),.i_s_axis_tuser(tag),.i_s_axis_tvalid(valid),.o_s_axis_tready(accept),
        .o_m_axis_tdata(result),.o_m_axis_tuser(result_tag),.o_m_axis_tvalid(result_valid),.i_m_axis_tready(ready),
        .i_wave_write(wave_write),.i_wave_address(wave_address),.i_wave_data(wave_data),.o_wave_ready(wave_ready));
    initial begin
        repeat(4) @(negedge clk); rstn=1;
        fd=$fopen("vectors/fm_operator.txt","r");
        if(!fd) $fatal(1,"missing vectors");
        for(n=0;n<2400;n=n+1) begin
            @(negedge clk);
            code=$fscanf(fd,"%h %h\n",data,expected);
            if(code!=2) $fatal(1,"bad vector %0d",n);
            tag=n; valid=1; wave_write=(n==0);
            @(posedge clk); while(!accept) @(posedge clk);
            @(negedge clk); valid=0; wave_write=0;
            latency=1;
            while(!result_valid) begin @(negedge clk); latency=latency+1; if(latency>30) $fatal(1,"operator timeout"); end
            if(result!==expected || result_tag!==n) $fatal(1,"vector %0d expected %h got %h tag %h",n,expected,result,result_tag);
            if(latency<min_latency) min_latency=latency;
            if(latency>max_latency) max_latency=latency;
            held=result;
            repeat(n%11) begin
                @(negedge clk);
                if(!result_valid || result!==held || result_tag!==n) $fatal(1,"unstable stalled result");
            end
            ready=1; @(negedge clk); ready=0;
        end
        // Cancel an in-flight operation, then ensure no ghost completion.
        valid=1; @(negedge clk); valid=0; repeat(3) @(negedge clk);
        rstn=0; repeat(2) @(negedge clk); rstn=1;
        repeat(20) begin @(negedge clk); if(result_valid) $fatal(1,"reset ghost"); end
        // Replace both frames, then independently check interpolation and morph.
        fd=$fopen("vectors/wave_upload.txt","r");
        for(n=0;n<2048;n=n+1) begin
            @(negedge clk); wave_write=1; wave_address=n;
            code=$fscanf(fd,"%h\n",wave_data);
            if(code!=1 || !wave_ready) $fatal(1,"wave write not accepted");
        end
        @(negedge clk); wave_write=0; $fclose(fd);
        fd=$fopen("vectors/fm_wave_uploaded.txt","r");
        for(n=0;n<256;n=n+1) begin
            @(negedge clk); code=$fscanf(fd,"%h %h\n",data,expected); tag=n+2400; valid=1;
            if(code!=2) $fatal(1,"uploaded waveform vector");
            @(posedge clk); while(!accept) @(posedge clk);
            @(negedge clk); valid=0;
            while(!result_valid) @(negedge clk);
            if(result!==expected || result_tag!==n+2400) $fatal(1,"uploaded waveform %0d expected %h got %h",n,expected,result);
            ready=1; @(negedge clk); ready=0;
        end
        $display("PASS fm_operator vectors=2656 latency=%0d..%0d stalled_outputs=2400 reset_cancel=1 uploaded_wave_points=2048",min_latency,max_latency);
        done=1; $finish;
    end
    initial begin #10000000; $fatal(1,"watchdog"); end
endmodule
