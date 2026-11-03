`timescale 1ns/1ps
// Compare public monitor words and every DAC/control output to frozen RTL.
module tb_pcm_rounding;
    reg clk=0,rstn=0,valid=0;
    reg [63:0] data=0;
    reg [15:0] click=0,expected_dry=0,expected_mixed=0;
    wire [1:0] ready,old_ready,bclk,old_bclk,ws,old_ws,serial,old_serial,sample_valid,old_sample_valid;
    wire [31:0] sample,old_sample;
    wire [63:0] frames,old_frames,underruns,old_underruns;
    integer fd,code,index=0;
    genvar mode;
    always #10 clk=~clk;
    generate for(mode=0;mode<2;mode=mode+1)begin:g_mode
        SynthPcmOutput #(.C_METRONOME_ENABLE(mode)) Dut(
            .i_clk(clk),.i_rstn(rstn),.i_valid(valid),.i_data(data),.i_click(click),
            .o_ready(ready[mode]),.o_bclk(bclk[mode]),.o_ws(ws[mode]),.o_data(serial[mode]),
            .o_frames(frames[mode*32+:32]),.o_underruns(underruns[mode*32+:32]),
            .o_sample_valid(sample_valid[mode]),.o_sample(sample[mode*16+:16]));
        SynthPcmOutputReference #(.C_METRONOME_ENABLE(mode)) Ref(
            .i_clk(clk),.i_rstn(rstn),.i_valid(valid),.i_data(data),.i_click(click),
            .o_ready(old_ready[mode]),.o_bclk(old_bclk[mode]),.o_ws(old_ws[mode]),.o_data(old_serial[mode]),
            .o_frames(old_frames[mode*32+:32]),.o_underruns(old_underruns[mode*32+:32]),
            .o_sample_valid(old_sample_valid[mode]),.o_sample(old_sample[mode*16+:16]));
    end endgenerate
    initial begin
        repeat(3)@(negedge clk);rstn=1;
        fd=$fopen("rounding.txt","r");if(!fd)$fatal(1,"missing oracle");
        while(!$feof(fd))begin
            code=$fscanf(fd,"%h %h %h %h %h\n",data[31:0],data[63:32],click,expected_dry,expected_mixed);
            if(code!=5)$fatal(1,"bad oracle");
            valid=(index%5)!=0;
            @(negedge clk);
            if(sample!=={expected_mixed,expected_dry})$fatal(1,"oracle mismatch case%0d",index);
            if({ready,bclk,ws,serial,frames,underruns,sample_valid,sample}!==
               {old_ready,old_bclk,old_ws,old_serial,old_frames,old_underruns,old_sample_valid,old_sample})
                $fatal(1,"pin or timing mismatch case%0d",index);
            index=index+1;
        end
        $fclose(fd);
        $display("PASS pcm_rounding cases=%0d dry/mixed/DAC/handshake/frame_timing=EXACT",index);
        $finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
