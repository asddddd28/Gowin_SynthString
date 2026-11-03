`timescale 1ns / 1ps
// Board hierarchy test / 板级引脚完整链路. Contract: spec/tb_synth_system_spec.md.
module tb_synth_system(output o_done);
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
    reg [7:0] packets[0:1247];
    reg [7:0] stress_packets[0:5771];
    reg [15:0] reply_crc;
    integer crc_index,old_count,old_nonzero,old_commands,stress_command,stress_byte,stress_timeout;
    reg [31:0] first_identity;
    SynthSystemTop #(.C_SETTLE_CYCLES(30),.C_UART_CYCLES(16),.C_POWERUP_CYCLES(16),.C_AMP_CYCLES(64)) Dut(
        .i_clk(clk),.i_rstn(rstn),.i_adc_dout(dout),.i_uart_rx(rx),
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
        $readmemh("raw_rest.hex",rest);$readmemh("raw_bottom.hex",bottom);$readmemh("sim/uart_packets.hex",packets);$readmemh("sim/uart_stress.hex",stress_packets);
        for(k=0;k<32;k=k+1)raw[k]=rest[k];
        repeat(5)@(negedge clk);rstn=1;
        while(!Dut.flag_boot_done)@(negedge clk);
        frames(80);
        if(Dut.Endpoint_Inst.Endpoint_Inst.C_DELAY_ADDR_BITS!=13)$fatal(1,"board delay capacity");
        if(pa || Dut.wire_completed!=57 || Dut.wire_pressed!=0 || serial_nonzero!=0)$fatal(1,"boot or idle");
        transact(0,0);
        if(replies[0][71:64]!=8'h11)$fatal(1,"board status initialized/amplifier flags %h",replies[0]);
        transact(1,0);if(replies[1][95:64]!=32'h00010005)$fatal(1,"AXI ABI read");
        raw[0]=bottom[0];raw[12]=bottom[12];raw[31]=bottom[31];
        frames(220);
        if(Dut.wire_pressed!==32'h80001001 || Dut.wire_delivered!==32'h80001001 || Dut.wire_key_events!=3 || serial_nonzero<100)$fatal(1,"three-key audio path");
        first_identity=Dut.Keys_Inst.mem_note_id[0];
        frames(100);if(Dut.wire_key_events!=3)$fatal(1,"held key retriggered");
        transact(2,0);old_commands=Dut.wire_completed;
        transact(3,0);if(!replies[reply_count-1][216] || Dut.wire_completed!=old_commands)$fatal(1,"duplicate executed");
        transact(4,2);if(Dut.wire_completed!=old_commands)$fatal(1,"conflict executed");
        transact(5,0);
        transact(6,0);frames(20);transact(7,0);
        if(!replies[reply_count-1][216] || replies[reply_count-1][191:64]!==replies[reply_count-2][191:64])$fatal(1,"query replay not cached");
        transact(8,5);
        old_count=reply_count;old_commands=Dut.wire_completed;
        send_packet(9);repeat(6000)@(negedge clk);
        if(reply_count!=old_count || Dut.wire_completed!=old_commands || Dut.wire_bad_packets==0)$fatal(1,"bad CRC side effect");
        transact(10,0);transact(11,0);
        for(k=0;k<32;k=k+1)raw[k]=bottom[k];
        transact(12,0);transact(13,0);transact(14,0);
        frames(400);
        if(Dut.wire_delivered!==32'hffffffff || Dut.wire_key_events!=32 || Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.o_active!==8'hff)$fatal(1,"32 keys / 8 voice allocation");
        transact(15,0);if(replies[reply_count-1][95:64]!=0)$fatal(1,"FX telemetry");
        transact(16,3);transact(17,0);
        for(k=0;k<10;k=k+1)send_byte(packets[18*52+k]);
        repeat(10000)@(negedge clk);transact(18,0);
        if(Dut.wire_bad_packets<2)$fatal(1,"partial packet timeout missing");
        transact(19,5);transact(20,5);
        for(k=0;k<32;k=k+1)raw[k]=rest[k];
        frames(220);
        if(Dut.wire_delivered!=0 || Dut.wire_key_events!=64)$fatal(1,"release events");
        raw[0]=bottom[0];frames(120);
        if(Dut.Keys_Inst.mem_note_id[0]==first_identity || Dut.wire_key_events!=65)$fatal(1,"repress identity");
        raw[0]=rest[0];frames(120);
        if(Dut.wire_key_events!=66)$fatal(1,"repress release");
        transact(21,0);transact(22,0);frames(20);
        old_nonzero=serial_nonzero;frames(30);
        if(serial_nonzero!=old_nonzero)$fatal(1,"panic and FX clear left sound");
        transact(23,0);
        // Upload and play the same 48-operator worst-case program through real UART.
        for(stress_command=0;stress_command<111;stress_command=stress_command+1)begin
            old_count=reply_count;
            for(stress_byte=0;stress_byte<52;stress_byte=stress_byte+1)send_byte(stress_packets[stress_command*52+stress_byte]);
            stress_timeout=0;
            while(reply_count==old_count && stress_timeout<20000)begin @(negedge clk);stress_timeout=stress_timeout+1;end
            if(reply_count!=old_count+1 || replies[old_count][199:192]!=0 || replies[old_count][63:32]!=19+stress_command)
                $fatal(1,"stress UART command %0d reply=%h",stress_command,replies[old_count]);
            if(stress_command<107 && stress_packets[stress_command*52+8]!=8'hc3 && replies[old_count][135:128]!=0)$fatal(1,"stress engine status %d",stress_command);
            if(stress_command==108 && replies[old_count][95:64]!=0)$fatal(1,"FX capacity address bits");
            if(stress_command==109 && replies[old_count][95:64]!=0)$fatal(1,"FX capacity maximum");
            if((stress_command==106 || stress_command==110) && replies[old_count][135:128]!=1)$fatal(1,"oversized board delay accepted");
            if(stress_command==104)begin
                stress_active=1;
                frames(256);
                stress_active=0;
                if(max_stress_compute!=835)$fatal(1,"native dry worst-case frame not observed %0d",max_stress_compute); // Voice834拍后下一沿观察到PCM脉冲；保留1024拍硬期限。
            end
        end
        frames(10);
        if(Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.o_pcm_dropped!=0 || Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.o_fx_dropped!=0 || Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.o_overruns!=0)$fatal(1,"audio drop/overrun");
        completed=1;
        $display("PASS synth_system boot=57 FX=disabled FM1_presets=4 keys=66 UART_replies=%0d CRC_replay=PASS PCM=%0d PT8211=%0d nonzero=%0d ADC=%0d max_compute=%0d native_stress=%0d",reply_count,pcm_count,serial_count,serial_nonzero,conversions,max_compute,max_stress_compute);
        $finish;
    end
    initial begin #300000000;$fatal(1,"system watchdog state=%0d boot=%0d",Dut.Master_Inst.reg_state,Dut.Boot_Inst.reg_command);end
endmodule
