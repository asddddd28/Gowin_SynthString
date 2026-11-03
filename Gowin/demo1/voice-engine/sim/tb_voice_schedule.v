`timescale 1ns / 1ps
// 复用真实AXI与FX激励，逐帧统计Voice状态占用；不改变DUT输入或执行顺序。
module tb_voice_schedule(output o_done);
    integer trace_file=0, state_index=0, measured_cycles=0, traced_frames=0; // 跟踪文件及逐帧状态计数
    integer state_cycles [0:18]; // 当前状态机全部有效状态的实际停留拍数
    integer operator_wait=0, request_stall=0; // 区分算子执行等待与请求端背压
    reg capturing=0; // 从被接纳的采样tick到Voice PCM结果期间采集
    wire done; // 原有完整AXI/FX回归完成标志
    reg pending=0, saved_carrier=0; // scoreboard中的当前已握手事务归属
    reg [5:0] saved_context=0, current_program=0; // 写回地址与独立计算的当前程序行地址
    reg [31:0] saved_history=0; // 当前算子前一采样的last，写回时必须变成older
    reg [162:0] expected_context=0; // 完成沿提交后应存储的全部状态
    reg signed [35:0] expected_sum=0; // 仅当前载波有资格计入声部累加
    integer issued=0, retired=0, skipped=0; // 实际观测到的请求、完成及禁用算子次数

    assign o_done=done; // 原回归负责功能断言及最终结束
    tb_axi_fx Stimulus(.o_done(done)); // 真实8声部、48算子、调制和FX压力激励

    initial begin // 只打开诊断输出，不向生产设计注入信号
        trace_file=$fopen("reports/voice-schedule.csv","w");
        if(trace_file==0) $fatal(1,"schedule trace file open failed");
        $fwrite(trace_file,"frame,voice_cycles,active,operator_wait,request_stall");
        for(state_index=0;state_index<19;state_index=state_index+1)
            $fwrite(trace_file,",state_%0d",state_index);
        $fwrite(trace_file,"\n");
    end

    always @(posedge Stimulus.clk) begin // NBA前取独立期望值，完成沿后检查实际RAM写回
        if(!Stimulus.rstn) pending=0;
        else begin
            if(Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_state==17 && Stimulus.Dut.Runtime_Inst.Voice_Inst.Modulation_Inst.reg_state!=3)
                $fatal(1,"smoothing must overlap the modulation route walk");
            current_program={Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_bank[Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_patch],
                Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_patch,Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_operator};
            if(Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_state==1 && Stimulus.Dut.Runtime_Inst.Voice_Inst.flag_enabled &&
                Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_active[Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_voice]) begin
                if(Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_core!==Stimulus.Dut.Runtime_Inst.Voice_Inst.mem_core[current_program] ||
                    Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_envelope!==Stimulus.Dut.Runtime_Inst.Voice_Inst.mem_envelope[current_program])
                    $fatal(1,"prefetch program row belongs to another operator");
                if(Stimulus.Dut.Runtime_Inst.Voice_Inst.flag_context_valid[Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_context] &&
                    Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_context_row!==Stimulus.Dut.Runtime_Inst.Voice_Inst.mem_context[Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_context])
                    $fatal(1,"prefetch context row belongs to another operator");
                if(!Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_flags[12]) skipped=skipped+1;
            end
            if(Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_state==2 && Stimulus.Dut.Runtime_Inst.Voice_Inst.flag_operator_ready) begin
                if(pending) $fatal(1,"two requests in single-inflight operator");
                pending=1; issued=issued+1;
                saved_context=Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_context;
                saved_carrier=Stimulus.Dut.Runtime_Inst.Voice_Inst.mem_core[current_program][134];
                saved_history=Stimulus.Dut.Runtime_Inst.Voice_Inst.flag_context_valid[saved_context] ?
                    Stimulus.Dut.Runtime_Inst.Voice_Inst.mem_context[saved_context][98:67] : 32'd0;
                if(Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_operator_request[511:480]!==saved_history ||
                    Stimulus.Dut.Runtime_Inst.Voice_Inst.flag_operator_carrier!==saved_carrier)
                    $fatal(1,"current request history/carrier corrupted by prefetch");
            end
            if(Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_state==3 && Stimulus.Dut.Runtime_Inst.Voice_Inst.flag_operator_valid) begin
                if(!pending || Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_operator_tag!=={26'd0,saved_context} ||
                    Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_context!==saved_context)
                    $fatal(1,"completion context/tag ownership mismatch");
                expected_context={Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_operator_result[159:128],saved_history,
                    Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_operator_result[31:0],
                    Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_operator_result[98:96],
                    Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_operator_result[95:64],
                    Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_operator_result[63:32]};
                expected_sum=Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_carrier_sum;
                if(saved_carrier) expected_sum=expected_sum+$signed(Stimulus.Dut.Runtime_Inst.Voice_Inst.wire_operator_result[31:0]);
                pending=0; retired=retired+1;
                #1;
                if(Stimulus.Dut.Runtime_Inst.Voice_Inst.mem_context[saved_context]!==expected_context ||
                    Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_carrier_sum!==expected_sum)
                    $fatal(1,"completion state/history/carrier writeback mismatch");
            end
        end
    end

    always @(posedge done) begin // 原有回归完成时输出归属检查的实际覆盖规模
        if(issued==0 || retired==0) $fatal(1,"ownership scoreboard observed no work");
        $display("PASS prefetch_ownership issued=%0d retired=%0d skipped=%0d pending=%0d",issued,retired,skipped,pending);
    end

    always @(negedge Stimulus.clk) begin // 下降沿观察，避免与DUT寄存器写入竞争
        if(!Stimulus.rstn) capturing=0;
        else if(Stimulus.Dut.Runtime_Inst.flag_tick && Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_state==0) begin
            capturing=1; measured_cycles=0; operator_wait=0; request_stall=0;
            for(state_index=0;state_index<19;state_index=state_index+1) state_cycles[state_index]=0;
        end else if(capturing && Stimulus.Dut.Runtime_Inst.flag_voice_pcm) begin
            if(measured_cycles!=Stimulus.Dut.Runtime_Inst.Voice_Inst.o_render_cycles)
                $fatal(1,"schedule accounting mismatch measured=%0d reported=%0d",measured_cycles,Stimulus.Dut.Runtime_Inst.Voice_Inst.o_render_cycles);
            $fwrite(trace_file,"%0d,%0d,%0d,%0d,%0d",Stimulus.Dut.Runtime_Inst.wire_voice_frame,measured_cycles,
                Stimulus.Dut.Runtime_Inst.Voice_Inst.o_active,operator_wait,request_stall);
            for(state_index=0;state_index<19;state_index=state_index+1)
                $fwrite(trace_file,",%0d",state_cycles[state_index]);
            $fwrite(trace_file,"\n");
            traced_frames=traced_frames+1; capturing=0;
        end else if(capturing) begin
            state_index=Stimulus.Dut.Runtime_Inst.Voice_Inst.reg_state;
            if(state_index>18) $fatal(1,"unexpected scheduler state");
            state_cycles[state_index]=state_cycles[state_index]+1;
            measured_cycles=measured_cycles+1;
            if(state_index==3 && !Stimulus.Dut.Runtime_Inst.Voice_Inst.flag_operator_valid) operator_wait=operator_wait+1;
            if(state_index==2 && !Stimulus.Dut.Runtime_Inst.Voice_Inst.flag_operator_ready) request_stall=request_stall+1;
        end
    end
endmodule
