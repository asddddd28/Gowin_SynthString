`timescale 1ns / 1ps
// Numerical oracle test / 数值比对. Contract: spec/tb_compact_delay_spec.md.
module tb_compact_delay(output o_done);
    reg completed=0;
    assign o_done=completed;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0;
    reg [63:0] data=0;
    reg [31:0] tag=0;
    reg valid=0;
    wire ready;
    wire [63:0] result;
    wire [31:0] result_tag;
    wire result_valid;
    reg result_ready=0;
    reg [159:0] config_data=0;
    reg clear=0;
    wire clipped;
    integer file_handle, scanned, frame=0, cycles, maximum=0, stalls=0, clip_count=0;
    integer request_clear, expected_clip;
    reg [63:0] expected;
    reg [64:0] held;
    AxisStereoDelay #(.C_DELAY_ADDR_BITS(13)) Dut_Inst(
        .i_axis_aclk(clk),.i_axis_arstn(resetn),.i_s_axis_tdata(data),.i_s_axis_tuser(tag),
        .i_s_axis_tvalid(valid),.o_s_axis_tready(ready),.o_m_axis_tdata(result),.o_m_axis_tuser(result_tag),
        .o_m_axis_tvalid(result_valid),.i_m_axis_tready(result_ready),.i_config(config_data[159:0]),
        .i_clear(clear),.o_clipped(clipped)
    );
    initial begin
        repeat(4) @(negedge clk);
        resetn=1;
        file_handle=$fopen("sim/compact_delay.txt","r");
        if (!file_handle) $fatal(1,"missing oracle vectors");
        while (!$feof(file_handle)) begin
            @(negedge clk);
            scanned=$fscanf(file_handle,"%h %h %h %h %h\n",request_clear,config_data,data,expected,expected_clip);
            if (scanned!=5) $fatal(1,"bad oracle row");
            clear=request_clear;
            @(negedge clk);
            clear=0;
            tag=frame;
            valid=1;
            @(posedge clk);
            while (!ready) @(posedge clk);
            @(negedge clk);
            valid=0;
            // Changing config while busy must not affect the captured frame.
            config_data=0;
            cycles=0;
            while (!result_valid) begin
                @(negedge clk);
                cycles=cycles+1;
                if (cycles>150) $fatal(1,"effect deadline");
            end
            if (cycles>maximum) maximum=cycles;
            if (result!==expected || result_tag!==frame || clipped!==expected_clip[0]) begin
                $display("dry=%h/%h wet=%h mix=%h/%h",Dut_Inst.reg_dry_left,Dut_Inst.reg_dry_right,Dut_Inst.reg_wet,Dut_Inst.reg_mix_left,Dut_Inst.reg_mix_right);
                $fatal(1,"delay frame %0d got %h/%b expected %h/%b",frame,result,clipped,expected,expected_clip[0]);
            end
            held={clipped,result};
            if (frame%31==0) repeat(4) begin
                @(negedge clk);
                if (!result_valid || {clipped,result}!==held || result_tag!==frame || ready)
                    $fatal(1,"stalled output mutated");
                stalls=stalls+1;
            end
            clip_count=clip_count+clipped;
            result_ready=1;
            @(negedge clk);
            result_ready=0;
            frame=frame+1;
        end
        $fclose(file_handle);
        // Cancel an in-flight request, then prove RAM history cannot escape reset.
        config_data=0;
        config_data[31:0]=65536;
        config_data[63:32]=65536;
        data=64'h0200000002000000;
        valid=1;
        @(negedge clk);
        valid=0;
        repeat(3) @(negedge clk);
        resetn=0;
        @(negedge clk);
        resetn=1;
        repeat(3) @(negedge clk);
        if (result_valid || !ready) $fatal(1,"reset did not cancel");
        data=0;
        valid=1;
        @(negedge clk);
        valid=0;
        while (!result_valid) @(negedge clk);
        if (result!==0) $fatal(1,"reset leaked stale history");
        completed=1;
        $display("PASS tb_compact_delay frames=%0d max_compute_cycles=%0d stalls=%0d clips=%0d",frame,maximum,stalls,clip_count);
        $finish;
    end
    initial begin #500000000; $fatal(1,"watchdog"); end
endmodule
