`timescale 1ns / 1ps
module tb_display_video;
    reg clk=0,sysclk=0,rstn=0,calibrating=0;
    always #6.818182 clk=~clk;
    always #10 sysclk=~sysclk;
    reg [2:0] page=0;
    wire [7:0] wave_address;
    wire [5:0] spectrum_address;
    wire blank,hs,vs,de;
    wire [23:0] rgb;
    reg [7:0] wave=128;
    reg [6:0] spectrum=0;
    integer file,pixels,n,frame,hs_count,vs_count;
    reg [159:0] fields={32'd12345,32'd0,32'd0,32'h00006700,32'h80010001};
    SynthDisplayVideo dut(.i_clk(clk),.i_rstn(rstn),.i_system_clk(sysclk),.i_page(page),.i_fields(fields),.i_calibrating(calibrating),.i_host_live(1'b0),
        .i_text_write(1'b0),.i_text_address(10'd0),.i_text_data(8'd0),.i_wave(wave),.i_spectrum(spectrum),.i_audio_available(1'b1),.i_publish(1'b0),
        .o_wave_address(wave_address),.o_spectrum_address(spectrum_address),.o_blank_start(blank),.o_rgb(rgb),.o_hsync(hs),.o_vsync(vs),.o_de(de));
    always @(posedge clk) begin wave<=wave_address;spectrum<=spectrum_address;end
    initial begin
        #100;rstn=1;
        for(frame=0;frame<9;frame=frame+1) begin
            wait(blank);@(negedge clk);page=frame==8 ? 0 : frame;calibrating=frame==8;
            wait(dut.cnt_x==0 && dut.cnt_y==0);repeat(6) @(negedge clk);
            case(frame)
                0:file=$fopen("overview.ppm","wb");1:file=$fopen("patches.ppm","wb");2:file=$fopen("operators.ppm","wb");
                3:file=$fopen("modulation.ppm","wb");4:file=$fopen("effects.ppm","wb");5:file=$fopen("system.ppm","wb");
                6:file=$fopen("sequences.ppm","wb");7:file=$fopen("presets.ppm","wb");8:file=$fopen("calibration.ppm","wb");
            endcase
            $fwrite(file,"P6\n1280 720\n255\n");pixels=0;hs_count=0;vs_count=0;
            for(n=0;n<1650*750;n=n+1) begin
                if(hs) hs_count=hs_count+1;
                if(vs) vs_count=vs_count+1;
                if(de) begin
                    if(^rgb===1'bx) $fatal(1,"unknown visible pixel");
                    $fwrite(file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);pixels=pixels+1;
                end
                @(negedge clk);
            end
            $fclose(file);if(pixels!=921600) $fatal(1,"active pixel count %0d",pixels);
            if(hs_count!=30000 || vs_count!=8250) $fatal(1,"sync pulse width");
        end
        $display("PASS video: nine complete frames including libraries and calibration, 921600 known RGB pixels each");$finish;
    end
    initial begin #350000000;$fatal(1,"timeout");end
endmodule
