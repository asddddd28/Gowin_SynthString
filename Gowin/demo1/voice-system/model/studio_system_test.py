"""End-to-end UART/keyboard/PCM monitor regression using the full board hierarchy."""
from pathlib import Path
from studio_monitor_model import key_row
ROOT=Path(__file__).resolve().parents[1]
def packet(seq,op,arg=0,words=()):
    b=bytearray(b'SY\x05\x03')+seq.to_bytes(4,'little')+bytes([op,arg])
    b+=b''.join(w.to_bytes(4,'little') for w in words);b+=bytes(50-len(b))
    crc=65535
    for v in b:
        crc^=v<<8
        for _ in range(8):crc=((crc<<1)^ (0x1021 if crc&32768 else 0))&65535
    return b+crc.to_bytes(2,'little')
row=key_row(2,60,110);new=key_row(1,67,50)
packets=[packet(0,0),packet(1,1,0,[row&0xffffffff,row>>32]),packet(1,1,0,[row&0xffffffff,row>>32]),packet(2,4),packet(3,2),packet(3,2),packet(4,3)]
packets += [packet(5+i,5,i) for i in range(64)]
packets += [packet(69,1,32,[row&0xffffffff,row>>32]),packet(70,0,0,[0,0,1]),packet(71,4,31),packet(72,1,0,[new&0xffffffff,new>>32]),packet(73,4,0)]
(ROOT/'sim/studio_packets.hex').write_text(''.join(f'{v:02x}\n' for b in packets for v in b))
source=(ROOT/'sim/tb_synth_system.v').read_text(encoding='utf-8')
prefix=source[:source.index('    initial begin\n        $readmemh')]
prefix=prefix.replace('module tb_synth_system(', 'module tb_studio_system(').replace('reg [7:0] packets[0:1247];',f'reg [7:0] packets[0:{len(packets)*52-1}];')
prefix=prefix.replace('    SynthSystemTop #(','''    reg [15:0] captured[0:511];
    integer sample_index,chunk,lane;
    always @(posedge clk) if(Dut.flag_rstn && Dut.Monitor_Inst.flag_capture_busy && Dut.flag_monitor_sample)
        captured[Dut.Monitor_Inst.reg_write_index]=rounded(Dut.wire_pcm[31:0]);
    SynthSystemTop #(''')
body='''
    initial begin
        $readmemh("raw_rest.hex",rest);$readmemh("raw_bottom.hex",bottom);$readmemh("sim/studio_packets.hex",packets);
        for(k=0;k<32;k=k+1)raw[k]=rest[k];
        repeat(5)@(negedge clk);rstn=1;
        while(!Dut.flag_boot_done)@(negedge clk);
        frames(80);
        transact(0,0);if(replies[0][95:64]!=32'h53544d31)$fatal(1,"monitor capabilities");
        transact(1,0);transact(2,0);if(!replies[2][216])$fatal(1,"mapping replay");
        transact(3,0);if(replies[3][111:64]!=48'hROW)$fatal(1,"map readback");
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
        if(replies[75][111:64]!=48'hNEW)$fatal(1,"updated map");
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
        completed=1;
        $display("PASS studio_system local_CRC_replay=PASS mapped_physical_key=PASS held_remap_release=PASS PCM512_bit_exact=PASS latency_cycles=%0d max_compute=%0d",Dut.Monitor_Inst.reg_latency,max_compute);
        $finish;
    end
    initial begin #300000000;$fatal(1,"studio watchdog");end
endmodule
'''.replace('ROW',f'{row:012x}').replace('NEW',f'{new:012x}')
# Discover the existing instance name rather than guessing it in the fixture.
runtime=(ROOT.parent/'voice-engine/rtl/AxisSynthSystem.v').read_text(encoding='utf-8')
import re
name=re.search(r'VoiceSynthEngine\s+(\w+)\s*\(',runtime).group(1)
body=body.replace('Voice_Inst',name)
(ROOT/'sim/tb_studio_system.v').write_text(prefix+body,encoding='utf-8')
print('Generated 76 framed local protocol transactions and complete board testbench')
