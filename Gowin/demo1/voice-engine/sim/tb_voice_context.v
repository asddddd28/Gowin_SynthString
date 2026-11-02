`timescale 1ns/1ps
// Stateful model scoreboard with random stalls, retry races and reset cancellation.
module tb_voice_context(output o_done);
    localparam C_BEATS=3587, C_RESPONSES=3563;
    reg clk=0, rstn=0, main_run=0, completed=0;
    always #10 clk=!clk;
    assign o_done=completed;
    reg [383:0] input_data=0;
    reg [31:0] input_tag=0;
    reg [7:0] input_opcode=0;
    reg input_last=1, input_valid=0, output_ready=0;
    wire input_ready, output_valid, output_last;
    wire [127:0] output_data;
    wire [31:0] output_tag, executed, replayed, rejected, bound;
    wire [7:0] output_opcode;
    AxisVoiceRuntime Dut(
        .i_axis_aclk(clk),.i_axis_arstn(rstn),
        .i_s_axis_tdata(input_data),.i_s_axis_tuser(input_tag),.i_s_axis_tdest(input_opcode),
        .i_s_axis_tlast(input_last),.i_s_axis_tvalid(input_valid),.o_s_axis_tready(input_ready),
        .o_m_axis_tdata(output_data),.o_m_axis_tuser(output_tag),.o_m_axis_tdest(output_opcode),
        .o_m_axis_tlast(output_last),.o_m_axis_tvalid(output_valid),.i_m_axis_tready(output_ready),
        .o_count_executed(executed),.o_count_replayed(replayed),.o_count_rejected(rejected),.o_count_bound(bound)
    );
    reg [383:0] payload [0:C_BEATS-1];
    reg [127:0] expected [0:C_BEATS-1];
    reg [31:0] tags [0:C_BEATS-1];
    reg [7:0] opcodes [0:C_BEATS-1];
    reg lasts [0:C_BEATS-1], wanted [0:C_BEATS-1];
    reg started [0:C_BEATS-1], seen [0:C_BEATS-1];
    reg [168:0] held_value;
    reg held=0, accepted=0;
    reg [31:0] random_state=32'haf410019;
    integer n, fd, code, index;
    integer sent=0, received=0, cycle=0, stalls=0;
    integer last_raw=-10000, minimum_raw_ii=10000;
    reg [383:0] prelude_data;

    task prelude_send;
        input [7:0] operation;
        input [383:0] data;
        begin
            @(negedge clk);
            input_opcode=operation; input_data=data; input_tag=32'hdeadbeef; input_valid=1; input_last=1;
            @(posedge clk); while(!input_ready) @(posedge clk);
            @(negedge clk); input_valid=0;
        end
    endtask

    initial begin
        fd=$fopen("vectors/voice_context.txt","r");
        if(!fd) $fatal(1,"missing context vectors");
        for(n=0;n<C_BEATS;n=n+1)begin
            code=$fscanf(fd,"%h %h %h %h %h %h\n",opcodes[n],lasts[n],tags[n],payload[n],wanted[n],expected[n]);
            if(code!=6) $fatal(1,"vector format at %0d",n);
            started[n]=0; seen[n]=0;
        end
        $fclose(fd);
        repeat(4) @(negedge clk); rstn=1;
        output_ready=1;
        prelude_data=0; prelude_data[351:320]=32'h100;
        prelude_data[63:0]=64'h0000000300000001;
        prelude_send(8'h80,prelude_data);
        @(posedge clk); while(!output_valid) @(posedge clk);
        if(output_data!==0) $fatal(1,"prelude bind failed");
        @(negedge clk); output_ready=0;
        prelude_data[319:0]=0;
        prelude_send(8'h90,prelude_data);
        wait(output_valid);
        repeat(8) @(negedge clk);
        if(executed!=1 || bound!=1 || output_data[63:0]!==64'h0000000400000004)
            $fatal(1,"reset prelude did not commit");
        rstn=0; input_valid=0;
        repeat(4) @(negedge clk);
        if(output_valid || executed || bound || input_ready) $fatal(1,"reset not clearing ownership");
        main_run=1;
        @(negedge clk); rstn=1;
        wait(received==C_RESPONSES);
        repeat(80) @(negedge clk);
        if(sent!=C_BEATS || executed!=2241 || replayed!=384 || rejected!=701 || bound!=65)
            $fatal(1,"counts beats=%0d exec=%0d replay=%0d reject=%0d bind=%0d",sent,executed,replayed,rejected,bound);
        if(minimum_raw_ii!=1 || stalls==0) $fatal(1,"raw bypass/stall coverage missing");
        for(n=0;n<C_BEATS;n=n+1) if(seen[n]!==wanted[n]) $fatal(1,"unresolved tag %0d",n);
        completed=1;
        $display("PASS voice_context beats=%0d responses=%0d executed=%0d replayed=%0d rejected=%0d bound=%0d raw_II=%0d stalls=%0d cycles=%0d",sent,received,executed,replayed,rejected,bound,minimum_raw_ii,stalls,cycle);
        $finish;
    end
    initial begin #10000000; $fatal(1,"context timeout sent=%0d returned=%0d",sent,received); end

    always @(negedge clk)begin
        if(main_run)begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            if(!rstn)begin input_valid=0; output_ready=0; end
            else begin
                output_ready=cycle<240 || (random_state[3] && cycle%197>37);
                if(!input_valid || accepted)begin
                    input_valid=sent<C_BEATS && (cycle<240 || random_state[1]);
                    if(input_valid)begin
                        input_data=payload[sent]; input_tag=tags[sent]; input_opcode=opcodes[sent]; input_last=lasts[sent];
                    end
                end
            end
        end
    end

    always @(posedge clk)begin
        accepted=input_valid&&input_ready;
        if(!rstn)begin held=0; cycle=0; sent=0; received=0; end
        else if(main_run)begin
            cycle=cycle+1;
            if(held && (!output_valid || {output_last,output_opcode,output_tag,output_data}!==held_value))
                $fatal(1,"context completion changed under backpressure");
            held=output_valid&&!output_ready;
            held_value={output_last,output_opcode,output_tag,output_data};
            if(held) stalls=stalls+1;
            if(accepted)begin
                started[sent]=1;
                if(sent<160)begin
                    if(sent>0 && cycle-last_raw<minimum_raw_ii) minimum_raw_ii=cycle-last_raw;
                    last_raw=cycle;
                end
                sent=sent+1;
            end
            if(output_valid&&output_ready)begin
                index=output_tag[23:0];
                if(output_tag[31:24]!==8'hc0 || index>=C_BEATS) $fatal(1,"stale tag %h",output_tag);
                if(!started[index] || seen[index] || !wanted[index] || output_data!==expected[index] || output_opcode!==opcodes[index] || !output_last)
                    $fatal(1,"context mismatch tag=%h op=%h got=%h expected=%h",output_tag,output_opcode,output_data,expected[index]);
                seen[index]=1; received=received+1;
            end
        end
    end
endmodule
