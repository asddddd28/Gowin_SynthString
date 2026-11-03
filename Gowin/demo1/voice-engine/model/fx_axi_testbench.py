"""Reuse the established AXI BFM; exercise the real voice/LFO/FX endpoint closure."""
from fx_contracts import ROOT, publish


def generate():
    base=(ROOT/'sim/tb_axi_lfo.v').read_text(encoding='utf-8')
    prefix=base[:base.index('    integer program_count,preset_index,k;')]
    prefix=prefix.replace('tb_axi_lfo','tb_axi_fx').replace('#60000000','#500000000')
    prefix=prefix.replace('AxiVoiceEndpoint Dut(', 'AxiVoiceEndpoint #(.LEGACY_ENABLE(0)) Dut(')
    prefix=prefix.replace('tries<100','tries<1000').replace('tries==100','tries==1000')
    prefix=prefix.replace('$fatal(1,"completion timeout")', '$fatal(1,"completion timeout op=%h cmd=%0d comp=%0d legacy=%b/%b selected=%b voice=%b/%b state=%d active=%h opcode=%h overrun=%d",Dut.reg_stage_opcode,Dut.cnt_command,Dut.cnt_completion,Dut.Runtime_Inst.flag_legacy_valid,Dut.Runtime_Inst.flag_legacy_ready,Dut.Runtime_Inst.flag_take_legacy,Dut.Runtime_Inst.flag_voice_valid,Dut.Runtime_Inst.flag_voice_ready,Dut.Runtime_Inst.Voice_Inst.reg_state,Dut.Runtime_Inst.o_active,Dut.Runtime_Inst.i_s_axis_tdest,Dut.Runtime_Inst.o_overruns)')
    tail=r'''
    integer fx_seq=0, saved_voice_seq, program_count,k,raw_file,out_file;
    integer clock_count=0,tick_clock=0,max_total=0,max_voice=0,clears=0;
    integer pending_clear=0,prior_audio,prior_nonzero;
    reg [7:0] program_opcode,program_address;
    reg [319:0] program_payload;
    reg [319:0] delay_image={160'd0,32'd3,32'd26843545,32'd33554432,32'h0017c000,32'h00104000};
    reg [319:0] reverb_image={192'd0,32'd1,32'd33554432,32'd20132659,32'd46976204};
    reg [127:0] cached_commit;
    task fx_control;
        input [7:0] operation,address;
        input [319:0] image;
        input [7:0] status;
        begin
            saved_voice_seq=engine_seq;
            engine_seq=fx_seq;
            control(operation,address,image,status);
            fx_seq=engine_seq;
            engine_seq=saved_voice_seq;
        end
    endtask
    always @(posedge clk) begin
        if(rstn) begin
            clock_count=clock_count+1;
            if(Dut.Runtime_Inst.flag_tick) tick_clock=clock_count;
            if(Dut.Runtime_Inst.FxDomain.Fx_Inst.flag_clear_delay) pending_clear=pending_clear|1;
            if(Dut.Runtime_Inst.FxDomain.Fx_Inst.flag_clear_reverb) begin pending_clear=pending_clear|2;clears=clears+1;end
            if(Dut.Runtime_Inst.FxDomain.Fx_Inst.i_audio_valid && Dut.Runtime_Inst.FxDomain.Fx_Inst.o_audio_ready) begin
                $fwrite(raw_file,"%h %h %h %h %h\n",pending_clear,Dut.Runtime_Inst.FxDomain.Fx_Inst.i_audio_frame,
                    Dut.Runtime_Inst.FxDomain.Fx_Inst.i_audio_data,Dut.Runtime_Inst.FxDomain.Fx_Inst.reg_delay_active,Dut.Runtime_Inst.FxDomain.Fx_Inst.reg_reverb_active);
                pending_clear=0;
            end
            if(Dut.Runtime_Inst.flag_pcm) begin
                $fwrite(out_file,"%h %h\n",Dut.Runtime_Inst.wire_frame,Dut.Runtime_Inst.wire_pcm);
                if(clock_count-tick_clock>max_total) max_total=clock_count-tick_clock;
                if(clock_count-tick_clock>=1024) $fatal(1,"whole audio frame missed deadline");
            end
            if(Dut.Runtime_Inst.o_render_cycles>max_voice) max_voice=Dut.Runtime_Inst.o_render_cycles;
        end
    end
    initial begin
        raw_file=$fopen("reports/fx-axi-input.txt","w");
        out_file=$fopen("reports/fx-axi-output.txt","w");
        repeat(4) @(negedge clk);rstn=1;
        check_word(4,32'h00010005,0);
        check_word(16'h4c,32'h040f1203,0);
        check_word(16'h50,32767,0);
        check_word(16'h0c,0,0);check_word(16'h1c,0,0);check_word(16'h30,0,0);
        stage(8'h01,9000,0);write_word(16'h130,1);expect_b(0);
        consume(128'h00000000000000010000000000000000,9000,8'h01);
        fx_control(8'hc0,0,delay_image,0);
        fx_control(8'hc1,0,reverb_image,0);
        fx_control(8'hc4,1,0,0);
        if(control_result[63:0]!==64'h0001000000010000) $fatal(1,"draft leaked before commit");
        fx_control(8'hc2,0,0,0);cached_commit=control_result;
        if(control_result[31:0]!==1) $fatal(1,"commit revision");
        fx_seq=fx_seq-1;fx_control(8'hc2,0,0,0);
        if(control_result!==(cached_commit|(128'd1<<72))) $fatal(1,"commit replay");
        fx_seq=fx_seq-1;fx_control(8'hc2,0,1,5);
        fx_control(8'hc0,0,0,8);
        fx_control(8'hc1,0,{192'd0,32'd1,32'd33554432,32'd20132659,32'd67108864},8);
        fx_control(8'hc4,3,0,0);
        if(control_result[127:96]!==1) $fatal(1,"replay recommitted");
        fd=$fopen("vectors/lfo_setup.txt","r");
        code=$fscanf(fd,"%d\n",program_count);
        if(code!=1) $fatal(1,"setup count");
        for(k=0;k<program_count;k=k+1) begin
            code=$fscanf(fd,"%h %h %h\n",program_opcode,program_address,program_payload);
            if(code!=3) $fatal(1,"setup format");
            control(program_opcode,program_address,program_payload,0);
        end
        $fclose(fd);
        for(k=0;k<8;k=k+1) begin
            program_payload=0;
            program_payload[31:0]=900+k;
            program_payload[63:32]=23012828+1000000*k;
            program_payload[95:64]=67108864;
            program_payload[127:96]=33554432;
            control(8'ha4,k%4,program_payload,0);
        end
        repeat(1024*3000) @(negedge clk);
        if(nonzero_pcm<2900 || max_voice!=834) $fatal(1,"full voice workload not exercised %0d/%0d",nonzero_pcm,max_voice); // 预取后每算子增加一拍部分和提交；1024拍期限不变。
        // Fill host completion FIFO; audio must continue through both effects.
        prior_audio=pcm_count;
        for(k=0;k<4;k=k+1) begin
            stage(8'hc4,10000+k,0);
            write_word(16'h134,{24'd55,8'd0});expect_b(0);
            write_word(16'h138,fx_seq);expect_b(0);
            write_word(16'h130,1);expect_b(0);
            fx_seq=fx_seq+1;
        end
        repeat(1024*80) @(negedge clk);
        read_burst(8,0,2,1,0);
        if(rd[0][6:4]!=4 || pcm_count-prior_audio<80) $fatal(1,"host completion blocked audio");
        for(k=0;k<4;k=k+1) begin
            read_burst(16'h200,5,2,1,0);
            if(rd[2][7:0]!=0 || rd[4]!=10000+k || rd[5]!=8'hc4) $fatal(1,"queued completion");
            write_word(16'h218,1);expect_b(0);
        end
        // Note panic leaves the shared room alive while all voice outputs become zero.
        control(8'ha7,0,{256'd0,32'd67108864,32'd5},0);
        repeat(1024*8) @(negedge clk);
        prior_nonzero=nonzero_pcm;
        repeat(1024*3000) @(negedge clk);
        if(nonzero_pcm-prior_nonzero<2000) $fatal(1,"shared tail died with voices");
        check_word(16'h38,0,0);
        // Clearing once is an action. Exact transport retries must not clear again.
        fx_control(8'hc3,0,3,0);
        repeat(1024*20) @(negedge clk);
        fx_seq=fx_seq-1;fx_control(8'hc3,0,3,0);
        if(!control_result[72] || clears!=1 || Dut.Runtime_Inst.FxDomain.Fx_Inst.Reverb_Inst.cnt_age<10)
            $fatal(1,"clear retry destroyed tail state");
        // Stalled PCM head stays stable, new frames are dropped with telemetry.
        pcm_ready=0;
        repeat(1024*8) @(negedge clk);
        read_burst(16'h44,0,2,1,0);
        if(rd[0]==0) $fatal(1,"missing PCM drop telemetry");
        pcm_ready=1;
        check_word(16'h3c,0,0);
        check_word(16'h5c,0,0);
        read_burst(16'h60,0,2,1,0);
        if(rd[0]>100 || rd[0]==0) $fatal(1,"FX cycles invalid %0d",rd[0]);
        repeat(1024*2) @(negedge clk);
        $fclose(raw_file);$fclose(out_file);
        completed=1;
        $display("PASS axi_fx commands=%0d pcm=%0d full_voice_cycles=%0d total_cycles=%0d fx_cycles=%0d clear_pulses=%0d",engine_tag,pcm_count,max_voice,max_total,rd[0],clears);
        #1; // 允许外层只读scoreboard处理完成事件后再结束仿真。
        $finish;
    end
endmodule
'''
    (ROOT/'sim/tb_axi_fx.v').write_text(prefix+tail,encoding='utf-8')
    publish('tb_axi_fx',[('output','o_done',1)],['真实AXI参数装载、草稿提交、重试、声音+LFO+FX满负载时限和独立尾音。'],'sim/tb_axi_fx.v')


if __name__=='__main__': generate()
