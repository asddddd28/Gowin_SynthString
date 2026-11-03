`timescale 1ns/1ps
module tb_lfo_engine(output o_done);
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
    integer setup_file,timeline_file,pcm_file,state_file,total,k,c,actions;
    reg [7:0] cmd_opcode,cmd_address;
    reg [319:0] cmd_payload;
    reg [127:0] expected_state,actual_state;
    reg [31:0] phase_before;
    initial begin
        repeat(4) @(negedge clk);rstn=1;
        setup_file=$fopen("vectors/lfo_setup.txt","r");timeline_file=$fopen("vectors/lfo_timeline.txt","r");
        pcm_file=$fopen("vectors/lfo_pcm.txt","r");state_file=$fopen("vectors/lfo_states.txt","r");
        code=$fscanf(setup_file,"%d\n",total);if(code!=1) $fatal(1,"setup count");
        for(k=0;k<total;k=k+1) begin
            code=$fscanf(setup_file,"%h %h %h\n",cmd_opcode,cmd_address,cmd_payload);if(code!=3) $fatal(1,"setup format");
            command(cmd_opcode,cmd_address,cmd_payload,0);
        end
        // Explicit rejection of out-of-draft writes, bad wave/rate and target index.
        command(8'hb0,0,0,9);
        command(8'hb1,0,60,8);
        command(8'hb0,0,32'd8796094,8);
        command(8'hb2,24,0,8);
        for(n=0;n<1600;n=n+1) begin
            code=$fscanf(timeline_file,"%d\n",actions);if(code!=1) $fatal(1,"timeline count");
            for(k=0;k<actions;k=k+1) begin
                code=$fscanf(timeline_file,"%h %h %h\n",cmd_opcode,cmd_address,cmd_payload);if(code!=3) $fatal(1,"timeline format");
                command(cmd_opcode,cmd_address,cmd_payload,0);
            end
            render;
            code=$fscanf(pcm_file,"%h\n",expected);
            if(code!=1 || pcm!==expected) $fatal(1,"LFO audio frame %0d expected %h got %h cycles=%0d",n,expected,pcm,cycles);
            for(c=0;c<24;c=c+1) begin
                code=$fscanf(state_file,"%h",expected_state);if(code!=1) $fatal(1,"state format");
                // Compare observable state, independent of its physical RAM encoding.
                @(negedge clk);data[327:320]=c;#1;
                actual_state=Dut.wire_lfo_inspect;
                if(actual_state!==expected_state) $fatal(1,"LFO state frame=%0d context=%0d expected %h got %h",n,c,expected_state,actual_state);
            end
            if(n==79 || n==599) begin
                command(8'hb2,0,0,0);
                if(saved_response[63:32]!==Dut.Modulation_Inst.mem_phase[0]) $fatal(1,"inspect phase mismatch");
                request(8'hb2,0,0,seq-1,0);if(!saved_response[72]) $fatal(1,"inspect replay missing");
            end
            if(n==520) begin
                request(8'hb3,0,0,seq-1,0);
                if(!saved_response[72] || !Dut.Modulation_Inst.flag_initialized[0]) $fatal(1,"restart retry re-triggered global LFO");
            end
        end
        // Leave a control result stalled while a fully modulated frame renders.
        @(negedge clk);ready=0;valid=1;opcode=8'hb2;data={seq,24'd77,8'd0,320'd0};
        @(posedge clk);while(!command_ready) @(posedge clk);
        @(negedge clk);valid=0;saved_response=response;
        repeat(8) begin render;if(response!==saved_response || !response_valid) $fatal(1,"stalled inspect changed");end
        ready=1;@(negedge clk);seq=seq+1;
        command(8'ha7,0,{256'd0,32'd67108864,32'd4},0);
        phase_before=Dut.Modulation_Inst.mem_phase[0];repeat(4) render;
        if(pcm!=0 || Dut.Modulation_Inst.mem_phase[0]!=phase_before) $fatal(1,"disabled engine must freeze LFO and emit silence");
        @(negedge clk);rstn=0;repeat(2) @(negedge clk);rstn=1;
        if(Dut.Modulation_Inst.flag_initialized!==0) $fatal(1,"reset retained LFO state");
        for(c=0;c<24;c=c+1)begin
            @(negedge clk);data[327:320]=c;#1;
            if(Dut.wire_lfo_inspect!==128'h00000001000000000000000000000000)$fatal(1,"reset exposes stale RAM %0d",c);
        end
        $display("PASS lfo_engine pcm_frames=1600 state_snapshots=38400 voices=8 logical_ops=48 max_render_cycles=%0d commands=%0d",max_cycles,commands);
        done=1;$finish;
    end
    initial begin #80000000;$fatal(1,"LFO engine watchdog");end
endmodule
