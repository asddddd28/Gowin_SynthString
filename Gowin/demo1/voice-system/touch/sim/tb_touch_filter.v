`timescale 1ns/1ps
module tb_touch_filter;
    reg clk=0,rstn=0,command_valid=0,audio_valid=0;
    always #10 clk=~clk;
    reg signed [19:0] offset=0;reg touch_active=0;
    reg [383:0] command=0,reference_command=0;reg [63:0] audio=0;
    wire [1:0] ready,result_valid,audio_ready,output_valid;
    wire [63:0] outputs[0:1];
    integer mode,n,elapsed,nonzero=0;
    genvar g;
    generate for(g=0;g<2;g=g+1)begin:filters
        AxisMasterLowpass #(.C_TOUCH_ENABLE(g==0)) dut(.i_clk(clk),.i_rstn(rstn),.i_touch_cutoff(offset),.i_touch_cutoff_active(touch_active),
            .i_command(g==0?command:reference_command),.i_tag(32'd0),.i_opcode(8'hd0),.i_command_valid(command_valid),.o_command_ready(ready[g]),
            .o_result(),.o_tag(),.o_opcode(),.o_result_valid(result_valid[g]),.i_result_ready(1'b1),
            .i_audio(audio),.i_frame(32'd0),.i_audio_valid(audio_valid),.o_audio_ready(audio_ready[g]),.o_audio(outputs[g]),.o_frame(),.o_audio_valid(output_valid[g]),.i_audio_ready(1'b1));
    end endgenerate
    initial begin
        for(mode=0;mode<4;mode=mode+1)begin
            rstn=0;repeat(4)@(negedge clk);rstn=1;
            offset=mode==0?0:mode==1?26700:mode==2?-53400:0;touch_active=mode!=0;
            command=0;command[31:0]=mode==0?1:mode==1?0:3;command[63:32]=177296;command[95:64]=879609;command[127:96]=53400;command[159:128]=mode+1;
            reference_command=command;reference_command[31:0]=command[31:0]|touch_active;reference_command[63:32]=177296+offset;
            @(negedge clk);command_valid=1;@(negedge clk);command_valid=0;wait(result_valid==3);@(negedge clk);
            for(n=0;n<1024;n=n+1)begin
                wait(audio_ready==3);@(negedge clk);audio={32'd0,n[3]?32'd30000000:-32'sd30000000};audio_valid=1;
                @(negedge clk);audio_valid=0;elapsed=0;
                while(output_valid!=3)begin @(negedge clk);elapsed=elapsed+1;if(elapsed>48)$fatal(1,"filter deadline");end
                if(outputs[0]!==outputs[1])$fatal(1,"filter mismatch mode=%d sample=%d %h/%h",mode,n,outputs[0],outputs[1]);
                if(outputs[0][63:32]!=0)$fatal(1,"stereo cross-talk");if(outputs[0]!=0)nonzero=nonzero+1;@(negedge clk);
            end
        end
        if(nonzero<3000)$fatal(1,"silent filter");$display("PASS touch filter 4096 PCM frames: neutral, temporary enable, positive/negative cutoff with LFO, stereo isolation");$finish;
    end
    initial begin #20000000;$fatal(1,"timeout");end
endmodule
