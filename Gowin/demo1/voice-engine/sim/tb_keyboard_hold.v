`timescale 1ns/1ps
// Read-only regression of the bridge actually selected by keyboard_latency.gprj.
module tb_keyboard_hold(output o_done);
    reg clk=0, rstn=0, completed=0;
    always #10 clk=!clk;
    assign o_done=completed;
    reg [31:0] pressed=0;
    integer cycle=0, on_count=0, off_count=0, stalls=0;
    wire ready=(cycle%17!=0)&&(cycle%67>7);
    wire frame_done=cycle%16==0;
    wire valid, initialized, patch_ready;
    wire [4:0] voice;
    wire [511:0] data;
    wire [31:0] delivered, events;
    reg held=0;
    reg [516:0] prior;
    reg [31:0] accepted_gates=0;
    always @(negedge clk)begin
        if(!rstn) cycle=0;
        else cycle=cycle+1;
    end
    KeyboardVoiceBridge Dut(
        .i_clk(clk),.i_rstn(rstn),.i_pressed(pressed),.i_frame_done(frame_done),
        .i_patch_valid(1'b0),.o_patch_ready(patch_ready),.i_patch_key(5'd0),.i_patch_data(512'd0),
        .i_velocity({32{7'd100}}),.o_cfg_valid(valid),.i_cfg_ready(ready),
        .o_cfg_voice(voice),.o_cfg_data(data),.o_initialized(initialized),.o_delivered(delivered),.o_events(events)
    );
    always @(posedge clk)begin
        if(!rstn)begin held=0; end
        else begin
            if(held && (!valid || {voice,data}!==prior)) $fatal(1,"key event changed while blocked");
            held=valid&&!ready; prior={voice,data};
            if(held) stalls=stalls+1;
            if(initialized && valid && ready)begin
                case(data[170:169])
                    2'd1:begin
                        if(accepted_gates[voice]) $fatal(1,"duplicate NoteOn key%0d",voice);
                        accepted_gates[voice]=1; on_count=on_count+1;
                    end
                    2'd2:begin
                        if(!accepted_gates[voice]) $fatal(1,"duplicate NoteOff key%0d",voice);
                        accepted_gates[voice]=0; off_count=off_count+1;
                    end
                    default:$fatal(1,"unexpected key event");
                endcase
            end
        end
    end
    initial begin
        repeat(4) @(negedge clk); rstn=1;
        wait(initialized);
        @(negedge clk); pressed=32'h8;
        repeat(2048) @(negedge clk);
        if(events!=1 || on_count!=1 || off_count!=0) $fatal(1,"held key retriggered events=%0d",events);
        pressed=0;
        repeat(1024) @(negedge clk);
        if(events!=2 || off_count!=1) $fatal(1,"release missing");
        pressed=32'h8;
        repeat(1024) @(negedge clk);
        if(events!=3 || on_count!=2) $fatal(1,"legitimate repress suppressed");
        pressed=32'ha8;
        repeat(1024) @(negedge clk);
        if(events!=5 || on_count!=4) $fatal(1,"chord edges missing");
        pressed=0;
        repeat(1024) @(negedge clk);
        if(events!=8 || on_count!=4 || off_count!=4 || delivered || accepted_gates || stalls==0)
            $fatal(1,"final edge accounting failed");
        completed=1;
        $display("PASS keyboard_hold NoteOn=%0d NoteOff=%0d events=%0d stalls=%0d",on_count,off_count,events,stalls);
        $finish;
    end
    initial begin #1000000; $fatal(1,"keyboard hold timeout"); end
endmodule
