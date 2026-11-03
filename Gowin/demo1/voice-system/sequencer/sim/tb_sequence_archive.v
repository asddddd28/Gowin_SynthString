`timescale 1ns / 1ps
// Verify archive leases and atomic publication using the actual event RAM.
module tb_sequence_archive;
    reg clk=0,rstn=0,request=0;
    always #10 clk=~clk;
    reg [7:0] opcode=0;
    reg [63:0] words=0;
    reg [5:0] buttons=0;
    wire valid;
    wire [135:0] reply;
    wire [3:0] locks;
    wire [31:0] status;
    wire [8:0] bpm;
    reg [89:0] first,second;
    reg [135:0] saved_reply;
    integer timeout;
    SynthSequencer #(.C_DEBOUNCE(2),.C_ADDRESS_BITS(6),.C_ARCHIVE_TIMEOUT(200)) dut(
        .i_clk(clk),.i_rstn(rstn),.i_enabled(1'b1),.i_silent(1'b0),.i_buttons(buttons),
        .i_capture(1'b0),.i_key(5'd0),.i_event(392'd0),.i_request_ready(1'b1),
        .i_response(136'd0),.i_response_valid(1'b0),
        .i_local_request(request),.i_opcode(opcode),.i_argument(8'd0),.i_words(words),
        .o_local_valid(valid),.o_local_response(reply),.o_patch_lock(locks),.o_status(status),.o_bpm(bpm));

    task transaction;
        input [7:0] command;
        input [63:0] payload;
        input [7:0] expected;
        begin
            @(negedge clk);opcode=command;words=payload;request=1;
            @(negedge clk);request=0;timeout=0;
            while(!valid && timeout<20)begin @(negedge clk);timeout=timeout+1;end
            if(!valid || reply[135:128]!==expected)$fatal(1,"archive op=%h expected=%d reply=%h",command,expected,reply);
            saved_reply=reply;
        end
    endtask
    task insert;
        input [31:0] index;
        input [89:0] event_data;
        begin
            transaction(8'h46,event_data[63:0],0);
            transaction(8'h47,{index,6'd0,event_data[89:64]},0);
        end
    endtask
    initial begin
        first=0;first[19:0]=20;first[61:30]=19327353;first[68:62]=99;
        first[75:69]=60;first[77:76]=2;first[78]=1;first[79]=1;first[84:80]=3;
        second=180;
        repeat(5)@(negedge clk);rstn=1;
        transaction(8'h43,0,0);if(saved_reply[31:0]!=32'h41524331)$fatal(1,"archive identity");
        transaction(8'h44,0,5);
        transaction(8'h45,2,0);
        if(locks!=15 || !status[5])$fatal(1,"lease does not protect patches");
        transaction(8'h42,1,10);transaction(8'h42,2,10);transaction(8'h42,{32'd90,32'd4},10);
        @(negedge clk);buttons=6'b001111;repeat(10)@(negedge clk);buttons=0;repeat(10)@(negedge clk);
        if(status[0] || bpm!=120 || dut.cnt_saved!=0)$fatal(1,"physical control changed archive");
        transaction(8'h47,0,5);
        insert(0,first);if(dut.cnt_saved!=0)$fatal(1,"partial import visible");
        transaction(8'h46,second[63:0],0);
        transaction(8'h47,{32'd3,32'd0},5);
        transaction(8'h47,{32'd1,32'd0},0);
        transaction(8'h48,{32'd1,16'd111,16'd3},5);
        transaction(8'h48,{32'd512,16'd111,16'd2},5);
        transaction(8'h48,{32'd1,16'd111,16'd2},0);
        if(dut.cnt_saved!=2 || dut.reg_length!=3840 || bpm!=111 || locks!=4 || status[5:0]!=0)$fatal(1,"atomic publish");
        transaction(8'h45,2,10);
        transaction(8'h45,1,0);
        transaction(8'h41,0,0);
        if(saved_reply[127:124]!=4 || saved_reply[11:8]!=15)$fatal(1,"saved slots confused with lease locks");
        transaction(8'h44,0,0);if(saved_reply[89:0]!==first || saved_reply[127:96]!=1)$fatal(1,"first read mismatch %h",saved_reply);
        transaction(8'h44,1,0);if(saved_reply[89:0]!==second)$fatal(1,"second read mismatch");
        transaction(8'h44,2,5);
        transaction(8'h45,0,0);
        @(negedge clk);buttons=6'b000100;repeat(50)@(negedge clk);buttons=0;repeat(10)@(negedge clk);
        transaction(8'h49,0,0);
        if(saved_reply[31:0]!=1 || bpm!=111)$fatal(1,"save edge repeated or changed BPM");
        @(negedge clk);buttons=6'b010000;repeat(12)@(negedge clk);buttons=0;repeat(10)@(negedge clk);
        @(negedge clk);buttons=6'b100000;repeat(12)@(negedge clk);buttons=0;repeat(10)@(negedge clk);
        transaction(8'h49,0,0);
        if(saved_reply[63:32]!=1 || saved_reply[95:64]!=1 || status[1])$fatal(1,"library navigation started audio or lost event");
        transaction(8'h42,2,0);
        transaction(8'h45,2,0);insert(0,first);transaction(8'h45,0,0);
        if(dut.cnt_saved!=0 || locks!=0)$fatal(1,"abort published partial image");
        transaction(8'h45,2,0);insert(0,first);
        repeat(220)@(negedge clk);
        if(status[5] || dut.cnt_saved!=0 || locks!=0)$fatal(1,"lease timeout failed");
        transaction(8'h45,2,0);
        transaction(8'h46,0,0);transaction(8'h47,{32'd0,32'h200000},5);
        transaction(8'h45,0,0);
        $display("PASS sequence_archive atomic=PASS roundtrip=PASS controls_lock=PASS timeout=PASS malformed=PASS");$finish;
    end
    initial begin #1000000;$fatal(1,"archive watchdog");end
endmodule
