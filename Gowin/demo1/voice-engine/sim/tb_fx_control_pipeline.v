`timescale 1ns / 1ps
// 在真实Delay/Reverb上验证FX校验快照、音频抢占、命令去重及原子提交。
module tb_fx_control_pipeline(output o_done);
    reg completed=0; // 所有定向检查完成后向夹具报告
    assign o_done=completed; // 仿真完成出口
    reg clk=0,rstn=0; // 50 MHz时钟及异步低有效复位
    always #10 clk=~clk; // 仅驱动功能仿真，不替代STA
    reg [383:0] command=0; // 在请求握手前稳定保持完整命令
    reg [31:0] tag=0; // 每次发送使用新标签，包括重放
    reg [7:0] opcode=0; // C0至C4命令选择
    reg command_valid=0,completion_ready=0; // 请求资格与独立完成反压
    wire command_ready,completion_valid; // DUT接收资格与完成有效位
    wire [127:0] result; // 完整结果，逐位检查状态和查询快照
    wire [31:0] result_tag; // 返回的当前请求标签
    wire [7:0] result_opcode; // 返回的完成操作码
    reg audio_valid=0; // 可在checked完成后插入音频抢占
    reg [31:0] audio_frame=0; // 音频输入帧号
    wire audio_ready,audio_output_valid; // 真实效果链输入与输出握手
    wire [31:0] audio_output_frame; // 检查音频输出顺序
    integer accepted=0,delivered=0,clear_delay=0,clear_reverb=0; // 按实际握手与清空脉冲计数
    integer audio_inputs=0,audio_outputs=0,preemptions=0,isolation_checks=0; // 音频与校验边界覆盖
    reg held_valid=0; // 上一采样沿完成输出处于暂停
    reg [167:0] held_completion=0; // 暂停期间完整包必须稳定
    reg [319:0] delay_payload=0,reverb_payload=0; // 草稿配置的独立期望值
    reg [127:0] expected_query=0; // 独立构造查询结果，不能使用DUT快照作为参考
    reg [31:0] blocked_tag=0; // 被反压的旧完成包标签
    reg saved_apply=0; // 无时钟参数翻转前保存执行使能

    AxisFxEngine #(.C_DELAY_ADDR_BITS(13)) Dut( // 使用真实共享效果域及实际参数边界
        .i_axis_aclk(clk),.i_axis_arstn(rstn),.i_s_axis_tdata(command),
        .i_s_axis_tuser(tag),.i_s_axis_tdest(opcode),.i_s_axis_tvalid(command_valid),
        .o_s_axis_tready(command_ready),.o_m_axis_tdata(result),.o_m_axis_tuser(result_tag),
        .o_m_axis_tdest(result_opcode),.o_m_axis_tvalid(completion_valid),.i_m_axis_tready(completion_ready),
        .i_audio_data(64'd0),.i_audio_frame(audio_frame),.i_audio_valid(audio_valid),.o_audio_ready(audio_ready),
        .o_audio_data(),.o_audio_frame(audio_output_frame),.o_audio_valid(audio_output_valid),.i_audio_ready(1'b1),
        .o_frames(),.o_clipped_frames(),.o_cycles()
    );

    // 只按接口握手和真实清空引脚计数；复位取消的一个完成包在结束时单独核对。
    always @(posedge clk) begin
        if(!rstn) held_valid=0;
        else begin
            if(held_valid && (!completion_valid || {result_opcode,result_tag,result}!==held_completion))
                $fatal(1,"completion changed under backpressure");
            held_valid=completion_valid && !completion_ready;
            held_completion={result_opcode,result_tag,result};
            if(command_valid && command_ready) accepted=accepted+1;
            if(completion_valid && completion_ready) delivered=delivered+1;
            if(Dut.flag_clear_delay) clear_delay=clear_delay+1;
            if(Dut.flag_clear_reverb) clear_reverb=clear_reverb+1;
            if(audio_valid && audio_ready) begin
                if(command_valid && command_ready) $fatal(1,"audio and command accepted together");
                audio_inputs=audio_inputs+1;
            end
            if(audio_output_valid) begin
                audio_outputs=audio_outputs+1;
                if(audio_output_frame!==audio_outputs) $fatal(1,"audio frame reordered");
            end
        end
    end

    // 发命令任务：保持输入到握手，显式指定序列号以覆盖重试和错误。
    task start_command; // 在负沿发出完整命令并保持到接收
        input [7:0] operation,address; // 操作码和查询地址
        input [31:0] sequence; // 重放时重复原序列，标签仍递增
        input [319:0] payload; // 按ABI打包的十个参数字
        begin
            @(negedge clk);
            command={sequence,24'h23,address,payload};opcode=operation;tag=tag+1;command_valid=1;
        end
    endtask

    // 等待接受任务：检查真实采样沿，允许旧完成出队同拍接受新命令。
    task accept_command; // 等待一次真实请求握手后撤回VALID
        begin: wait_accept
            forever begin
                @(posedge clk);
                if(command_valid && command_ready) begin
                    #1;@(negedge clk);command_valid=0;disable wait_accept;
                end
            end
        end
    endtask

    // 回读任务：比较完整返回包后再允许消费，不假设完成只持续一个时钟。
    task read_completion; // 验证数据及身份字段后释放完成反压
        input [127:0] expected; // 包含状态、重放位以及查询字段
        input [31:0] expected_tag; // 应返回本次请求标签
        input [7:0] expected_opcode; // 对应操作码
        begin
            while(!completion_valid) @(negedge clk);
            if(result!==expected || result_tag!==expected_tag || result_opcode!==expected_opcode)
                $fatal(1,"completion mismatch tag=%0d expected=%h actual=%h",expected_tag,expected,result);
            completion_ready=1;
            @(posedge clk);#1;@(negedge clk);completion_ready=0;
        end
    endtask

    // 音频抢占任务：命令checked后插入音频，必须撤销旧快照且不执行控制动作。
    task preempt_with_audio; // 在已校验但尚未执行的边界插入音频
        begin
            wait(Dut.flag_checked===1'b1);
            @(negedge clk);audio_frame=audio_frame+1;audio_valid=1;
            #1;
            if(command_ready || !audio_ready || Dut.flag_apply || Dut.flag_clear_delay || Dut.flag_clear_reverb)
                $fatal(1,"audio did not preempt checked command");
            @(posedge clk);#1;
            if(Dut.flag_checked || Dut.flag_packet_decoded) $fatal(1,"audio kept stale snapshot");
            @(negedge clk);audio_valid=0;preemptions=preemptions+1;
        end
    endtask

    // 超时保护避免缺失握手被误判为仍在计算。
    initial begin
        #2000000;$fatal(1,"FX control test timeout");
    end

    // 全部动作预期由命令语义给出，未通过force替换任何DSP或控制逻辑。
    initial begin
        delay_payload={160'd0,32'd1,32'd16777216,32'd0,32'd131072,32'd65536};
        reverb_payload={192'd0,32'd1,32'd16777216,32'd33554432,32'd33554432};
        repeat(3) @(negedge clk);rstn=1;
        start_command(8'hc0,0,0,delay_payload);
        wait(Dut.flag_checked===1'b1);#1;
        saved_apply=Dut.flag_apply;
        command[31]=!command[31];#1;
        if(!saved_apply || Dut.flag_apply!==saved_apply) $fatal(1,"raw parameter leaked to checked apply");
        command[31]=!command[31];isolation_checks=isolation_checks+1;
        accept_command;
        blocked_tag=tag;
        if(Dut.reg_delay_draft!==delay_payload[159:0] || Dut.reg_delay_active[127:96]!==0)
            $fatal(1,"draft updated active configuration");

        start_command(8'hc4,0,1,0);
        preempt_with_audio;
        wait(!Dut.flag_audio_busy);preempt_with_audio;
        wait(!Dut.flag_audio_busy);wait(Dut.flag_checked===1'b1);
        @(negedge clk);
        if(command_ready) $fatal(1,"completion pressure failed to block command");
        fork
            read_completion(0,blocked_tag,8'hc0);
            accept_command;
        join
        expected_query=0;expected_query[31:0]=2;expected_query[127:96]=72;
        read_completion(expected_query,tag,8'hc4);

        start_command(8'hc1,0,2,reverb_payload);accept_command;read_completion(0,tag,8'hc1);
        if(Dut.reg_reverb_active!==0) $fatal(1,"reverb draft activated early");
        start_command(8'hc2,0,3,0);preempt_with_audio;
        if(Dut.cnt_revision!==0 || Dut.reg_delay_active[127:96]!==0 || Dut.reg_reverb_active!==0)
            $fatal(1,"commit raced audio acceptance");
        accept_command;
        if(Dut.cnt_revision!==1 || Dut.reg_delay_active!==delay_payload[159:0] || Dut.reg_reverb_active!==reverb_payload[127:0])
            $fatal(1,"atomic commit mismatch");
        read_completion(128'd1,tag,8'hc2);

        start_command(8'hc3,0,4,320'd3);preempt_with_audio;accept_command;read_completion(0,tag,8'hc3);
        start_command(8'hc3,0,4,320'd3);accept_command;read_completion(128'h1000000000000000000,tag,8'hc3);
        start_command(8'hc3,0,4,320'd1);accept_command;read_completion(128'h50000000000000000,tag,8'hc3);
        start_command(8'hc0,0,5,0);accept_command;read_completion(128'h80000000000000000,tag,8'hc0);
        start_command(8'hc0,0,5,0);accept_command;read_completion(128'h1080000000000000000,tag,8'hc0);
        start_command(8'hc2,0,6,320'd1);accept_command;read_completion(128'h80000000000000000,tag,8'hc2);
        if(Dut.cnt_revision!==1 || clear_delay!=1 || clear_reverb!=1 || Dut.reg_delay_draft!==delay_payload[159:0])
            $fatal(1,"retry or rejected command changed state");

        start_command(8'hc4,0,7,0);accept_command;
        start_command(8'hc3,0,8,320'd3);wait(Dut.flag_checked===1'b1);
        @(negedge clk);rstn=0;command_valid=0;
        #1;
        if(Dut.flag_checked || completion_valid || Dut.cnt_revision!==0 || Dut.flag_clear_delay || Dut.flag_clear_reverb)
            $fatal(1,"reset failed to cancel pending control");
        repeat(3) @(negedge clk);rstn=1;
        start_command(8'hc4,0,0,0);accept_command;read_completion(0,tag,8'hc4);
        if(accepted!=12 || delivered!=11 || clear_delay!=1 || clear_reverb!=1 ||
            audio_inputs!=4 || audio_outputs!=4 || preemptions!=4 || isolation_checks!=1)
            $fatal(1,"coverage mismatch accepted=%0d delivered=%0d audio=%0d/%0d",accepted,delivered,audio_inputs,audio_outputs);
        completed=1;
        $display("PASS fx_control_pipeline accepted=%0d delivered=%0d reset_cancelled=1 audio=%0d preemptions=%0d clears=%0d/%0d isolation_checks=%0d",accepted,delivered,audio_outputs,preemptions,clear_delay,clear_reverb,isolation_checks);
        $finish;
    end
endmodule
