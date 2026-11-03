`timescale 1ns / 1ps
module tb_display_control;
    reg clk=0,pclk=0,rstn=0;
    always #10 clk=~clk;
    always #6.818182 pclk=~pclk;
    reg request=0,blank=0;
    reg [7:0] opcode=0,argument=0;
    reg [63:0] words=0;
    wire response_valid,text_write;
    wire [135:0] response;
    wire [9:0] text_address;
    wire [7:0] text_data;
    wire [2:0] page,pixel_page;
    wire [159:0] fields;
    integer writes=0;
    reg [4:0] joystick=21,encoder_a=0,encoder_b=0;
    integer channel,longs=0;
    wire touch_next;
    always @(posedge clk)if(touch_next)longs=longs+1;
    SynthDisplayControl #(.C_LONG_CYCLES(300000)) dut(.i_clk(clk),.i_rstn(rstn),.i_joystick(joystick),.i_encoder_a(encoder_a),.i_encoder_b(encoder_b),.o_touch_next(touch_next),
        .i_request(request),.i_opcode(opcode),.i_argument(argument),.i_words(words),.o_response_valid(response_valid),.o_response(response),
        .o_text_write(text_write),.o_text_address(text_address),.o_text_data(text_data),.o_page(page),.o_focus(),.o_confirm());
    SynthDisplaySnapshot snap(.i_clk(clk),.i_rstn(rstn),.i_pixel_clk(pclk),.i_pixel_rstn(rstn),.i_blank_start(blank),
        .i_keys(32'h80000001),.i_latency(32'd335000),.i_underruns(32'd0),.i_errors(32'd7),.i_frames(32'd12345),.i_page(page),.o_fields(fields),.o_page(pixel_page));
    always @(posedge clk) if(text_write) begin
        if(text_address!==16+writes || text_data!==8'h41+writes) $fatal(1,"text write order/data");
        writes=writes+1;
    end
    task command;
        input [7:0] op,arg;input [63:0] data;
        begin @(negedge clk);opcode=op;argument=arg;words=data;request=1;@(negedge clk);request=0;wait(response_valid);@(negedge clk);end
    endtask
    task move_joystick;
        input [4:0] value;
        begin joystick=value;repeat(260030)@(negedge clk);end
    endtask
    initial begin
        #100;rstn=1;
        command(8'h10,0,0);if(response[31:0]!==32'h48444d31) $fatal(1,"capability");
        command(8'h11,6,0);if(page!==6) $fatal(1,"sequence library page set");
        command(8'h11,7,0);if(page!==7) $fatal(1,"SD presets page set");
        command(8'h11,8,0);if(response[135:128]!==5 || page!==7) $fatal(1,"invalid page changed state");
        command(8'h12,2,64'h4847464544434241);if(writes!=8) $fatal(1,"early ACK");
        @(negedge pclk);blank=1;@(negedge pclk);blank=0;
        repeat(200) @(negedge pclk);
        if(fields[63:32]!==32'h00006700 || fields[31:0]!==32'h80000001 || pixel_page!==7) $fatal(1,"coherent snapshot or decimal conversion: %h",fields);
        repeat(3000)@(negedge clk);
        encoder_b=1;repeat(3000)@(negedge clk);encoder_a=1;repeat(3000)@(negedge clk);
        encoder_b=0;repeat(3000)@(negedge clk);encoder_a=0;repeat(3000)@(negedge clk);
        if(dut.reg_position[0]!==4) $fatal(1,"first encoder detent lost");
        for(channel=1;channel<5;channel=channel+1) begin
            encoder_b[channel]=1;repeat(3000)@(negedge clk);encoder_a[channel]=1;repeat(3000)@(negedge clk);
            encoder_b[channel]=0;repeat(3000)@(negedge clk);encoder_a[channel]=0;repeat(3000)@(negedge clk);
        end
        command(8'h13,0,0);
        for(channel=0;channel<5;channel=channel+1) if(response[channel*16 +:16]!==4) $fatal(1,"encoder channel/response mismatch %d",channel);
        move_joystick(21);if(page!==7) $fatal(1,"centre changed page");
        move_joystick(23);if(page!==0) $fatal(1,"right did not advance/wrap");
        move_joystick(23);if(page!==0) $fatal(1,"held right repeated");
        move_joystick(21);if(page!==0) $fatal(1,"right release changed page");
        move_joystick(20);if(page!==7) $fatal(1,"left did not reverse/wrap");
        move_joystick(21);if(page!==7) $fatal(1,"left release changed page");
        move_joystick(22);move_joystick(20);if(page!==7) $fatal(1,"invalid axis rearmed direction");
        move_joystick(21);move_joystick(29);if(dut.reg_focus_o!==255) $fatal(1,"up focus");
        move_joystick(21);move_joystick(17);if(dut.reg_focus_o!==0) $fatal(1,"down focus");
        move_joystick(21);move_joystick(5);
        if(dut.reg_confirm_o!==0 || longs!=0) $fatal(1,"short press must await release");
        move_joystick(21);if(dut.reg_confirm_o!==1) $fatal(1,"short release missing confirm");
        move_joystick(5);move_joystick(5);move_joystick(5);
        if(dut.reg_confirm_o!==1 || longs!=1) $fatal(1,"long press missing/repeated or confirmed");
        move_joystick(21);if(dut.reg_confirm_o!==1 || longs!=1) $fatal(1,"long release emitted confirm");
        move_joystick(5);move_joystick(21);if(dut.reg_confirm_o!==2) $fatal(1,"short after long did not rearm");
        rstn=0;joystick=23;repeat(10)@(negedge clk);rstn=1;
        move_joystick(23);if(page!==0) $fatal(1,"power-up held right emitted event");
        move_joystick(21);move_joystick(23);if(page!==1) $fatal(1,"did not arm after first centre");
        $display("PASS control: five encoders, comparator left/centre/right, release/hold/invalid/startup, focus, confirm, cap, text ACK, CDC, 6700 us");$finish;
    end
    initial begin #200000000;$fatal(1,"timeout");end
endmodule
