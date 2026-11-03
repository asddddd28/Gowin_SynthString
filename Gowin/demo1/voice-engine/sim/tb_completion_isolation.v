`timescale 1ns / 1ps
// 公共完成通道单元验证：受控三源替代DSP结果，真实子模块另由整链回归覆盖。
module tb_completion_isolation;
    reg clk=0, rstn=0, ready=0; // 测试时钟、低有效复位与消费端反压
    always #5 clk=~clk; // 10 ns 周期仅用于离散握手验证，不代替物理时序约束
    reg [2:0] source_valid=0, sent=0; // 三源持包资格及最近采样沿已接受标记
    reg [167:0] source_legacy=0, source_voice=0, source_fx=0; // 独立保持三个源的完整完成包
    reg [31:0] serial_legacy=0, serial_voice=0, serial_fx=0; // 每源独立递增标签，用于定位丢失或重复
    reg [31:0] random_state=32'h7ad32e19; // 固定种子的伪随机到达与反压序列
    wire [127:0] result; // DUT 返回的结果载荷
    wire [31:0] tag; // DUT 返回的透明事务标签
    wire [7:0] opcode; // DUT 返回的完成操作码
    wire valid, last; // DUT 输出有效资格与原子包尾
    wire [167:0] packet={opcode,tag,result}; // 按协议字段重建全包供独立队列比较
    wire [2:0] source_ready={Dut.FxDomain.Fx_Inst.i_m_axis_tready, // 观察实际连接到三个完成源的接受条件
        Dut.Voice_Inst.i_m_axis_tready,(Dut.flag_advance && Dut.flag_take_legacy)};
    reg [167:0] expected [0:16383]; // 参考队列只保存真实输入握手的完整包
    integer read_index=0, write_index=0, occupancy=0, priority_expected=0; // 队列位置、占用和独立轮询优先级
    integer cycle=0, selected, k; // 激励周期、模型选中源及轮询遍历索引
    integer accepted=0, delivered=0, cancelled=0; // 接收、交付及复位取消的守恒统计
    integer coverage_empty=0, coverage_full=0, coverage_both=0; // 空、满及同时入出队覆盖
    integer coverage_stall=0, coverage_reset=0, isolation_checks=0; // 暂停、带在途包复位及组合隔离覆盖
    integer domain_legacy=0, domain_voice=0, domain_fx=0; // 分源接收计数检查轮询进展
    reg held_valid=0; // 前一采样沿有输出被反压
    reg [167:0] held_packet=0; // 前一暂停输出，用于稳定性比较
    reg [2:0] saved_ready; // 翻转下游 READY 前保存三源 READY
    reg saved_downstream; // 隔离探测结束后恢复原下游 READY

    // 真实互联结构保留，完成源在下方受控替换，音频接口持续允许消费。
    AxisSynthSystem #(.LEGACY_ENABLE(0),.C_DELAY_ADDR_BITS(13)) Dut( // 固定板级参数以复现相同完成路由
        .i_axis_aclk(clk),.i_axis_arstn(rstn),.i_s_axis_tdata(384'd0),
        .i_s_axis_tuser(32'd0),.i_s_axis_tdest(8'd0),.i_s_axis_tlast(1'b1),
        .i_s_axis_tvalid(1'b0),.o_s_axis_tready(),
        .o_m_axis_tdata(result),.o_m_axis_tuser(tag),.o_m_axis_tdest(opcode),
        .o_m_axis_tlast(last),.o_m_axis_tvalid(valid),.i_m_axis_tready(ready),
        .i_pcm_ready(1'b1)
    );

    // 仅替换结果生产端，不替换缓冲、轮询或 READY 反馈逻辑。
    initial begin
        force Dut.flag_legacy_valid=source_valid[0];
        force Dut.flag_voice_valid=source_valid[1];
        force Dut.flag_fx_valid=source_valid[2];
        force Dut.wire_legacy_result=source_legacy[127:0];
        force Dut.wire_legacy_tag=source_legacy[159:128];
        force Dut.wire_legacy_opcode=source_legacy[167:160];
        force Dut.wire_voice_result=source_voice[127:0];
        force Dut.wire_voice_tag=source_voice[159:128];
        force Dut.wire_voice_opcode=source_voice[167:160];
        force Dut.wire_fx_result=source_fx[127:0];
        force Dut.wire_fx_tag=source_fx[159:128];
        force Dut.wire_fx_opcode=source_fx[167:160];
    end

    // 在采样沿观察真实三源接收与下游消费，模型以队列记录全包，独立检查轮询顺序。
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            if (occupancy!=0) coverage_reset=coverage_reset+1;
            cancelled=cancelled+occupancy;
            occupancy=0; read_index=0; write_index=0;
            priority_expected=0; held_valid=0; sent=0;
        end else begin
            if (valid !== (occupancy!=0)) $fatal(1,"completion occupancy/VALID mismatch");
            if (valid && ((^packet)===1'bx || last!==1'b1)) $fatal(1,"unknown completion packet");
            if (held_valid && (valid!==1'b1 || packet!==held_packet)) $fatal(1,"stalled completion changed");
            if (occupancy==0) coverage_empty=coverage_empty+1;
            if (occupancy==2) coverage_full=coverage_full+1;
            if (valid && !ready) coverage_stall=coverage_stall+1;
            sent=source_valid & source_ready;
            selected=-1;
            for (k=0;k<3;k=k+1)
                if (selected<0 && source_valid[(priority_expected+k)%3]) selected=(priority_expected+k)%3;
            if (occupancy==2 && sent!=0) $fatal(1,"full queue accepted through combinational lookahead");
            if (occupancy<2 && selected>=0 && sent!==(3'b001<<selected)) $fatal(1,"round-robin acceptance mismatch");
            if (selected<0 && sent!=0) $fatal(1,"accepted absent source");
            if (valid && ready) begin
                if (packet!==expected[read_index]) $fatal(1,"completion lost, duplicated, reordered or corrupted");
                read_index=read_index+1; occupancy=occupancy-1; delivered=delivered+1;
                if (sent!=0) coverage_both=coverage_both+1;
            end
            if (sent!=0) begin
                case (selected)
                    0: begin expected[write_index]=source_legacy; domain_legacy=domain_legacy+1; end
                    1: begin expected[write_index]=source_voice; domain_voice=domain_voice+1; end
                    2: begin expected[write_index]=source_fx; domain_fx=domain_fx+1; end
                    default: $fatal(1,"invalid arbitration grant");
                endcase
                priority_expected=(selected+1)%3;
                write_index=write_index+1; occupancy=occupancy+1; accepted=accepted+1;
            end
            if (occupancy<0 || occupancy>2 || accepted!=delivered+cancelled+occupancy)
                $fatal(1,"completion conservation failure");
            held_valid=valid && !ready;
            held_packet=packet;
        end
    end

    // 源端在接受前保持包；先持续堵塞、再连续传输，随后随机反压并在满队列复位。
    always @(negedge clk) begin
        cycle=cycle+1;
        if (cycle==5 || cycle==2004 || cycle==5004) rstn=1;
        if (cycle==2000 || cycle==5000) rstn=0;
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        if (!rstn) begin
            ready=0; source_valid=0;
        end else begin
            ready=cycle>=120 && (cycle<220 || cycle>=7800 ||
                ((cycle%181)>=50 && random_state[4:2]!=0));
            if ((cycle>=1970 && cycle<2000) || (cycle>=4970 && cycle<5000)) ready=0;
            if (!source_valid[0] || sent[0]) begin
                source_valid[0]=cycle<7800 && (cycle<220 || random_state[5]);
                if (source_valid[0]) begin
                    serial_legacy=serial_legacy+1;
                    source_legacy={8'h10,serial_legacy,32'h4c454741,serial_legacy,32'h12345678,~serial_legacy};
                end
            end
            if (!source_valid[1] || sent[1]) begin
                source_valid[1]=cycle<7800 && (cycle<220 || random_state[6]);
                if (source_valid[1]) begin
                    serial_voice=serial_voice+1;
                    source_voice={8'ha9,serial_voice,32'h564f4943,serial_voice,32'h12345678,~serial_voice};
                end
            end
            if (!source_valid[2] || sent[2]) begin
                source_valid[2]=cycle<7800 && (cycle<220 || random_state[7]);
                if (source_valid[2]) begin
                    serial_fx=serial_fx+1;
                    source_fx={8'hc4,serial_fx,32'h46582020,serial_fx,32'h12345678,~serial_fx};
                end
            end
            // 无时钟沿翻转下游READY，上游三个READY不得发生组合变化。
            #1; saved_ready=source_ready; saved_downstream=ready;
            ready=!ready;
            #1; if (source_ready!==saved_ready) $fatal(1,"downstream READY leaked combinationally to producer");
            ready=saved_downstream; isolation_checks=isolation_checks+1;
        end
        if (cycle==8200) begin
            if (occupancy!=0 || source_valid!=0 || accepted!=delivered+cancelled)
                $fatal(1,"queue failed final drain");
            if (coverage_full<100 || coverage_empty<20 || coverage_both<100 || coverage_reset!=2 ||
                domain_legacy<200 || domain_voice<200 || domain_fx<200)
                $fatal(1,"insufficient completion coverage");
            $display("PASS completion_isolation accepted=%0d delivered=%0d cancelled=%0d full=%0d empty=%0d simultaneous=%0d stalled=%0d resets=%0d isolation_checks=%0d domains=%0d/%0d/%0d",
                accepted,delivered,cancelled,coverage_full,coverage_empty,coverage_both,
                coverage_stall,coverage_reset,isolation_checks,domain_legacy,domain_voice,domain_fx);
            $finish;
        end
    end
endmodule
