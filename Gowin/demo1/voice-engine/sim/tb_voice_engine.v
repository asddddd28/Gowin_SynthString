`timescale 1ns/1ps
module tb_voice_engine(output o_done);
    reg clk=0,rstn=0,valid=0,ready=1,tick=0,done=0;
    reg [383:0] data=0;
    reg [31:0] tag=0, seq=0;
    reg [7:0] opcode=0;
    wire command_ready, response_valid, pcm_valid;
    wire [127:0] response;
    wire [31:0] response_tag,frame,overruns,cycles;
    wire [7:0] response_opcode,active;
    wire [63:0] pcm;
    reg [319:0] core [0:5], envelope [0:5];
    reg [127:0] saved_response;
    reg [63:0] expected;
    integer fd,code,n,v,op,elapsed,max_cycles=0,nonzero=0,commands=0;
    assign o_done=done;
    always #10 clk=!clk;
    function [319:0] note;
        input [31:0] identity,increment,gain,pan;
        begin note={192'd0,pan,gain,increment,identity}; end
    endfunction
    VoiceSynthEngine Dut(.i_axis_aclk(clk),.i_axis_arstn(rstn),.i_s_axis_tdata(data),.i_s_axis_tuser(tag),
        .i_s_axis_tdest(opcode),.i_s_axis_tvalid(valid),.o_s_axis_tready(command_ready),
        .o_m_axis_tdata(response),.o_m_axis_tuser(response_tag),.o_m_axis_tdest(response_opcode),
        .o_m_axis_tvalid(response_valid),.i_m_axis_tready(ready),.i_sample_tick(tick),
        .o_pcm_valid(pcm_valid),.o_pcm_data(pcm),.o_frame(frame),.o_overruns(overruns),
        .o_render_cycles(cycles),.o_active(active));
    task request;
        input [7:0] operation,address;
        input [319:0] payload;
        input [31:0] sequence;
        input [7:0] status;
        begin
            @(negedge clk); data={sequence,24'd77,address,payload}; opcode=operation; valid=1; tag=commands;
            @(posedge clk); while(!command_ready) @(posedge clk);
            @(negedge clk); valid=0;
            while(!response_valid) @(negedge clk);
            if(response[71:64]!==status || response_tag!==commands || response_opcode!==operation)
                $fatal(1,"command %0d op %h status expected %h got %h",commands,operation,status,response);
            saved_response=response;
            commands=commands+1;
            @(negedge clk);
        end
    endtask
    task command;
        input [7:0] operation,address;
        input [319:0] payload;
        input [7:0] status;
        begin request(operation,address,payload,seq,status); seq=seq+1; end
    endtask
    task render;
        begin
            @(negedge clk); tick=1; @(negedge clk); tick=0; elapsed=1;
            while(!pcm_valid) begin @(negedge clk); elapsed=elapsed+1; if(elapsed>1024) $fatal(1,"deadline missed %0d",elapsed); end
            if(cycles>max_cycles) max_cycles=cycles;
            if(pcm!=0) nonzero=nonzero+1;
            if(overruns!=0) $fatal(1,"overrun");
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rstn=1;
        fd=$fopen("vectors/engine_patch.txt","r"); if(!fd) $fatal(1,"missing patch");
        for(op=0;op<6;op=op+1) begin code=$fscanf(fd,"%h %h\n",core[op],envelope[op]); if(code!=2) $fatal(1,"patch vector"); end
        $fclose(fd);
        command(8'ha4,0,{192'd0,32'd33554432,32'd67108864,32'd20000000,32'd1},9);
        command(8'ha0,0,1,0);
        command(8'ha3,0,0,9); // incomplete bank cannot become active
        for(op=0;op<6;op=op+1) begin command(8'ha1,op,core[op],0); command(8'ha2,op,envelope[op],0); end
        command(8'ha3,0,0,0);
        fd=$fopen("vectors/engine_patch_alt.txt","r");
        command(8'ha0,1,1,0);
        for(op=0;op<6;op=op+1) begin
            code=$fscanf(fd,"%h %h\n",core[op],envelope[op]); if(code!=2) $fatal(1,"alternate patch vector");
            command(8'ha1,8+op,core[op],0); command(8'ha2,8+op,envelope[op],0);
        end
        $fclose(fd);
        command(8'ha3,1,0,0);
        command(8'ha7,0,{256'd0,32'd67108864,32'd1},0);
        for(v=0;v<8;v=v+1) command(8'ha4,v%2,note(v+100,20000000+v*1234567,67108864-v*1000000,v*67108864/7),0);
        // Exact transaction retry returns cached result, not a ninth voice.
        request(opcode,1,data[319:0],seq-1,0);
        if(!saved_response[72] || active!=255) $fatal(1,"retry did not replay");
        request(8'ha5,0,100,seq-1,5);
        request(8'ha5,0,100,seq+1,7);
        fd=$fopen("vectors/engine_pcm.txt","r");
        for(n=0;n<400;n=n+1) begin
            if(n==80) begin
                command(8'ha4,0,{192'd0,32'd0,32'd67108864,32'd20000000,32'd100},0);
                if(!saved_response[73]) $fatal(1,"NoteID duplicate not recognized");
            end
            if(n==120) command(8'ha7,0,{256'd0,32'd67108864,32'd3},0);
            if(n==100) command(8'ha6,0,note(100,25000000,16777216,50331648),0);
            if(n==130) for(v=0;v<8;v=v+1) command(8'ha5,0,v+100,0);
            if(n==200) command(8'ha7,0,{256'd0,32'd67108864,32'd1},0);
            render;
            code=$fscanf(fd,"%h\n",expected);
            if(code!=1 || pcm!==expected) $fatal(1,"frame %0d expected %h got %h cycles=%0d",n,expected,pcm,cycles);
            if(n==190 && active!=255) $fatal(1,"sustain lost voices");
        end
        if(active!=0 || nonzero<190) $fatal(1,"release or silence failure active=%h nonzero=%0d",active,nonzero);
        // Oldest stealing plus stale NoteOff must preserve the replacement.
        for(v=0;v<9;v=v+1) command(8'ha4,0,note(v+1000,30000000,67108864,33554432),0);
        if(saved_response[2:0]!=0) $fatal(1,"oldest voice not stolen");
        command(8'ha5,0,1000,0); render;
        if(active!=255 || Dut.mem_identity[0]!=1008 || !Dut.reg_held[0]) $fatal(1,"stale off killed replacement");
        // An unconsumed control completion must not freeze the audio FSM.
        @(negedge clk); ready=0; valid=1; opcode=8'ha9; data={seq,24'd77,8'd0,320'd0};
        @(posedge clk); while(!command_ready) @(posedge clk);
        @(negedge clk); valid=0; saved_response=response;
        repeat(16) begin
            render;
            if(!response_valid || response!==saved_response) $fatal(1,"stalled control response moved");
            repeat(1024-elapsed) @(negedge clk);
        end
        ready=1; @(negedge clk); seq=seq+1;
        // Atomic bank update: drafting leaves active program unchanged.
        command(8'ha0,0,2,0);
        command(8'ha1,0,core[0] | (320'd1 << 128),8); // zero-delay self edge forbidden
        command(8'ha3,0,0,9);
        render; if(pcm==0) $fatal(1,"incomplete draft silenced active program");
        command(8'ha7,0,{256'd0,32'd67108864,32'd4},0); // disable + panic
        render; if(active!=0 || pcm!=0) $fatal(1,"panic did not silence");
        // Reallocation invalidates RAM even when NoteOff replaces NoteOn before a sample.
        command(8'ha7,0,{256'd0,32'd67108864,32'd1},0);
        command(8'ha4,0,note(9000,30000000,67108864,33554432),0);
        command(8'ha5,0,9000,0);
        render; if(active!=0 || pcm!=0) $fatal(1,"pre-frame NoteOff leaked a previous context");
        command(8'ha7,0,{256'd0,32'd67108864,32'd4},0);
        command(8'ha8,0,{256'd0,32'd67108864,32'd0},0);
        @(negedge clk); rstn=0; repeat(3) @(negedge clk); rstn=1;
        render; if(pcm!=0 || active!=0) $fatal(1,"reset ghost voice");
        $display("PASS voice_engine pcm_frames=400 all_48_operators=1 max_render_cycles=%0d nonzero_frames=%0d commands=%0d retry/sustain/steal/panic/reset/backpressure=PASS",max_cycles,nonzero,commands);
        done=1; $finish;
    end
    initial begin #30000000; $fatal(1,"watchdog"); end
endmodule
