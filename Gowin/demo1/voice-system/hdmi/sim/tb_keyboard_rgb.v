`timescale 1ns/1ps
module tb_keyboard_rgb;
    reg clk=0;
    always #10 clk=~clk;
    reg rstn=0,calibrating=0,request=0;
    reg [31:0] pressed=0;
    reg [7:0] opcode=0,argument=0;
    reg [63:0] words=0;
    wire valid,rgb;
    wire [135:0] response;
    integer edges=0,frames=0,pulses=0,high_cycles=0;
    SynthKeyboardRgb #(.C_FRAME_CYCLES(60000)) dut(
        .i_clk(clk),.i_rstn(rstn),.i_pressed(pressed),.i_calibrating(calibrating),
        .i_request(request),.i_opcode(opcode),.i_argument(argument),.i_words(words),
        .o_response_valid(valid),.o_response(response),.o_rgb(rgb));
    always @(posedge clk) if(rstn) begin
        if(dut.wire_press!=0) edges=edges+1;
        if(dut.flag_frame) frames=frames+1;
    end
    // Observe the output pin, not internal serializer data.
    always @(negedge clk) if(rstn) begin
        if(rgb) high_cycles=high_cycles+1;
        else if(high_cycles!=0) begin
            if(high_cycles!=15 && high_cycles!=42) $fatal(1,"WS2812 pulse %0d",high_cycles);
            pulses=pulses+1;high_cycles=0;
        end
    end
    task command;
        input [7:0] op,arg;
        input [63:0] data;
        input [7:0] status;
        begin
            @(negedge clk);opcode=op;argument=arg;words=data;request=1;
            @(negedge clk);
            if(!valid || response[135:128]!=status) $fatal(1,"command %h status %h",op,response[135:128]);
            request=0;
            @(negedge clk);if(valid) $fatal(1,"repeated response");
        end
    endtask
    integer mode;
    initial begin
        repeat(4) @(negedge clk);rstn=1;
        command(8'h18,0,0,0);
        if(response[31:0]!=32'h52474231 || response[63:32]!=1) $fatal(1,"identity/default");
        pressed=1;repeat(120010) @(negedge clk);
        if(edges!=1 || frames<2 || pulses<768) $fatal(1,"hold/frame regression");
        pressed=0;repeat(2) @(negedge clk);pressed=1;repeat(2) @(negedge clk);
        if(edges!=2) $fatal(1,"repress lost");
        calibrating=1;pressed=32'h80000000;repeat(2) @(negedge clk);
        calibrating=0;repeat(2) @(negedge clk);
        if(edges!=2 || dut.Effects_Inst.mem_timer[31]!=0) $fatal(1,"calibration retrigger");
        for(mode=0;mode<=6;mode=mode+1) begin
            command(8'h19,mode,1,mode==5 ? 5 : 0);
            if(mode!=5) begin
                command(8'h18,0,0,0);
                if(response[63:32]!=(256+mode)) $fatal(1,"mode readback");
            end
        end
        command(8'h19,3,2,5);command(8'h19,7,0,5);command(8'h18,1,0,5);
        command(8'h18,0,0,0);
        if(response[63:32]!=262) $fatal(1,"bad request mutated mode");
        repeat(60000) @(negedge clk);
        $display("PASS keyboard RGB: edges, held-key suppression, calibration, modes, reject/readback, %0d WS2812 pulses",pulses);
        $finish;
    end
    initial begin #20000000;$fatal(1,"timeout");end
endmodule
