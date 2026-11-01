"""Build an independent byte/UART/raster testbench, including an RTL frame capture."""
from pathlib import Path
ROOT=Path(__file__).resolve().parent
def transmit(text):
    return '\n'.join(f'        send_byte(8\'h{c:02x});' for c in text.encode())
keyframes=''.join(f'K{k+1:02d}:{(k*100+300):03X}\r\n' for k in range(32))
touch='T100015A000'+'21000000'+'00'*38+'*00\r\n'
assert len(touch)==100
frames=keyframes+'E1 A3 F3 QFFFB P0005 N000A X0000\r\n'+'J1234 R15 F15 P0001\r\n'+'@010001400000000081*00\n'+touch
assert len('E1 A3 F3 QFFFB P0005 N000A X0000\r\n')==34
tb='''`timescale 1ns / 1ps
module tb_dashboard;
    reg clk=0; always #5 clk=~clk;
    reg rstn=0;
    reg [7:0] data=0;
    reg valid=0, error=0;
    wire [383:0] keys;
    wire [79:0] encoders;
    wire [4:0] joystick;
    wire [23:0] touch;
    wire [1:0] touch_ok;
    wire [31:0] pressed;
    wire configured,live,sample;
    wire [3:0] effect;
    wire [11:0] key_value;
    wire [23:0] rgb;
    wire hs,vs,de;
    reg serial_rx=1;
    wire [7:0] serial_data;
    wire serial_valid,serial_error;
    integer serial_count=0;
    integer pixels=0,hs_count=0,vs_count=0,i,j,fd;
    DashboardTelemetry #(.C_CLOCK_HZ(5000000)) parser(
        .i_clk(clk),.i_rstn(rstn),.i_byte(data),.i_valid(valid),.i_error(error),
        .o_keys(keys),.o_encoders(encoders),.o_joystick(joystick),.o_touch(touch),.o_touch_ok(touch_ok),
        .o_pressed(pressed),.o_configured(configured),.o_effect(effect),.o_live(live),.o_key_sample(sample),.o_key_value(key_value));
    DashboardVideo video(.i_clk(clk),.i_rstn(rstn),.i_keys(keys),.i_encoders(encoders),.i_joystick(joystick),
        .i_touch(touch),.i_touch_ok(touch_ok),.i_pressed(pressed),.i_configured(configured),.i_effect(effect),.i_live(live),
        .i_key_sample(sample),.i_key_value(key_value),.o_rgb(rgb),.o_hsync(hs),.o_vsync(vs),.o_de(de));
    UartRx #(.C_CLOCK_HZ(73333333),.C_BAUD(115200)) receiver(
        .i_clk(clk),.i_rstn(rstn),.i_rx(serial_rx),.o_byte(serial_data),.o_valid(serial_valid),.o_error(serial_error));
    always @(posedge clk) begin
        if(serial_valid) begin
            if(serial_data !== 8'hA5) $fatal(1,"UART sampling mismatch");
            serial_count=serial_count+1;
        end
        if(serial_error) $fatal(1,"Unexpected UART framing error");
    end
    task send_byte;
        input [7:0] b;
        begin @(negedge clk);data=b;valid=1;@(negedge clk);valid=0;end
    endtask
    initial begin
        repeat(5) @(negedge clk);rstn=1;
        // Baud ratio based on actual 50 MHz/434 TX observed at 73.333 MHz.
        serial_rx=0; repeat(637) @(negedge clk);
        for(j=0;j<8;j=j+1) begin serial_rx=(8'hA5>>j)&1;repeat(637) @(negedge clk);end
        serial_rx=1; repeat(700) @(negedge clk);
        if(serial_count!=1) $fatal(1,"No synchronized UART byte");
__FRAMES__
        repeat(3) @(negedge clk);
        if(keys[11:0]!==12'd300 || keys[383:372]!==12'd3400) $fatal(1,"Key decode mismatch");
        if(encoders[15:0]!==16'hFFFB) $fatal(1,"Signed encoder bits mismatch");
        if(joystick!==5'h15) $fatal(1,"Joystick mismatch");
        if(touch[11:0]!==12'h021 || touch_ok[0]!==1) $fatal(1,"Touch decode mismatch");
        if(pressed!==32'h81 || !configured || effect!==4) $fatal(1,"Board status mismatch");
__MALFORMED__
        repeat(3) @(negedge clk);
        if(keys[11:0]!==12'd300) $fatal(1,"Malformed frame mutated key");
        for(i=0;i<110;i=i+1) send_byte("X");
        send_byte(10);
__RECOVER__
        repeat(3) @(negedge clk);
        if(keys[23:12]!==12'h123) $fatal(1,"Overflow resynchronization failed");
        // A known changing ADC history makes the captured plot easy to inspect.
__TRACE__
        wait(video.cnt_y==749); wait(video.cnt_y==0);
        fd=$fopen("frame.ppm","wb");$fwrite(fd,"P6\\n1280 720\\n255\\n");
        for(i=0;i<1237500;i=i+1) begin
            @(negedge clk);
            if(de) begin
                if((^rgb)===1'bx) $fatal(1,"Unknown active RGB");
                pixels=pixels+1;
                $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
            end else if(rgb!==0) $fatal(1,"Nonblack blanking");
            if(hs) hs_count=hs_count+1;
            if(vs) vs_count=vs_count+1;
        end
        $fclose(fd);
        if(pixels!=921600 || hs_count!=30000 || vs_count!=8250)
            $fatal(1,"Raster mismatch: %d %d %d",pixels,hs_count,vs_count);
        wait(!live);
        $display("PASS UART, parser, malformed/overflow recovery, stale timeout, 1280x720 raster and RTL frame capture");
        $finish;
    end
    initial begin #70000000; $fatal(1,"Test timeout"); end
endmodule
'''
tb=tb.replace('__FRAMES__',transmit(frames)).replace('__MALFORMED__',transmit('K01:GGG\r\nK01:FFF\nK00:123\r\nK33:123\r\n'))
tb=tb.replace('__RECOVER__',transmit('K02:123\r\n'))
tb=tb.replace('__TRACE__',transmit(''.join(f'K01:{(700+abs(32-n)*75):03X}\r\n' for n in range(64))))
(ROOT/'sim/tb_dashboard.v').write_text(tb)
sources=[ROOT/'src/DashboardTelemetry.v',ROOT/'src/DashboardVideo.v',ROOT/'src/DashboardFont.v',ROOT.parent/'keyboard_games/src/UartRx.v',ROOT/'sim/tb_dashboard.v']
(ROOT/'sim/compile.f').write_text('\n'.join('"'+p.as_posix()+'"' for p in sources))
