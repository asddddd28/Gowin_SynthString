`timescale 1ns/1ps
// Whole-engine oracle: real factory programs, resident slots, velocity and mixing.
module tb_fm1_engine(output o_done);
    reg clk=0,rstn=0,valid=0,ready=1,tick=0,done=0;
    reg [383:0] data=0;
    reg [31:0] sequence=0;
    reg [7:0] opcode=0;
    wire command_ready,response_valid,pcm_valid;
    wire [127:0] response;
    wire [31:0] response_tag,frame,overruns,cycles;
    wire [7:0] response_opcode,active;
    wire [63:0] pcm;
    integer fd,code,kind,count=0,frames=0,nonzero=0,elapsed,max_cycles=0;
    reg [7:0] action_opcode,address,status;
    reg [319:0] payload;
    reg [63:0] expected;
    assign o_done=done;
    always #10 clk=!clk;
    VoiceSynthEngine Dut(.i_axis_aclk(clk),.i_axis_arstn(rstn),.i_s_axis_tdata(data),.i_s_axis_tuser(sequence),
        .i_s_axis_tdest(opcode),.i_s_axis_tvalid(valid),.o_s_axis_tready(command_ready),
        .o_m_axis_tdata(response),.o_m_axis_tuser(response_tag),.o_m_axis_tdest(response_opcode),
        .o_m_axis_tvalid(response_valid),.i_m_axis_tready(ready),.i_sample_tick(tick),
        .o_pcm_valid(pcm_valid),.o_pcm_data(pcm),.o_frame(frame),.o_overruns(overruns),
        .o_render_cycles(cycles),.o_active(active));
    initial begin
        repeat(4)@(negedge clk);rstn=1;
        fd=$fopen("vectors/fm1_engine.txt","r");if(!fd)$fatal(1,"missing scenario");
        while(!$feof(fd))begin
            code=$fscanf(fd,"%d %h %h %h %h %h\n",kind,action_opcode,address,payload,status,expected);
            if(code!=6)$fatal(1,"malformed scenario");
            if(kind==0)begin
                @(negedge clk);data={sequence,24'd88,address,payload};opcode=action_opcode;valid=1;
                @(posedge clk);while(!command_ready)@(posedge clk);
                @(negedge clk);valid=0;
                while(!response_valid)@(negedge clk);
                if(response[71:64]!==status || response_tag!==sequence || response_opcode!==opcode)
                    $fatal(1,"command %0d op %h expected status %h got %h",count,opcode,status,response);
                @(negedge clk);sequence=sequence+1;count=count+1;
            end else begin
                @(negedge clk);tick=1;@(negedge clk);tick=0;elapsed=1;
                while(!pcm_valid)begin @(negedge clk);elapsed=elapsed+1;if(elapsed>1024)$fatal(1,"audio deadline");end
                if(pcm!==expected)$fatal(1,"frame %0d expected %h got %h",frames,expected,pcm);
                if(overruns!=0)$fatal(1,"overrun");
                if(cycles>max_cycles)max_cycles=cycles;
                if(pcm!=0)nonzero=nonzero+1;
                frames=frames+1;
            end
        end
        if(frames!=10240 || count!=147 || nonzero<9000)$fatal(1,"coverage frames=%0d commands=%0d nonzero=%0d",frames,count,nonzero);
        $display("PASS fm1_engine patches=4 PCM=%0d commands=%0d max_voice_cycles=%0d mixed_native=PASS metadata_conflict=PASS live_format_barrier=PASS",frames,count,max_cycles);
        done=1;$finish;
    end
    initial begin #300000000;$fatal(1,"watchdog");end
endmodule
