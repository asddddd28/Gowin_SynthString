"""Full ADC -> accepted keyboard event -> sequencer -> AXI -> PT8211 regression."""
from pathlib import Path
import shutil
from run_tests import ROOT,OUT,run


def packet(sequence,kind,opcode,argument=0,words=()):
    data=bytearray(b'SY\x05')+bytes([kind])+sequence.to_bytes(4,'little')+bytes([opcode,argument])
    data+=b''.join(w.to_bytes(4,'little') for w in words)
    data+=bytes(50-len(data))
    crc=65535
    for byte in data:
        crc^=byte<<8
        for _ in range(8):crc=((crc<<1)^(0x1021 if crc&32768 else 0))&65535
    return data+crc.to_bytes(2,'little')


def main():
    source=(ROOT/'sim/tb_studio_system.v').read_text(encoding='utf-8')
    source=source[:source.index('    initial begin\n        $readmemh')]
    source=source.replace('tb_studio_system','tb_sequencer_system')
    source=source.replace('SynthSystemTop #(', 'SynthSystemTop #(.C_SEQUENCE_ENABLE(1),')
    source=source.replace('.i_clk(clk),.i_rstn(rstn),.i_adc_dout(dout)', '.i_buttons(6\'d0),.i_clk(clk),.i_rstn(rstn),.i_adc_dout(dout)')
    source=source.replace('rounded(Dut.wire_pcm[31:0]) : 0','mixed(Dut.wire_pcm[31:0],Dut.wire_click) : 0')
    source=source.replace('rounded(Dut.wire_pcm[63:32]) : 0','mixed(Dut.wire_pcm[63:32],Dut.wire_click) : 0')
    source+='''
    defparam Dut.SequenceDomain.Recorder_Inst.C_US_CYCLES=1;
    defparam Dut.SequenceDomain.Recorder_Inst.C_PPQ=128;
    function [15:0] mixed;
        input signed [31:0] value;
        input signed [15:0] click_value;
        integer sum;
        begin
            sum=$signed(rounded(value))+$signed(click_value);
            mixed=sum>32767 ? 16'h7fff : sum< -32768 ? 16'h8000 : sum;
        end
    endfunction
    initial begin
        $readmemh("raw_rest.hex",rest);$readmemh("raw_bottom.hex",bottom);$readmemh("packets.hex",packets);
        for(k=0;k<32;k=k+1)raw[k]=rest[k];
        repeat(5)@(negedge clk);rstn=1;
        wait(Dut.flag_boot_done);frames(80);
        transact(0,0);
        if(replies[0][95:64]!=32'h53455131)$fatal(1,"sequencer not discovered through real UART");
        transact(1,0);transact(2,0);
        if(!Dut.SequenceDomain.Recorder_Inst.flag_recording || !replies[2][216])$fatal(1,"duplicate start toggled recording twice");
        raw[0]=bottom[0];frames(120);raw[0]=rest[0];frames(160);
        transact(3,0);wait(!Dut.SequenceDomain.Recorder_Inst.flag_finalizing);
        if(Dut.SequenceDomain.Recorder_Inst.cnt_saved!=2 || !Dut.SequenceDomain.Recorder_Inst.flag_playing)$fatal(1,"ADC recording failed");
        transact(4,11);
        if(Dut.flag_master_fault)$fatal(1,"protected patch write poisoned master");
        transact(5,0);
        if(replies[5][95:64]==0)$fatal(1,"status missing");
        frames(1000);
        old_nonzero=serial_nonzero;
        frames(1000);
        if(serial_nonzero<=old_nonzero)$fatal(1,"replay did not reach DAC");
        if(Dut.SequenceDomain.Click_Inst.o_sample!=0)$fatal(1,"metronome still active after recording");
        // A live key coexists with playback, and clear only stops playback IDs.
        raw[1]=bottom[1];frames(100);first_identity=Dut.Keys_Inst.mem_note_id[1];
        transact(6,0);frames(100);old_commands=0;
        for(k=0;k<8;k=k+1)if(Dut.Endpoint_Inst.Endpoint_Inst.Runtime_Inst.Voice_Inst.mem_identity[k]==first_identity)old_commands=old_commands+1;
        if(old_commands!=1 || !Dut.wire_delivered[1])$fatal(1,"clear removed held live voice");
        raw[1]=rest[1];frames(120);
        if(Dut.SequenceDomain.Recorder_Inst.o_patch_lock!=0 || Dut.wire_underruns!=0)$fatal(1,"clear/underrun failure");
        // Import and export over the real UART, then render the restored loop.
        transact(7,0);if(replies[7][95:64]!=32'h41524331)$fatal(1,"archive capability");
        transact(8,0);transact(9,0);transact(10,0);transact(11,0);transact(12,0);
        if(Dut.SequenceDomain.Recorder_Inst.cnt_saved!=0)$fatal(1,"uncommitted image visible");
        transact(13,0);transact(14,0);transact(15,0);transact(16,0);transact(17,0);
        if(replies[15][83:64]!=12 || replies[15][142]!=1 || replies[16][83:64]!=60)$fatal(1,"UART archive readback");
        old_nonzero=serial_nonzero;transact(18,0);frames(1000);
        if(serial_nonzero<=old_nonzero || Dut.wire_underruns!=0)$fatal(1,"restored loop did not reach PCM");
        transact(19,0);frames(150);transact(20,0);
        $display("PASS archive_system UART_import=PASS UART_export=PASS restored_loop_PCM=PASS");
        $display("PASS sequencer_system UART_duplicate=PASS ADC_record=PASS AXI_slot_protect=PASS loop_PCM=PASS independent_clear=PASS max_compute=%0d",max_compute);
        completed=1;$finish;
    end
    initial begin #200000000;$fatal(1,"sequencer system watchdog");end
endmodule
'''
    # Keep the hand-authored fixture's signal name aligned with the actual integration.
    source=source.replace('Dut.wire_click','Dut.wire_click_sample')
    bench=ROOT/'sequencer/sim/tb_sequencer_system.v'
    bench.write_text(source,encoding='utf-8')
    packets=[packet(0,3,0x40),packet(1,3,0x42,words=[1]),packet(1,3,0x42,words=[1]),
             packet(2,3,0x42,words=[1]),packet(3,0,0xa0,words=[2]),packet(4,3,0x41),packet(5,3,0x42,words=[2])]
    on=12|(19327353<<30)|(100<<62)|(60<<69)|(1<<78)|(1<<79)
    extra=[(0x43,[]),(0x45,[2]),(0x46,[on&0xffffffff,(on>>32)&0xffffffff]),
           (0x47,[on>>64,0]),(0x46,[60,0]),(0x47,[0,1]),
           (0x48,[2|(137<<16),1]),(0x45,[1]),(0x44,[0]),(0x44,[1]),(0x45,[0]),
           (0x42,[3]),(0x42,[3]),(0x42,[2])]
    packets.extend(packet(index+6,3,op,words=words) for index,(op,words) in enumerate(extra))
    work=OUT/'system';work.mkdir(exist_ok=True)
    (work/'packets.hex').write_text(''.join(f'{b:02x}\n' for p in packets for b in p))
    shutil.copytree(ROOT/'rom',work/'rom',dirs_exist_ok=True)
    for name in ('raw_rest.hex','raw_bottom.hex','key_thresholds.hex'):shutil.copyfile(ROOT/name,work/name)
    sources=[Path(line) for line in (ROOT/'sources.f').read_text().splitlines() if line.strip()]
    run('tb_sequencer_system',sources+[bench],'system')


if __name__=='__main__':main()
