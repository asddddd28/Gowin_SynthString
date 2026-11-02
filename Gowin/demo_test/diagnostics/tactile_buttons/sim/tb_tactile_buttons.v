`timescale 1ns / 1ps
// Self-checking bounce/concurrency/reset tests plus UART bytes for independent CRC checking.
module tb_tactile_buttons;
    reg clk=0;
    reg resetn=0;
    reg [5:0] switches=0;
    wire [5:0] raw,pressed;
    wire [95:0] presses,releases,edges;
    wire tx;
    reg [5:0] report_raw=6'h15;
    reg [5:0] report_pressed=6'h0a;
    integer channel,step,bit_index,packets=0;
    integer output_file;
    reg [7:0] received;
    genvar idx;
    always #10 clk=~clk;
    generate
        for(idx=0;idx<6;idx=idx+1) begin:gen_inputs
            TactileInput #(.C_STABLE_CYCLES(5)) Input_Inst(
                .i_clk(clk),.i_rstn(resetn),.i_switch(switches[idx]),
                .o_raw(raw[idx]),.o_pressed(pressed[idx]),
                .o_presses(presses[95-idx*16 -:16]),.o_releases(releases[95-idx*16 -:16]),
                .o_edges(edges[95-idx*16 -:16]));
        end
    endgenerate
    TactileReport #(.C_REPORT_CYCLES(10000),.C_BAUD_CYCLES(8)) Report_Inst(
        .i_clk(clk),.i_rstn(resetn),.i_raw(report_raw),.i_pressed(report_pressed),
        .i_presses(96'h000100020003000400050006),.i_releases(96'h000600050004000300020001),
        .i_edges(96'h000700080009000a000bffff),.o_tx(tx));

    // Monitor the actual 8N1 serial wire, sampling in the center of each bit.
    initial begin
        output_file=$fopen("uart.bin","wb");
        if(output_file==0) $fatal(1,"Cannot create UART evidence");
        wait(resetn);
        forever begin
            @(negedge tx);
            #240;
            for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
                received[bit_index]=tx;
                #160;
            end
            if(tx!==1'b1) $fatal(1,"UART stop bit invalid");
            $fwrite(output_file,"%c",received);
            if(received==10) begin
                packets=packets+1;
                if(packets==3) begin
                    $fclose(output_file);
                    $display("PASS three physical UART frames emitted for independent CRC/snapshot verification");
                    $finish;
                end
            end
        end
    end
    // Change the source during transmission; the first frame must retain its snapshot.
    initial begin
        wait(Report_Inst.state_current==2);
        @(negedge clk);report_raw=6'h3f;report_pressed=6'h3f;
    end
    initial begin
        repeat(8) @(negedge clk);resetn=1;
        repeat(10) @(negedge clk);
        for(step=0;step<4;step=step+1) begin
            switches=6'h3f;repeat(2) @(negedge clk);
            switches=0;repeat(3) @(negedge clk);
        end
        repeat(10) @(negedge clk);
        if(pressed!==0 || presses!==0 || releases!==0) $fatal(1,"Bounce created a press");
        for(channel=0;channel<6;channel=channel+1) begin
            switches=1<<channel;repeat(10) @(negedge clk);
            if(pressed!==(1<<channel)) $fatal(1,"Channel mapping mismatch");
            if(presses[95-channel*16 -:16]!==1) $fatal(1,"Missing single press");
            // Release bounce shorter than the stable window must preserve pressed state.
            switches=0;repeat(2) @(negedge clk);
            switches=1<<channel;repeat(10) @(negedge clk);
            if(pressed!==(1<<channel) || presses[95-channel*16 -:16]!==1) $fatal(1,"Release bounce repeated press");
            switches=0;repeat(10) @(negedge clk);
            if(pressed!==0 || releases[95-channel*16 -:16]!==1) $fatal(1,"Missing release");
        end
        switches=6'h3f;repeat(40) @(negedge clk);
        if(pressed!==6'h3f || presses!==96'h000200020002000200020002) $fatal(1,"Simultaneous/held inputs failed");
        switches=0;repeat(10) @(negedge clk);
        if(releases!==96'h000200020002000200020002) $fatal(1,"Simultaneous release failed");
        // Accelerate the documented modulo wrap boundary without millions of synthetic clicks.
        force gen_inputs[0].Input_Inst.cnt_presses_o=16'hffff;
        @(negedge clk);release gen_inputs[0].Input_Inst.cnt_presses_o;
        switches=1;repeat(10) @(negedge clk);
        if(presses[95:80]!==0) $fatal(1,"Press counter failed to wrap");
        resetn=0;switches=6'h3f;repeat(5) @(negedge clk);resetn=1;
        repeat(15) @(negedge clk);
        if(pressed!==6'h3f || presses!==96'h000100010001000100010001 || releases!==0) $fatal(1,"Reset-held behavior failed");
        $display("PASS debounce both edges, six channel mapping, concurrency, hold, counter wrap, reset-held");
    end
    initial begin #3000000;$fatal(1,"Timeout");end
endmodule
