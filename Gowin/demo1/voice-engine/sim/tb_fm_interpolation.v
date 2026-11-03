`timescale 1ns / 1ps
// 验证完整接口上的满位宽波表插值、固定十拍延迟、写仲裁、反压与逐拍复位取消。
module tb_fm_interpolation(output o_done);
    reg clk=0, rstn=0, valid=0, ready=0, completed=0; // 单时钟握手激励与结束资格
    reg [671:0] request=0; // 请求字段由独立Python整数参考生成
    reg [159:0] expected=0, held=0; // 当前参考结果和反压期间的结果快照
    reg [31:0] tag=0; // 每个已接纳请求具有不同标识
    reg write_valid=0; // 故意与计算争用写端口以验证计算优先
    reg [10:0] write_address=0; // 两帧波表各1024点
    reg [31:0] write_data=0; // 覆盖完整有符号32位范围
    wire accept, result_valid, write_ready; // 请求、结果及波表写资格
    wire [159:0] result; // 包含音频、相位、包络和噪声状态
    wire [31:0] result_tag; // 结果必须保持原始事务标识
    integer fd=0, code=0, index=0, latency=0, stage=0, checked=0; // 文件、延迟和覆盖计数
    assign o_done=completed; // 仿真完成通知
    always #10 clk=~clk; // 50MHz功能时钟；不代表物理实现已满足50MHz

    AxisFmOperator Dut( // 不替换内部状态；所有边界测试均通过真实接口
        .i_axis_aclk(clk),.i_axis_arstn(rstn),
        .i_s_axis_tdata(request),.i_s_axis_tuser(tag),
        .i_s_axis_tvalid(valid),.o_s_axis_tready(accept),
        .o_m_axis_tdata(result),.o_m_axis_tuser(result_tag),
        .o_m_axis_tvalid(result_valid),.i_m_axis_tready(ready),
        .i_wave_write(write_valid),.i_wave_address(write_address),
        .i_wave_data(write_data),.o_wave_ready(write_ready)
    );

    // 任务：接纳当前参考请求并验证十拍完成、反压保持和计算期间禁止波表写入。
    task check_request; // 请求检查任务：参考数据由外部文件提供
        begin // 任务入口：所有信号仅在下降沿驱动以避免采样竞争
            @(negedge clk);
            valid=1;
            write_valid=1;
            write_address=0;
            write_data=32'h12345678;
            @(posedge clk);
            if(!accept || write_ready) $fatal(1,"request must win table-write arbitration");
            @(negedge clk);
            valid=0;
            latency=1;
            while(!result_valid) begin
                if(write_ready || accept) $fatal(1,"active transaction admitted another producer");
                @(negedge clk);
                latency=latency+1;
                if(latency>10) $fatal(1,"operator exceeded ten-clock deadline");
            end
            if(latency!=10 || result!==expected || result_tag!==tag)
                $fatal(1,"boundary %0d latency=%0d expected=%h actual=%h",tag,latency,expected,result);
            held=result;
            repeat(tag%7+1) begin
                @(negedge clk);
                if(!result_valid || result!==held || result_tag!==tag || write_ready || accept)
                    $fatal(1,"stalled transaction changed");
            end
            write_valid=0;
            ready=1;
            @(negedge clk);
            ready=0;
            if(result_valid || !accept) $fatal(1,"completion did not release operator");
            checked=checked+1;
        end
    endtask

    initial begin // 上传边界素材，执行真实请求并覆盖每个取消点
        repeat(4) @(negedge clk);
        rstn=1;
        fd=$fopen("vectors/fm_interp_upload.txt","r");
        if(!fd) $fatal(1,"missing boundary wave tables");
        for(index=0;index<2048;index=index+1) begin
            @(negedge clk);
            write_valid=1;
            write_address=index;
            code=$fscanf(fd,"%h\n",write_data);
            if(code!=1 || !write_ready) $fatal(1,"table upload not accepted");
        end
        @(negedge clk);
        write_valid=0;
        $fclose(fd);
        fd=$fopen("vectors/fm_interp_boundary.txt","r");
        if(!fd) $fatal(1,"missing interpolation vectors");
        for(index=0;index<960;index=index+1) begin
            code=$fscanf(fd,"%h %h\n",request,expected);
            if(code!=2) $fatal(1,"bad interpolation vector");
            tag=index;
            check_request;
        end
        $fclose(fd);
        // 在每一个计算阶段及结果等待阶段取消；下一次请求不得读取前次乘积。
        for(stage=1;stage<=10;stage=stage+1) begin
            @(negedge clk);
            tag=1000+stage;
            valid=1;
            @(posedge clk);
            if(!accept) $fatal(1,"reset probe not accepted");
            @(negedge clk);
            valid=0;
            repeat(stage-1) @(negedge clk);
            rstn=0;
            repeat(2) @(negedge clk);
            rstn=1;
            repeat(15) begin
                @(negedge clk);
                if(result_valid) $fatal(1,"cancelled operation produced a ghost completion");
            end
            tag=2000+stage;
            check_request;
        end
        // 重查index0，证明所有被拒绝的写都没有污染边界样点；复位也不清空波表。
        fd=$fopen("vectors/fm_interp_boundary.txt","r");
        code=$fscanf(fd,"%h %h\n",request,expected);
        if(code!=2) $fatal(1,"cannot reload first vector");
        $fclose(fd);
        tag=3000;
        check_request;
        $display("PASS fm_interpolation vectors=%0d latency=10 reset_stages=10 upload_points=2048 arbitration=PASS stalls=PASS",checked);
        completed=1;
        $finish;
    end

    initial begin // 独立超时保险，防止握手失效造成仿真不结束
        #5000000;
        $fatal(1,"boundary interpolation watchdog");
    end
endmodule
