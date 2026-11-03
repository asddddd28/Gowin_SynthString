`timescale 1ns / 1ps
// Board hierarchy test / 板级引脚完整链路. Contract: spec/tb_synth_system_spec.md.
module tb_touch_system(output o_done);
    reg clk=0,rstn=0,dout=0,rx=1,completed=0;
    assign o_done=completed;
    always #10 clk=~clk;
    wire [2:0] mux;
    wire en,cs,sclk,din,tx,bclk,ws,sdata,pa;
    reg [11:0] raw[0:31],rest[0:31],bottom[0:31];
    reg [1:0] selected=0;
    reg [15:0] adc_response=0,adc_command=0;
    integer edges=0,col=0,conversions=0,k,clock_count=0,last_tick=0,max_compute=0,max_stress_compute=0;
    reg stress_active=0; // 单独核对全native压力帧，不覆盖此前DX负载最大值
    integer pcm_count=0,serial_count=0,serial_slot=0,serial_nonzero=0;
    reg [15:0] serial_left=0,serial_right=0,expected_left=0,expected_right=0;
    reg previous_ws=1;
    integer reply_count=0,reply_byte=0,reply_bit;
    reg [7:0] received;
    reg [255:0] reply_image;
    reg [255:0] replies[0:255];
    reg [7:0] packets[0:4523];
    reg [7:0] stress_packets[0:5771];
    reg [15:0] reply_crc;
    integer crc_index,old_count,old_nonzero,old_commands,stress_command,stress_byte,stress_timeout;
    reg [31:0] first_identity;
    reg [15:0] captured[0:511];
    integer sample_index,chunk,lane;
    always @(posedge clk) if(Dut.flag_rstn && Dut.Monitor_Inst.flag_capture_busy && Dut.flag_monitor_sample)
        captured[Dut.Monitor_Inst.reg_write_index]=rounded(Dut.wire_pcm[31:0]);
    SynthSystemTop #(.C_TOUCH_ENABLE(1),.C_SETTLE_CYCLES(30),.C_UART_CYCLES(16),.C_POWERUP_CYCLES(16),.C_AMP_CYCLES(64)) Dut(
        .i_clk(clk),.i_rstn(rstn),.i_adc_dout(dout),.i_uart_rx(rx),.i_touch_next(1'b0),
        .o_mux_sel(mux),.o_mux_en(en),.o_adc_cs_n(cs),.o_adc_sclk(sclk),.o_adc_din(din),.o_uart_tx(tx),
        .HP_BCK(bclk),.HP_WS(ws),.HP_DIN(sdata),.PA_EN(pa)
    );
    always @(negedge cs) begin
        case(mux)4:col=0;5:col=1;6:col=2;7:col=3;3:col=4;2:col=5;1:col=6;default:col=7;endcase
        edges=0;adc_command=0;adc_response={4'd0,raw[selected*8+col]};dout=0;
    end
    always @(posedge sclk) if(!cs) begin adc_command={adc_command[14:0],din};edges=edges+1;end
    always @(negedge sclk) if(!cs && edges<16) begin adc_response={adc_response[14:0],1'b0};dout<=#30 adc_response[15];end
    always @(posedge cs) if(rstn && edges!=0) begin
        if(edges!=16) $fatal(1,"ADC length");
        selected=adc_command[12:11];conversions=conversions+1;
    end
    function [15:0] rounded;
        input signed [31:0] sample;
        integer magnitude,value;
        begin
            magnitude=sample<0 ? -sample : sample;
            value=(magnitude+1024)/2048;
            if(sample<0)value=-value;
            if(value>32767)value=32767;
            if(value< -32768)value=-32768;
            rounded=value;
        end
    endfunction
    function [15:0] crc_byte;
        input [15:0] initial_crc;
        input [7:0] byte_value;
        integer bit_index;
        reg [15:0] crc;
        begin
            crc=initial_crc^{byte_value,8'd0};
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)crc=crc[15] ? (crc<<1)^16'h1021 : crc<<1;
            crc_byte=crc;
        end
    endfunction
    always @(posedge clk) if(Dut.flag_rstn) begin
        clock_count=clock_count+1;
        if(Dut.flag_boot_fault || Dut.flag_key_fault || Dut.flag_master_fault || Dut.wire_underruns!=0)
            $fatal(1,"system fault boot=%b key=%b master=%b underrun=%d boot_cmd=%d master_state=%d result=%h",Dut.flag_boot_fault,Dut.flag_key_fault,Dut.flag_master_fault,Dut.wire_underruns,Dut.Boot_Inst.reg_command,Dut.Master_Inst.reg_state,Dut.master_response);
        if(Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.flag_tick) last_tick=clock_count;
        if(Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.flag_pcm) begin
            if(clock_count-last_tick>max_compute)max_compute=clock_count-last_tick;
            if(stress_active && clock_count-last_tick>max_stress_compute)max_stress_compute=clock_count-last_tick;
            if(clock_count-last_tick>=1024)$fatal(1,"DSP deadline");
        end
        if(Dut.flag_pcm_ready) begin
            expected_left=Dut.flag_pcm_valid ? rounded(Dut.wire_pcm[31:0]) : 0;
            expected_right=Dut.flag_pcm_valid ? rounded(Dut.wire_pcm[63:32]) : 0;
            if(Dut.flag_pcm_valid)pcm_count=pcm_count+1;
        end
    end
    always @(posedge bclk) if(Dut.flag_rstn) begin
        if(ws!=previous_ws)serial_slot=0;
        if(ws)serial_left={serial_left[14:0],sdata};else serial_right={serial_right[14:0],sdata};
        if(!ws && serial_slot==15) begin
            if(serial_left!==expected_left || serial_right!==expected_right)
                $fatal(1,"PT8211 frame %0d L/R=%h/%h expected=%h/%h",serial_count,serial_left,serial_right,expected_left,expected_right);
            if(serial_left!=0 || serial_right!=0)serial_nonzero=serial_nonzero+1;
            serial_count=serial_count+1;
        end
        previous_ws=ws;serial_slot=serial_slot+1;
    end
    initial forever begin
        @(negedge tx);#160;
        if(tx!==0)$fatal(1,"UART response start");
        for(reply_bit=0;reply_bit<8;reply_bit=reply_bit+1)begin #320;received[reply_bit]=tx;end
        #320;if(tx!==1)$fatal(1,"UART response stop");
        reply_image[reply_byte*8+:8]=received;
        if(reply_byte==31)begin
            reply_crc=16'hffff;
            for(crc_index=0;crc_index<30;crc_index=crc_index+1)reply_crc=crc_byte(reply_crc,reply_image[crc_index*8+:8]);
            if(reply_image[23:0]!==24'h055253 || reply_crc!==reply_image[255:240])$fatal(1,"UART response CRC/header");
            replies[reply_count]=reply_image;reply_count=reply_count+1;reply_byte=0;
        end else reply_byte=reply_byte+1;
    end
    task frames;
        input integer count;
        integer target;
        begin target=pcm_count+count;while(pcm_count<target)@(negedge clk);end
    endtask
    task send_byte;
        input [7:0] value;
        integer bit_index;
        begin
            @(negedge clk);rx=0;repeat(16)@(negedge clk);
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin rx=value[bit_index];repeat(16)@(negedge clk);end
            rx=1;repeat(20)@(negedge clk);
        end
    endtask
    task send_packet;
        input integer number;
        integer byte_index;
        begin for(byte_index=0;byte_index<52;byte_index=byte_index+1)send_byte(packets[number*52+byte_index]);end
    endtask
    task transact;
        input integer number;
        input [7:0] status;
        integer target,watchdog;
        begin
            target=reply_count+1;send_packet(number);watchdog=0;
            while(reply_count<target && watchdog<20000)begin @(negedge clk);watchdog=watchdog+1;end
            if(reply_count!=target)$fatal(1,"UART timeout packet=%0d host_state=%d master=%d",number,Dut.Host_Inst.reg_state,Dut.Master_Inst.reg_state);
            if(replies[target-1][199:192]!==status)$fatal(1,"UART status packet=%0d got=%0d expected=%0d",number,replies[target-1][199:192],status);
            if(replies[target-1][63:32]!=={packets[number*52+7],packets[number*52+6],packets[number*52+5],packets[number*52+4]})$fatal(1,"UART identity");
            if(status==0 && packets[number*52+3]==0) begin
                if(packets[number*52+8]>=8'hc0 && packets[number*52+8]<=8'hc4) begin
                    if(replies[target-1][135:128]!=1)$fatal(1,"disabled FX did not return unsupported");
                end else if(replies[target-1][135:128]!=0)$fatal(1,"engine command status packet=%0d %h",number,replies[target-1]);
            end
        end
    endtask

    initial begin
        $readmemh("raw_rest.hex",rest);$readmemh("raw_bottom.hex",bottom);$readmemh("sim/touch_packets.hex",packets);
        for(k=0;k<32;k=k+1)raw[k]=rest[k];
        repeat(5)@(negedge clk);rstn=1;
        while(!Dut.flag_boot_done)@(negedge clk);
        frames(80);
        transact(0,0);if(replies[0][95:64]!=32'h53544d31)$fatal(1,"monitor capabilities");
        transact(1,0);transact(2,0);if(!replies[2][216])$fatal(1,"mapping replay");
        transact(3,0);if(replies[3][111:64]!=48'hdcf2015f25dc)$fatal(1,"map readback");
        raw[0]=bottom[0];frames(120);
        if(Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.Voice_Inst.mem_patch[0]!=2)$fatal(1,"physical key did not use mapped patch");
        first_identity=Dut.Keys_Inst.mem_note_id[0];
        transact(4,0);transact(5,0);
        if(!replies[5][216]||Dut.Monitor_Inst.cnt_generation!=1)$fatal(1,"capture replay executed twice");
        frames(520);transact(6,0);
        if(replies[6][159:128]==0||replies[6][95:64]==0||replies[6][95:64]>50000)$fatal(1,"tagged latency absent or outside 1ms");
        old_nonzero=0;
        for(chunk=0;chunk<64;chunk=chunk+1)begin
            transact(7+chunk,0);
            for(lane=0;lane<8;lane=lane+1)begin
                if(replies[reply_count-1][64+lane*16+:16]!==captured[chunk*8+lane])$fatal(1,"PCM capture mismatch %0d/%0d",chunk,lane);
                if(captured[chunk*8+lane]!=0)old_nonzero=old_nonzero+1;
            end
        end
        if(old_nonzero==0)$fatal(1,"no actual audio captured");
        transact(71,5);transact(72,5);transact(73,0);
        transact(74,0);transact(75,0);
        if(replies[75][111:64]!=48'h650d020e209b)$fatal(1,"updated map");
        if(Dut.Keys_Inst.mem_note_id[0]!=first_identity||Dut.wire_key_events!=1)$fatal(1,"held key remap retriggered");
        raw[0]=rest[0];frames(200);
        if(Dut.wire_key_events!=2||Dut.wire_delivered!=0)$fatal(1,"release after mapping");
        raw[0]=bottom[0];frames(150);
        old_commands=0;
        for(k=0;k<8;k=k+1)begin
            if(Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.Voice_Inst.mem_identity[k]==Dut.Keys_Inst.mem_note_id[0])begin
                if(Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.Voice_Inst.mem_patch[k]!=1)$fatal(1,"next press ignored mapping");
                old_commands=old_commands+1;
            end
        end
        if(old_commands!=1)$fatal(1,"new key voice identity missing");
        if(Dut.Keys_Inst.mem_note_id[0]==first_identity)$fatal(1,"new press retained identity");
        transact(76,0);
        if(Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.Filter_Inst.reg_revision!=32'habc123)$fatal(1,"filter not committed through AXI");
        raw[0]=rest[0];frames(200);raw[0]=bottom[0];frames(150);
        if(Dut.wire_key_events!=5)$fatal(1,"filter commands damaged physical note sequence");
        transact(77,0);transact(78,0);if(!replies[reply_count-1][216])$fatal(1,"filter status replay");
        if(replies[reply_count-1][127:96]!=32'habc123)$fatal(1,"filter revision readback");
        transact(79,0);frames(300);transact(80,0);
        if(Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.Filter_Inst.reg_mix!=0)$fatal(1,"filter bypass did not settle");

        transact(81,0);if(replies[81][95:64]!=32'h544f5531)$fatal(1,"touch capability through UART");
        transact(82,0);frames(50);
        if(Dut.o_touch_mode!=3 || Dut.wire_delivered!=0)$fatal(1,"guitar did not stop held physical key");
        transact(83,0);if(!replies[83][216])$fatal(1,"touch exact replay missing");
        transact(84,0);if(replies[84][65:64]!=3)$fatal(1,"touch status mode");
        transact(85,5);if(Dut.o_touch_mode!=3)$fatal(1,"invalid touch config mutated mode");
        force Dut.TouchDomain.wire_error=0;
        force Dut.TouchDomain.wire_contact=1;
        force Dut.TouchDomain.wire_x=512;
        force Dut.TouchDomain.wire_y=0;
        force Dut.TouchDomain.wire_update=0;
        raw[3]=bottom[3];frames(50);if(Dut.wire_delivered!=0)$fatal(1,"guitar keyboard sounded directly");
        @(negedge clk);force Dut.TouchDomain.wire_update=1;@(negedge clk);force Dut.TouchDomain.wire_update=0;repeat(10)@(negedge clk);
        if(Dut.wire_delivered!=0)$fatal(1,"touchdown sounded");
        force Dut.TouchDomain.wire_y=1023;force Dut.TouchDomain.wire_update=1;@(negedge clk);force Dut.TouchDomain.wire_update=0;frames(20);
        if(Dut.wire_delivered!=8)$fatal(1,"rightmost strum did not reach voice %h",Dut.wire_delivered);
        raw[3]=rest[3];raw[0]=rest[0];frames(80);if(Dut.wire_delivered!=0)$fatal(1,"guitar release stuck");
        transact(86,0);frames(10);if(Dut.o_touch_mode!=0)$fatal(1,"normal mode restore");
        $display("PASS touch system UART capability/config/status/replay, ADC physical key suppressed in guitar, rightmost strum through voice and PT8211, note release");
        completed=1;
        $display("PASS studio_system filter_AXI_LFO_bypass=PASS independent_note_sequence=PASS local_CRC_replay=PASS mapped_physical_key=PASS held_remap_release=PASS PCM512_bit_exact=PASS latency_cycles=%0d max_compute=%0d",Dut.Monitor_Inst.reg_latency,max_compute);
        $finish;
    end
    initial begin #300000000;$fatal(1,"studio watchdog");end
endmodule
