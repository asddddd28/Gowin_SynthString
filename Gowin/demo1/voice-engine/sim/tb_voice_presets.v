`timescale 1ns/1ps
module tb_voice_presets(output o_done);
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
    integer preset_index,program_file,pcm_file,k,preset_nonzero;
    reg [7:0] program_opcode,program_address;
    reg [31:0] program_sequence,increment;
    reg [319:0] program_image;
    initial begin
        repeat(4) @(negedge clk); rstn=1;
        program_file=$fopen("vectors/preset_programs.txt","r");
        pcm_file=$fopen("vectors/preset_pcm.txt","r");
        for(preset_index=0;preset_index<5;preset_index=preset_index+1) begin
            // Compiler sequence is rebased because transport/note commands share it.
            for(k=0;k<14;k=k+1) begin
                code=$fscanf(program_file,"%h %h %h %h\n",program_opcode,program_address,program_sequence,program_image);
                if(code!=4) $fatal(1,"program format");
                command(program_opcode,program_address,program_image,0);
            end
            command(8'ha7,0,{256'd0,32'd67108864,32'd5},0);
            // Rounded MIDI phase words at 50 MHz / 1024; generated independently.
            increment=preset_index==1 ? 32'd11506414 : 32'd23012828;
            command(8'ha4,0,note(100,increment,67108864,33554432),0);
            if(preset_index==4) begin
                command(8'ha4,0,note(101,28994347,67108864,33554432),0);
                command(8'ha4,0,note(102,34480283,67108864,33554432),0);
            end
            preset_nonzero=0;
            for(n=0;n<2048;n=n+1) begin
                if(n==1024) begin
                    command(8'ha5,0,100,0);
                    if(preset_index==4) begin command(8'ha5,0,101,0); command(8'ha5,0,102,0); end
                end
                render;
                code=$fscanf(pcm_file,"%h\n",expected);
                if(code!=1 || pcm!==expected) $fatal(1,"preset %0d frame %0d expected %h got %h",preset_index,n,expected,pcm);
                if(pcm!=0) preset_nonzero=preset_nonzero+1;
            end
            if(preset_nonzero<900) $fatal(1,"preset unexpectedly silent");
        end
        $display("PASS voice_presets compiled_patches=5 compared_pcm_frames=10240 chord_voices=3");
        done=1; $finish;
    end
    initial begin #300000000; $fatal(1,"preset watchdog"); end
endmodule
