"""Extend the proven board-level UART/ADC/DAC fixture with touch gating/replay."""
from pathlib import Path
import struct,binascii
ROOT=Path(__file__).resolve().parents[2]
raw=bytes(int(x,16) for x in (ROOT/'sim/filter_packets.hex').read_text().split())
seq=int.from_bytes(raw[-48:-44],'little')+1
def packet(op,words=(),repeat=False):
    global seq
    p=bytearray(52);p[:4]=bytes([0x53,0x59,5,3]);p[4:8]=struct.pack('<I',seq);p[8]=op
    for i,w in enumerate(words):p[10+i*4:14+i*4]=struct.pack('<I',w)
    p[50:52]=struct.pack('<H',binascii.crc_hqx(p[:50],0xffff));seq+=1
    return bytes(p)
config=packet(0x31,[3,0x401520])
# First capability must precede the configuration sequence on the wire.
seq-=1
cap=packet(0x30);config=packet(0x31,[3,0x401520])
extra=cap+config+config+packet(0x32)+packet(0x31,[1,0xff1520])+packet(0x31,[0,0x401520])
(ROOT/'sim/touch_packets.hex').write_text('\n'.join(f'{x:02x}' for x in raw+extra)+'\n')
s=(ROOT/'sim/tb_studio_system.v').read_text(encoding='utf-8')
s=s.replace('tb_studio_system','tb_touch_system').replace('packets[0:4211]','packets[0:4523]').replace('sim/filter_packets.hex','sim/touch_packets.hex')
s=s.replace('SynthSystemTop #(', 'SynthSystemTop #(.C_TOUCH_ENABLE(1),')
s=s.replace('.i_clk(clk),.i_rstn(rstn),.i_adc_dout(dout),.i_uart_rx(rx),', ".i_clk(clk),.i_rstn(rstn),.i_adc_dout(dout),.i_uart_rx(rx),.i_touch_next(1'b0),")
insert='''
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
'''
s=s.replace('        completed=1;',insert+'        completed=1;')
(ROOT/'touch/sim/tb_touch_system.v').write_text(s,encoding='utf-8')
print('Generated touch system test',len(raw+extra),'bytes',seq)
