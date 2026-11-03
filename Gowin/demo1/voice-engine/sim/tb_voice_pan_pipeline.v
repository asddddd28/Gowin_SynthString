`timescale 1ns / 1ps
// 定向验证真实Voice声像流水寄存器；完整声音与命令行为由整链回归覆盖。
module tb_voice_pan_pipeline(output o_done);
    reg completed=0; // 对外指示所有定向检查已经结束
    assign o_done=completed; // 仿真夹具的完成出口
    reg clk=0, rstn=0; // 内部时钟及异步低有效复位
    always #10 clk=~clk; // 50 MHz功能仿真时钟，不代替物理时序分析
    reg [4:0] drive_state=0; // 定向驱动真实状态输出逻辑，跳过与声像无关的算子计算
    reg [31:0] pan=0; // 合法范围为0至2^26，覆盖两端与中心相邻LSB
    reg signed [31:0] sample=0; // 覆盖完整signed32范围，不假设信号已限制在满刻度内
    reg signed [63:0] voice_product=0; // 按原接口将测试音频放入product[57:26]
    reg signed [63:0] expected_left=0, expected_right=0; // 直接使用原始32位系数乘法作为独立数值参考
    reg [63:0] previous_left=0, previous_right=0; // 证明乘法拍不会提前修改输出
    reg [39:0] previous_sum_left=0, previous_sum_right=0; // 证明非活动声部不会重复累加前一声部
    reg [31:0] random_state=32'h70616e31; // 可复现的随机音频与声像激励
    integer vector_index=0, checked=0, resets=0; // 边界、随机检查与流水中复位覆盖计数

    VoiceSynthEngine Dut( // 只替换状态、输入音频和已限幅声像，使用真实计算与清零逻辑
        .i_axis_aclk(clk),.i_axis_arstn(rstn),.i_s_axis_tdata(384'd0),
        .i_s_axis_tuser(32'd0),.i_s_axis_tdest(8'd0),.i_s_axis_tvalid(1'b0),
        .o_s_axis_tready(),.o_m_axis_tdata(),.o_m_axis_tuser(),.o_m_axis_tdest(),
        .o_m_axis_tvalid(),.i_m_axis_tready(1'b1),.i_sample_tick(1'b0),
        .o_pcm_valid(),.o_pcm_data(),.o_frame(),.o_overruns(),.o_render_cycles(),.o_active()
    );

    // force仅用于隔离声像计算；完整状态机调度另外由真实八声部测试验证。
    initial begin
        force Dut.reg_state=drive_state;
        force Dut.reg_mod_pan=pan;
        force Dut.reg_voice_product=voice_product;
        repeat(3) @(negedge clk);
        rstn=1;
        for(vector_index=0;vector_index<2090;vector_index=vector_index+1) begin
            random_state=random_state^(random_state<<13);
            random_state=random_state^(random_state>>17);
            random_state=random_state^(random_state<<5);
            sample=random_state;
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            pan=random_state%67108865;
            if(vector_index<90) begin
                case(vector_index/9)
                    0: sample=32'sh80000000;
                    1: sample=32'sh80000001;
                    2: sample=-67108865;
                    3: sample=-67108864;
                    4: sample=-1;
                    5: sample=0;
                    6: sample=1;
                    7: sample=67108863;
                    8: sample=67108864;
                    default: sample=32'sh7fffffff;
                endcase
                case(vector_index%9)
                    0: pan=0;
                    1: pan=1;
                    2: pan=2;
                    3: pan=33554431;
                    4: pan=33554432;
                    5: pan=33554433;
                    6: pan=67108862;
                    7: pan=67108863;
                    default: pan=67108864;
                endcase
            end
            voice_product={{6{sample[31]}},sample,26'd0};
            expected_left=sample*$signed(32'd67108864-pan);
            expected_right=sample*$signed(pan);
            @(negedge clk); drive_state=16;
            @(posedge clk); #1;
            if(Dut.reg_pan_left!==(27'd67108864-pan) || Dut.reg_pan_right!==pan)
                $fatal(1,"pan coefficient mismatch vector=%0d",vector_index);
            previous_left=Dut.reg_left_product; previous_right=Dut.reg_right_product;
            @(negedge clk); drive_state=7;
            @(posedge clk); #1;
            if(Dut.reg_left_product!==previous_left || Dut.reg_right_product!==previous_right)
                $fatal(1,"pan result changed before final stage");
            if(Dut.dec_next_state!==5'd18) $fatal(1,"pan FSM missing product boundary");
            @(negedge clk); drive_state=18;
            @(posedge clk); #1;
            if(Dut.reg_left_product!==expected_left || Dut.reg_right_product!==expected_right)
                $fatal(1,"pan product mismatch vector=%0d sample=%h pan=%h",vector_index,sample,pan);
            if(Dut.dec_next_state!==5'd8) $fatal(1,"pan FSM missing accumulation boundary");
            checked=checked+1;
            @(negedge clk); drive_state=8;
            @(posedge clk); #1;
            previous_sum_left=Dut.reg_left_sum; previous_sum_right=Dut.reg_right_sum;
            @(negedge clk); drive_state=1;
            @(posedge clk); #1;
            if(Dut.reg_left_product!==0 || Dut.reg_right_product!==0 || Dut.dec_next_state!==5'd8)
                $fatal(1,"inactive voice failed to clear products or preserve fast path");
            @(negedge clk); drive_state=8;
            @(posedge clk); #1;
            if(Dut.reg_left_sum!==previous_sum_left || Dut.reg_right_sum!==previous_sum_right)
                $fatal(1,"inactive voice leaked previous sample");
            if(vector_index%199==0) begin
                @(negedge clk); drive_state=7;
                @(posedge clk); #1;
                @(negedge clk); drive_state=0; rstn=0;
                #1;
                if(Dut.reg_pan_left_raw!==0 || Dut.reg_pan_right_raw!==0 || Dut.reg_pan_sample!==0 ||
                    Dut.reg_left_product!==0 || Dut.reg_right_product!==0 || Dut.reg_pan_left!==0 || Dut.reg_pan_right!==0)
                    $fatal(1,"reset left stale pan pipeline state");
                @(negedge clk); rstn=1; resets=resets+1;
            end
        end
        if(checked!=2090 || resets!=11) $fatal(1,"pan coverage incomplete");
        completed=1;
        $display("PASS voice_pan_pipeline vectors=%0d exact_products=%0d inactive_checks=%0d mid_pipeline_resets=%0d",checked,checked*2,checked,resets);
        $finish;
    end
endmodule
