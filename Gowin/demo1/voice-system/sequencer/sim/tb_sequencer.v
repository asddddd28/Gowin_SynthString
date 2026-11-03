`timescale 1ns / 1ps
module tb_sequencer;
    reg clk=0,rstn=0;
    always #10 clk=~clk;
    reg [5:0] buttons=0;
    reg capture=0,local_request=0,ready=1,response_valid=0;
    reg [4:0] key=0;
    reg [391:0] event_data=0;
    reg [7:0] opcode=0;
    reg [63:0] words=0;
    reg [135:0] response=0;
    wire [391:0] request;
    wire request_valid,response_ready,local_valid,click,accent,recording;
    wire [135:0] local_response;
    wire [3:0] locks;
    wire [8:0] bpm;
    wire [31:0] status;
    reg [31:0] active_id[0:7];
    reg [7:0] active=0;
    integer slot=0,on_count=0,off_count=0,slot_a=0,slot_b=0,beats=0,k,n;
    reg [391:0] held_request;
    reg held_valid=0;
    SynthSequencer #(.C_DEBOUNCE(4),.C_US_CYCLES(1),.C_PPQ(4),.C_ADDRESS_BITS(6),.C_EARLY_WINDOW(0)) dut(
        .i_clk(clk),.i_rstn(rstn),.i_enabled(1'b1),.i_silent(1'b0),.i_buttons(buttons),
        .i_capture(capture),.i_key(key),.i_event(event_data),.o_request(request),.o_request_valid(request_valid),.i_request_ready(ready),
        .i_response(response),.i_response_valid(response_valid),.o_response_ready(response_ready),
        .i_local_request(local_request),.i_opcode(opcode),.i_argument(8'd0),.i_words(words),.o_local_valid(local_valid),.o_local_response(local_response),
        .o_patch_lock(locks),.o_click(click),.o_accent(accent),.o_recording(recording),.o_bpm(bpm),.o_status(status));

    always @(posedge clk)begin
        if(rstn)begin
            if(click)beats=beats+1;
            if(held_valid && request!==held_request)$fatal(1,"request changed under backpressure");
            held_valid=request_valid && !ready;
            held_request=request;
            if(response_valid && response_ready)response_valid<=0;
            if(request_valid && ready)begin
                if(response_valid)$fatal(1,"more than one request outstanding");
                response<=0;response_valid<=1;
                if(request[31:28]!=4)$fatal(1,"replay identity overlaps live key namespace");
                if(request[327:320]==8'ha4)begin
                    on_count=on_count+1;
                    if(request[329:328]==0)slot_a=slot_a+1;
                    if(request[329:328]==1)slot_b=slot_b+1;
                    for(k=0;k<8;k=k+1)if(active[k] && active_id[k]==request[31:0])$fatal(1,"reused held NoteID");
                    active_id[slot]=request[31:0];active[slot]=1;response[2:0]<=slot;slot=(slot+1)%8;
                end else if(request[327:320]==8'ha5)begin
                    off_count=off_count+1;
                    for(k=0;k<8;k=k+1)if(active_id[k]==request[31:0])active[k]=0;
                end else $fatal(1,"unexpected playback opcode");
            end
        end
    end

    task control;
        input [31:0] action;
        input [31:0] value;
        begin
            @(negedge clk);opcode=8'h42;words={value,action};local_request=1;
            @(negedge clk);local_request=0;
            if(!local_valid || local_response[135:128]!=0)$fatal(1,"control failed %0d",action);
        end
    endtask
    task note;
        input [4:0] note_key;
        input press;
        input [1:0] patch;
        begin
            @(negedge clk);key=note_key;event_data=0;capture=1;
            event_data[327:320]=press ? 8'ha4 : 8'ha5;
            event_data[329:328]=patch;event_data[63:32]=32'd19327353;
            event_data[95:64]=32'd52953088;event_data[159:128]={1'b1,17'd0,7'd100,7'd60};
            @(negedge clk);capture=0;
        end
    endtask
    task position;
        input [19:0] value;
        begin wait(dut.reg_position==value);@(negedge clk);end
    endtask

    initial begin
        for(k=0;k<8;k=k+1)active_id[k]=0;
        #100;@(negedge clk);rstn=1;
        control(1,0);note(0,1,0);position(2);control(1,0);
        wait(!dut.flag_finalizing);repeat(3)@(negedge clk);
        if(dut.reg_length!=0 || dut.cnt_saved!=0 || status[1] || locks!=0)$fatal(1,"short recording retained");
        $display("PASS no complete bar means no saved loop");
        beats=0;
        control(1,0);position(1);note(0,1,0);position(2);note(0,0,0);
        position(17);note(3,1,2);position(18);control(1,0);
        wait(!dut.flag_finalizing);repeat(3)@(negedge clk);
        if(dut.reg_length!=16 || dut.cnt_saved!=2 || locks!=1 || !status[1])$fatal(1,"bar trim or patch lock failed %0d %0d",dut.reg_length,dut.cnt_saved);
        wait(on_count>=3);if(beats!=5)$fatal(1,"metronome four beats plus next downbeat %0d",beats);
        $display("PASS complete-bar trim and automatic loop, metronome stops");
        position(1);control(1,0);note(1,1,1);position(3);note(1,0,1);
        position(0);position(2);control(1,0);wait(!dut.flag_finalizing);
        if(dut.cnt_saved!=4 || dut.reg_length!=16 || locks!=3)$fatal(1,"overdub failed");
        wait(slot_b>=2);if(slot_a<3)$fatal(1,"base layer disappeared");
        $display("PASS overdub retains original loop length and separate patch slots");
        // Pause, resume and clear while the command bus refuses an offered request.
        control(3,0);repeat(200)@(negedge clk);if(active!=0)$fatal(1,"pause left a held voice");
        control(3,0);wait(request_valid);@(negedge clk);ready=0;
        wait(request_valid);held_request=request;control(2,0);repeat(50)@(negedge clk);ready=1;
        repeat(400)@(negedge clk);
        if(active!=0 || dut.cnt_saved!=0 || status[1:0]!=0 || locks!=0)$fatal(1,"clear failed under backpressure");
        $display("PASS clear under AXI backpressure holds transaction and releases only playback IDs");
        // Preserve a two-bar first take, then close an overdub at its last complete bar.
        control(1,0);position(1);note(0,1,0);position(34);control(1,0);
        wait(!dut.flag_finalizing);repeat(3)@(negedge clk);
        if(dut.reg_length!=32 || dut.cnt_saved!=1 || locks!=1)$fatal(1,"two-bar held take failed");
        position(8);control(1,0);position(10);note(1,1,1);position(18);control(1,0);
        wait(!dut.flag_finalizing);repeat(3)@(negedge clk);
        if(dut.cnt_saved!=3 || dut.reg_length!=32 || locks!=3)$fatal(1,"truncated held overdub missing closing off");
        if({dut.mem_event_b[2][1:0],dut.mem_event_a[2]}!=16 || dut.mem_event_e[2][6])$fatal(1,"closing off has wrong position/type");
        position(31);position(0);position(20);control(2,0);repeat(400)@(negedge clk);
        if(active!=0)$fatal(1,"held notes survived final clear");
        $display("PASS multi-bar loop and truncated long-note overdub");
        // A first note on a boundary starts the new window; retain it only
        // after a complete bar from that origin, without a leading empty bar.
        control(1,0);position(15);wait(dut.flag_tick);@(negedge clk);
        key=2;capture=1;event_data=0;event_data[327:320]=8'ha4;event_data[329:328]=2;
        event_data[159:128]={1'b1,17'd0,7'd100,7'd60};
        @(negedge clk);capture=0;position(17);control(1,0);wait(!dut.flag_finalizing);repeat(3)@(negedge clk);
        if(dut.cnt_saved!=1 || locks!=4)$fatal(1,"bar-edge capture lost");
        if({dut.mem_event_b[0][1:0],dut.mem_event_a[0]}!=0)$fatal(1,"boundary first note assigned to previous bar");
        control(2,0);repeat(400)@(negedge clk);
        control(4,137);if(bpm!=137)$fatal(1,"BPM write failed");
        @(negedge clk);buttons=6'b000100;repeat(50)@(negedge clk);buttons=0;repeat(10)@(negedge clk);
        if(bpm!=137)$fatal(1,"save button changed BPM");
        control(1,0);
        for(n=0;n<16;n=n+1)begin note(n,1,0);note(n,0,0);end
        wait(!dut.flag_finalizing && !recording);repeat(4)@(negedge clk);
        if(!status[3] || dut.cnt_saved!=0)$fatal(1,"capacity overflow corrupted saved loop");
        $display("PASS debounced controls, adjustable BPM, bounded full-buffer stop");
        $display("PASS sequencer");$finish;
    end
    initial begin #20000000;$fatal(1,"sequencer watchdog");end
endmodule
