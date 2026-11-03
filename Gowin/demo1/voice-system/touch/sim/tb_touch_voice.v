`timescale 1ns/1ps
// Independent equivalence: performance sidebands vs changing only base pitch/gain.
module tb_touch_voice;
    reg clk=0,rstn=0,valid=0,tick=0;
    always #10 clk=~clk;
    reg [383:0] data=0,reference_data=0;
    reg [7:0] opcode=0;
    reg [17:0] gain=65536;
    reg signed [31:0] pitch=0;
    wire [1:0] ready,response_valid,pcm_valid;
    wire [127:0] response[0:1];wire [63:0] pcm[0:1];
    wire [31:0] cycles[0:1],overruns[0:1];
    genvar g;
    generate for(g=0;g<2;g=g+1)begin:engines
        VoiceSynthEngine #(.C_TOUCH_ENABLE(g==0)) dut(.i_axis_aclk(clk),.i_axis_arstn(rstn),.i_touch_gain(gain),.i_touch_pitch(pitch),
            .i_s_axis_tdata(g==0?data:reference_data),.i_s_axis_tuser(32'd0),.i_s_axis_tdest(opcode),.i_s_axis_tvalid(valid),.o_s_axis_tready(ready[g]),
            .o_m_axis_tdata(response[g]),.o_m_axis_tuser(),.o_m_axis_tdest(),.o_m_axis_tvalid(response_valid[g]),.i_m_axis_tready(1'b1),
            .i_sample_tick(tick),.o_pcm_valid(pcm_valid[g]),.o_pcm_data(pcm[g]),.o_frame(),.o_overruns(overruns[g]),.o_render_cycles(cycles[g]),.o_active());
    end endgenerate
    integer seq=0,fd,k,n,testcase,preset,code,elapsed,nonzero=0,maximum=0;
    reg [7:0] file_op,file_address;reg [31:0] file_seq,phase,ref_phase,master,ref_master;
    reg [319:0] payload;
    task command;input [7:0] op,address;input [319:0] a,b;
        begin
            @(negedge clk);data={seq[31:0],24'd77,address,a};reference_data={seq[31:0],24'd77,address,b};opcode=op;valid=1;
            @(posedge clk);while(ready!=3)@(posedge clk);@(negedge clk);valid=0;
            while(response_valid!=3)@(negedge clk);
            if(response[0][71:64]!=0||response[1][71:64]!=0)$fatal(1,"command error %h/%h",response[0],response[1]);
            seq=seq+1;@(negedge clk);
        end
    endtask
    initial begin
        for(testcase=0;testcase<4;testcase=testcase+1)begin
            gain=testcase==0?65536:testcase==1?32768:testcase==2?98304:131072;
            pitch=testcase==0?0:testcase==1?16777216:testcase==2?-16777216:67108864;
            master=testcase<2?67108864:testcase==2?33554432:50331648;
            ref_master=testcase==0?67108864:testcase==1?33554432:testcase==2?50331648:67108864;
            fd=$fopen("preset_programs.txt","r");if(fd==0)$fatal(1,"missing fixtures");
            for(preset=0;preset<5;preset=preset+1)begin
                rstn=0;repeat(4)@(negedge clk);rstn=1;seq=0;
                for(k=0;k<14;k=k+1)begin
                    code=$fscanf(fd,"%h %h %h %h\n",file_op,file_address,file_seq,payload);if(code!=4)$fatal(1,"fixture parse");
                    command(file_op,file_address,payload,payload);
                end
                command('ha7,0,{256'd0,master,32'd5},{256'd0,ref_master,32'd5});
                phase=23012828;ref_phase=testcase==0?phase:testcase==1?phase+phase/4:testcase==2?phase-phase/4:phase*2;
                command('ha4,0,{192'd0,32'd33554432,32'd67108864,phase,32'd100},{192'd0,32'd33554432,32'd67108864,ref_phase,32'd100});
                repeat(5)@(negedge clk);
                for(n=0;n<256;n=n+1)begin
                    tick=1;@(negedge clk);tick=0;elapsed=0;
                    while(pcm_valid!=3)begin @(negedge clk);elapsed=elapsed+1;if(elapsed>1024)$fatal(1,"deadline");end
                    if(pcm[0]!==pcm[1])$fatal(1,"PCM mismatch case=%d preset=%d sample=%d %h/%h",testcase,preset,n,pcm[0],pcm[1]);
                    if(pcm[0]!=0)nonzero=nonzero+1;if(cycles[0]>maximum)maximum=cycles[0];
                    if(overruns[0]||overruns[1])$fatal(1,"overrun");@(negedge clk);
                end
            end
            $fclose(fd);
        end
        if(nonzero<4000)$fatal(1,"insufficient sound %d",nonzero);
        $display("PASS touch voice: 5120 PCM frames bit-exact vs independent base gain/pitch, neutral, down/up, output gain clamp, five synth presets, max cycles=%d",maximum);$finish;
    end
    initial begin #200000000;$fatal(1,"timeout");end
endmodule
