`timescale 1ns/1ps
module tb_master_lowpass(output o_done);
    reg clk=0,rstn=0,completed=0;
    always #10 clk=~clk;
    assign o_done=completed;
    reg [383:0] command=0;
    reg [31:0] tag=0;
    reg [7:0] opcode=0;
    reg command_valid=0,result_ready=0,audio_valid=0,audio_ready=0;
    wire command_ready,result_valid,source_ready,result_audio_valid;
    wire [127:0] result;
    wire [31:0] result_tag,result_frame;
    wire [7:0] result_opcode;
    reg [63:0] audio=0;
    reg [31:0] frame=0;
    wire [63:0] result_audio;
    reg [255:0] vectors[0:12287];
    reg [255:0] vector;
    integer index,cycles,maximum=0,stall,last_block=0;
    AxisMasterLowpass dut(.i_clk(clk),.i_rstn(rstn),.i_command(command),.i_tag(tag),.i_opcode(opcode),.i_command_valid(command_valid),.o_command_ready(command_ready),
        .o_result(result),.o_tag(result_tag),.o_opcode(result_opcode),.o_result_valid(result_valid),.i_result_ready(result_ready),
        .i_audio(audio),.i_frame(frame),.i_audio_valid(audio_valid),.o_audio_ready(source_ready),.o_audio(result_audio),.o_frame(result_frame),.o_audio_valid(result_audio_valid),.i_audio_ready(audio_ready));
    initial begin
        $readmemh("vectors.hex",vectors);
        repeat(3)@(negedge clk);rstn=1;
        for(index=0;index<12288;index=index+1)begin
            vector=vectors[index];
            if(vector[206:199]!=last_block)begin
                wait(command_ready);@(negedge clk);opcode='hd0;tag=index;command=0;
                command[31:0]=vector[130:128];command[63:32]=vector[148:131];command[95:64]=vector[180:149];command[127:96]=vector[198:181];command[159:128]=vector[206:199];command_valid=1;
                @(negedge clk);command_valid=0;wait(result_valid);#1;
                if(result[71:64]!=0||result_tag!=index||result[63:32]!=vector[206:199])$fatal(1,"config ACK");
                // Hold completion through first100audio frames to prove independent progress.
                last_block=vector[206:199];
            end
            wait(source_ready);@(negedge clk);audio=vector[63:0];frame=index;audio_valid=1;
            @(negedge clk);audio_valid=0;cycles=0;
            while(!result_audio_valid)begin @(negedge clk);cycles=cycles+1;if(cycles>=48)$fatal(1,"audio deadline");end
            if(cycles>maximum)maximum=cycles;
            if(result_audio!==vector[127:64]||result_frame!==index)$fatal(1,"sample %d actual %h expected %h",index,result_audio,vector[127:64]);
            for(stall=0;stall<index%7;stall=stall+1)begin @(negedge clk);if(!result_audio_valid||result_audio!==vector[127:64]||result_frame!==index)$fatal(1,"audio backpressure");end
            audio_ready=1;@(negedge clk);audio_ready=0;
            if(index%2048==100)begin result_ready=1;@(negedge clk);result_ready=0;end
        end
        wait(command_ready);@(negedge clk);opcode='hd0;command=0;command_valid=1;
        @(negedge clk);command_valid=0;wait(result_valid);#1;if(result[71:64]!=1||dut.reg_revision!=6)$fatal(1,"invalid config mutated state");
        @(negedge clk);result_ready=1;@(negedge clk);result_ready=0;wait(command_ready);
        @(negedge clk);opcode='hd1;command_valid=1;@(negedge clk);command_valid=0;wait(result_valid);#1;
        if(result[71:64]!=0||result[63:32]!=6||result[31:0]!=0)$fatal(1,"status snapshot");
        completed=1;$display("PASS lowpass 12288 stereo frames bit-exact, full-scale bounded, sine/triangle modulation, bypass, backpressure, command/audio independence, max %d cycles",maximum);$finish;
    end
    initial begin #40000000;$fatal(1,"timeout index=%d command=%d audio=%d",index,dut.reg_command_state,dut.reg_audio_state);end
endmodule
