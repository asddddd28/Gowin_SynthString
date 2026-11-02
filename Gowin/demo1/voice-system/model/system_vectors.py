"""Host programs actually sent over simulated UART pins."""
import json
from system_model import ROOT,ENGINE,packet,compile_fx,UNITY,RATE


def generate():
    phase=round(220*(1<<32)/RATE)
    cases=[packet(0,kind=2),packet(1,kind=1,words=[4]),
        packet(2,0xa4,1,[100,phase,UNITY,UNITY//2]),packet(2,0xa4,1,[100,phase,UNITY,UNITY//2]),
        packet(2,0xa4,1,[101,phase,UNITY,UNITY//2]),packet(3,0xa5,0,[100]),
        packet(4,0xc4),packet(4,0xc4),packet(5,kind=1,words=[0x131])]
    on=packet(6,0xa4,2,[101,phase,UNITY,UNITY//2])
    cases.extend([on[:-1]+bytes([on[-1]^0x80]),on,packet(7,0xa5,0,[101])])
    for index,command in enumerate(compile_fx(json.loads((ENGINE/'examples/fx_room.json').read_text(encoding='utf-8')))['commands']):
        cases.append(packet(8+index,command['opcode'],command['address'],command['words']))
    cases.extend([packet(11,kind=1,words=[0x60]),packet(13,kind=2),packet(12,kind=2),packet(13,kind=2),
        packet(14,0x10),packet(15,0xa4,0,[0x80000001,phase,UNITY,UNITY//2]),
        packet(16,0xa7,0,[5,UNITY//2]),packet(17,0xc3,0,[3]),packet(18,kind=2)])
    (ROOT/'sim/uart_packets.hex').write_text('\n'.join(f'{byte:02x}' for data in cases for byte in data)+'\n',encoding='utf-8')
    (ROOT/'reports/vector-plan.json').write_text(json.dumps(dict(packets=len(cases),byte_count=sum(map(len,cases))),indent=2)+'\n',encoding='utf-8')
    from contracts import publish
    publish('tb_synth_system',[('output','o_done',1)],['Real UART and ADC pins through boot, arbitration, AXI command execution, voice/LFO/FX and independent PT8211 decoder.'],'sim/tb_synth_system.v')
    print('Generated UART test programs',len(cases))
    stress=[]
    setup=(ENGINE/'vectors/lfo_setup.txt').read_text(encoding='utf-8').splitlines()[1:]
    for line in setup:
        opcode,address,payload=(int(v,16) for v in line.split())
        words=[(payload>>(32*i))&0xffffffff for i in range(10)]
        if opcode==0xa0:words[0]=2
        stress.append(packet(19+len(stress),opcode,address,words))
    for voice in range(8):stress.append(packet(19+len(stress),0xa4,voice%4,[200+voice,phase+voice*1000000,UNITY,UNITY//2]))
    stress.append(packet(19+len(stress),0xa7,0,[5,UNITY//2]))
    stress.append(packet(19+len(stress),0xc3,0,[3]))
    stress.append(packet(19+len(stress),kind=2))
    stress.append(packet(19+len(stress),kind=1,words=[0x4c]))
    stress.append(packet(19+len(stress),kind=1,words=[0x50]))
    stress.append(packet(19+len(stress),0xc0,0,[8192<<16,1<<16,0,0,1]))
    assert len(stress)==111
    (ROOT/'sim/uart_stress.hex').write_text('\n'.join(f'{byte:02x}' for data in stress for byte in data)+'\n',encoding='utf-8')


if __name__=='__main__':generate()
