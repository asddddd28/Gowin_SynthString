`timescale 1ns/1ps
module tb_lfo_step(output o_done);
    reg clk=0,rstn=0,valid=0,ready=0,done=0;
    reg [255:0] data=0,requests[0:3559];
    reg [159:0] expected[0:3559],held;
    reg [31:0] tag=0,rng=32'h4c464f17,held_tag;
    wire source_ready,result_valid;
    wire [159:0] result;
    wire [31:0] result_tag;
    integer sent=0,received=0,cycle=0,fd,code,n,stalls=0,last_accept=-1,min_ii=999;
    integer accepted_at[0:3559],min_latency=999;
    reg stalled=0,input_stalled=0,scoreboard=1;
    assign o_done=done;
    always #10 clk=!clk;
    AxisLfoStep Dut(.i_axis_aclk(clk),.i_axis_arstn(rstn),.i_s_axis_tdata(data),.i_s_axis_tuser(tag),
        .i_s_axis_tvalid(valid),.o_s_axis_tready(source_ready),.o_m_axis_tdata(result),.o_m_axis_tuser(result_tag),
        .o_m_axis_tvalid(result_valid),.i_m_axis_tready(ready));
    always @(posedge clk) begin
        if(rstn && scoreboard) begin
            cycle=cycle+1;
            if(stalled && (!result_valid || result!==held || result_tag!==held_tag)) $fatal(1,"LFO output changed under stall");
            stalled=result_valid&&!ready; held=result;held_tag=result_tag;
            input_stalled=valid&&!source_ready;
            if(stalled) stalls=stalls+1;
            if(valid&&source_ready) begin
                accepted_at[sent]=cycle;
                if(last_accept>=0 && cycle-last_accept<min_ii) min_ii=cycle-last_accept;
                last_accept=cycle;sent=sent+1;
            end
            if(result_valid&&ready) begin
                if(result!==expected[received] || result_tag!==received) $fatal(1,"LFO %0d expected %h got %h tag=%h",received,expected[received],result,result_tag);
                if(cycle-accepted_at[received]<min_latency) min_latency=cycle-accepted_at[received];
                received=received+1;
            end
        end
    end
    initial begin
        fd=$fopen("vectors/lfo_step.txt","r");if(!fd) $fatal(1,"missing LFO vectors");
        for(n=0;n<3560;n=n+1) begin code=$fscanf(fd,"%h %h\n",requests[n],expected[n]);if(code!=2) $fatal(1,"vector format");end
        repeat(4) @(negedge clk);rstn=1;
        while(received<3560) begin
            @(negedge clk);
            rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
            ready=cycle<64 ? 1'b1 : rng[0]&&((cycle%97)<70);
            if(!input_stalled) begin
                valid=sent<3560 && (cycle<64 || rng[3]);
                if(valid) begin data=requests[sent];tag=sent;end
            end
        end
        @(negedge clk);valid=0;ready=1;scoreboard=0;
        if(min_latency!=5 || min_ii!=1 || stalls==0) $fatal(1,"LFO throughput coverage");
        repeat(4) @(negedge clk);
        valid=1;data=requests[0];tag=32'hbad;
        repeat(3) @(negedge clk);
        valid=0;rstn=0;repeat(2) @(negedge clk);rstn=1;
        repeat(12) begin @(negedge clk);if(result_valid) $fatal(1,"reset ghost LFO result");end
        $display("PASS lfo_step vectors=3560 min_latency=%0d II=%0d stalled_cycles=%0d reset_cancelled=3",min_latency,min_ii,stalls);
        done=1;$finish;
    end
    initial begin #20000000;$fatal(1,"LFO watchdog");end
endmodule
