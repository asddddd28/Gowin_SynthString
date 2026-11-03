`timescale 1ns / 1ps
module tb_display_audio;
    reg clk=0,pclk=0,rstn=0;
    always #10 clk=~clk;
    always #6.818182 pclk=~pclk;
    reg valid=0,blank=0;
    reg signed [15:0] sample=0;
    reg [7:0] wave_address=0;
    reg [5:0] spectrum_address=0;
    wire [7:0] wave;
    wire [6:0] spec;
    wire available,publish;
    reg [15:0] samples[0:16127];
    reg [15:0] input_counts[0:6],trigger_starts[0:6];
    reg [7:0] waves[0:1791];
    reg [6:0] reference[0:447];
    integer n,block_index;
    SynthDisplayAudio dut(.i_clk(clk),.i_rstn(rstn),.i_sample_valid(valid),.i_sample(sample),
        .i_pixel_clk(pclk),.i_pixel_rstn(rstn),.i_blank_start(blank),.i_wave_address(wave_address),.i_spectrum_address(spectrum_address),
        .o_wave(wave),.o_spectrum(spec),.o_available(available),.o_publish(publish));
    initial begin
        $readmemh("samples.hex",samples);$readmemh("spectrum.hex",reference);$readmemh("waves.hex",waves);
        $readmemh("input_counts.hex",input_counts);$readmemh("trigger_starts.hex",trigger_starts);
        #100;rstn=1;
        for(block_index=0;block_index<7;block_index=block_index+1) begin
        for(n=0;n<input_counts[block_index];n=n+1) begin
            @(negedge clk);sample=samples[block_index*2304+n];valid=1;
            if(dut.flag_sample_accept!==(n>=trigger_starts[block_index])) begin
                // Allow continuous decode to settle after assigning the input.
                #1;
                if(dut.flag_sample_accept!==(n>=trigger_starts[block_index])) $fatal(1,"trigger acceptance block %d sample %d",block_index,n);
            end
            @(negedge clk);valid=0;
            repeat(1023) @(negedge clk);
        end
        if(dut.reg_state!=7) $fatal(1,"not waiting for consumer bank");
        repeat(12) @(negedge pclk);
        blank=1;@(negedge pclk);blank=0;
        repeat(4) @(negedge pclk);
        if(!available) $fatal(1,"snapshot not published");
        for(n=0;n<256;n=n+1) begin
            spectrum_address=n;wave_address=n;
            repeat(3) @(negedge pclk);
            if(n<64 && spec!==reference[block_index*64+n]) $fatal(1,"DFT block %0d bin %0d expected %0d got %0d",block_index,n,reference[block_index*64+n],spec);
            if(wave!==waves[block_index*256+n]) $fatal(1,"wave mismatch block %0d sample %0d",block_index,n);
        end
        end
        $display("PASS audio: phase-invariant and30.5Hz triggered capture, bounded quiet/silence/DC fallback,448 DFT bins and1792 waveform pixels exact, asynchronous publication");$finish;
    end
    initial begin #250000000;$fatal(1,"timeout");end
endmodule
