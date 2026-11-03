`timescale 1ns / 1ps
// 首音提前20ms窗口与首尾空小节裁剪；回放相邻起音不能多等一小节。
module tb_record_window;
    reg clk=0,rstn=0,capture=0,local_request=0,response_valid=0;
    always #10 clk=~clk;
    reg [391:0] event_data=0;
    reg [63:0] words=0;
    wire [391:0] request;
    wire request_valid,response_ready,local_valid;
    wire [135:0] local_response;
    wire [31:0] status;
    integer ticks=0,on_count=0,previous_on=-1,interval,case_index;
    reg check_period=0;
    SynthSequencer #(.C_US_CYCLES(1),.C_PPQ(64),.C_ADDRESS_BITS(6)) dut(
        .i_clk(clk),.i_rstn(rstn),.i_enabled(1'b1),.i_silent(1'b0),.i_buttons(6'd0),
        .i_capture(capture),.i_key(5'd0),.i_event(event_data),.o_request(request),.o_request_valid(request_valid),.i_request_ready(1'b1),
        .i_response(136'd0),.i_response_valid(response_valid),.o_response_ready(response_ready),
        .i_local_request(local_request),.i_opcode(8'h42),.i_argument(8'd0),.i_words(words),
        .o_local_valid(local_valid),.o_local_response(local_response),.o_status(status));
    always @(posedge clk)begin
        if(rstn && dut.flag_tick)ticks=ticks+1;
        if(response_valid && response_ready)response_valid<=0;
        if(request_valid)begin
            response_valid<=1;
            if(request[327:320]==8'ha4)begin
                on_count=on_count+1;
                if(check_period && previous_on>=0)begin
                    interval=ticks-previous_on;
                    if(interval<255 || interval>257)$fatal(1,"extra playback gap: interval=%d ticks",interval);
                end
                previous_on=ticks;
            end
        end
    end
    task control;
        input [31:0] action;
        begin
            @(negedge clk);words={32'd0,action};local_request=1;
            @(negedge clk);local_request=0;
            if(!local_valid || local_response[135:128]!=0)$fatal(1,"control rejected");
        end
    endtask
    task tempo;
        input [31:0] bpm;
        begin
            @(negedge clk);words={bpm,32'd4};local_request=1;
            @(negedge clk);local_request=0;repeat(105)@(negedge clk);
            if(dut.wire_lead!=bpm*8/25)$fatal(1,"20ms window conversion failed for BPM=%d",bpm);
        end
    endtask
    task at_tick;
        input integer value;
        begin wait(ticks>=value);@(negedge clk);end
    endtask
    task note;
        input pressed;
        begin
            @(negedge clk);capture=1;event_data=0;
            event_data[327:320]=pressed ? 8'ha4 : 8'ha5;
            event_data[63:32]=32'd19327353;event_data[95:64]=32'd67108864;
            event_data[159:128]={1'b1,17'd0,7'd100,7'd60};
            @(negedge clk);capture=0;
        end
    endtask
    task begin_take;
        begin
            check_period=0;control(2);repeat(100)@(negedge clk);
            ticks=0;on_count=0;previous_on=-1;control(1);
        end
    endtask
    task stop_take;
        input integer expected_length;
        input integer expected_first;
        begin
            control(1);wait(!dut.flag_finalizing);repeat(4)@(negedge clk);
            if(dut.reg_length!=expected_length)$fatal(1,"wrong loop length: got=%d expected=%d",dut.reg_length,expected_length);
            if(expected_length!=0 && {dut.mem_event_b[0][1:0],dut.mem_event_a[0]}!=expected_first)
                $fatal(1,"first note belongs to wrong window: got=%d expected=%d",{dut.mem_event_b[0][1:0],dut.mem_event_a[0]},expected_first);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rstn=1;
        begin_take;at_tick(240);note(1);at_tick(280);note(0);at_tick(800);stop_take(256,22);
        check_period=1;wait(on_count>=4);check_period=0;
        $display("PASS early note -16ticks belongs to next bar; four replay attacks have no extra bar");
        for(case_index=0;case_index<3;case_index=case_index+1)begin
            begin_take;at_tick(217+case_index);note(1);at_tick(280);note(0);at_tick(800);
            stop_take(case_index==0 ? 512 : 256,case_index==0 ? 255 : case_index-1);
        end
        $display("PASS before/on/after shifted boundary");
        begin_take;at_tick(217);wait(dut.flag_tick);@(negedge clk);
        capture=1;event_data=0;event_data[327:320]=8'ha4;event_data[63:32]=32'd19327353;
        event_data[95:64]=32'd67108864;event_data[159:128]={1'b1,17'd0,7'd100,7'd60};
        @(negedge clk);capture=0;at_tick(280);note(0);at_tick(800);stop_take(256,0);
        begin_take;at_tick(10);note(1);at_tick(217);wait(dut.flag_tick);@(negedge clk);
        capture=1;event_data[327:320]=8'ha5;
        @(negedge clk);capture=0;at_tick(800);stop_take(256,48);
        if(dut.cnt_saved!=1)$fatal(1,"boundary release created an extra empty bar");
        $display("PASS exact-clock boundary on/off, no added trailing bar");
        begin_take;at_tick(800);note(1);at_tick(850);note(0);at_tick(1600);stop_take(256,70);
        begin_take;at_tick(10);note(1);at_tick(800);stop_take(768,48);
        $display("PASS leading/trailing empty bars trimmed; held note keeps complete length");
        begin_take;at_tick(10);note(1);at_tick(30);note(0);at_tick(522);note(1);at_tick(550);note(0);at_tick(1100);stop_take(768,48);
        $display("PASS intentional middle rest preserved");
        begin_take;at_tick(800);stop_take(0,0);
        begin_take;at_tick(10);note(1);at_tick(30);note(0);at_tick(100);stop_take(0,0);
        if(status[1])$fatal(1,"empty/partial take started playback");
        for(case_index=20;case_index<=300;case_index=case_index+1)tempo(case_index);
        $display("PASS all BPM20..300 offsets without DSP divider");
        $display("PASS record_window");$finish;
    end
    initial begin #250000000;$fatal(1,"record window watchdog");end
endmodule
