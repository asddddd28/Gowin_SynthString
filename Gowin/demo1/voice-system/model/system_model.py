"""Executable contract: UART framing, resident commands, keyboard identities and PCM."""
from pathlib import Path
import json
import math
import shutil
import sys
ROOT=Path(__file__).resolve().parents[1]
ENGINE=ROOT.parent/'voice-engine'
sys.path.insert(0,str(ENGINE/'model'))
from compile_voice_patch import compile_patch, RATE, UNITY
from compile_fx import compile_fx
from dx7_bank import INITIAL, convert


def crc16(data):
    crc=0xffff
    for byte in data:
        crc^=byte<<8
        for _ in range(8): crc=((crc<<1)^0x1021 if crc&0x8000 else crc<<1)&0xffff
    return crc


def packet(sequence, opcode=0, address=0, words=(), kind=0):
    if not 0<=sequence<1<<32 or len(words)>10: raise ValueError('request range')
    payload=b''.join((w&0xffffffff).to_bytes(4,'little') for w in words).ljust(40,b'\0')
    header=bytes((0x53,0x59,5,kind))+sequence.to_bytes(4,'little')+bytes((opcode,address))+payload
    return header+crc16(header).to_bytes(2,'little')


def decode_response(data):
    if len(data)!=32 or data[:3]!=bytes((0x53,0x52,5)) or crc16(data[:30])!=int.from_bytes(data[30:],'little'):
        raise ValueError('response framing/CRC')
    return dict(kind=data[3],sequence=int.from_bytes(data[4:8],'little'),
        result=int.from_bytes(data[8:24],'little'),transport_status=data[24],opcode=data[25],address=data[26],replayed=bool(data[27]&1))


def pcm16(sample):
    rounded=(abs(sample)+1024)>>11
    return max(-32768,min(32767,-rounded if sample<0 else rounded))


class KeyboardModel:
    def __init__(self):
        self.delivered=0
        self.serial=0
        self.identities=[0]*32

    def event(self, key, pressed):
        if bool(self.delivered&(1<<key))==pressed: return None
        if pressed:
            self.serial+=1
            self.identities[key]=0x80000000|self.serial
            self.delivered|=1<<key
            return 0xa4, [self.identities[key],round(440*2**((48+key-69)/12)*(1<<32)/RATE),UNITY,UNITY//2,0x80003200|(48+key)]
        self.delivered&=~(1<<key)
        return 0xa5,[self.identities[key]]


def assets():
    for directory in ('rtl','sim','spec','reports','rom','host'):(ROOT/directory).mkdir(exist_ok=True)
    rows=[]
    factory=(ENGINE/'assets/fm1/factory.vmem').read_bytes()
    from dx7_bank import FACTORY_SHA
    import hashlib
    if hashlib.sha256(factory).hexdigest()!=FACTORY_SHA:raise ValueError('FM1 source integrity')
    for slot,index in enumerate(INITIAL):
        patch=convert(factory[index*128:(index+1)*128],index)
        rows.extend(compile_patch(patch,slot=slot)['commands'])
    fx=json.loads((ENGINE/'examples/fx_room.json').read_text(encoding='utf-8'))
    rows.extend(compile_fx(fx)['commands'])
    rows.append(dict(opcode=0xa7,address=0,words=[1,UNITY//2]+[0]*8))
    image=[len(rows)]
    for row in rows:image.extend([row['opcode']|(row['address']<<8),*row['words']])
    assert len(image)<=1024
    (ROOT/'rom/boot.hex').write_text('\n'.join(f'{v:08x}' for v in image+[0]*(1024-len(image)))+'\n',encoding='utf-8')
    notes=[round(440*2**((48+key-69)/12)*(1<<32)/RATE) for key in range(32)]
    (ROOT/'rom/keyboard_phase.hex').write_text('\n'.join(f'{n:08x}' for n in notes)+'\n',encoding='utf-8')
    shutil.copyfile(ENGINE/'rom/sine_q26.hex',ROOT/'rom/sine_q26.hex')
    for source in (ENGINE/'rom').glob('dx_*.hex'):shutil.copyfile(source,ROOT/'rom'/source.name)
    for name in ('key_thresholds.hex','raw_rest.hex','raw_bottom.hex'):
        shutil.copyfile(ROOT.parent/'keyboard-latency'/name,ROOT/name)
    (ROOT/'rom/boot.commands.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
    model=KeyboardModel()
    first=model.event(0,True)
    assert model.event(0,True) is None
    assert model.event(0,False)[1][0]==first[1][0]
    assert model.event(0,True)[1][0]!=first[1][0]
    assert pcm16(UNITY)==32767 and pcm16(-UNITY)==-32768
    assert crc16(b'123456789')==0x29b1
    (ROOT/'reports/model.json').write_text(json.dumps(dict(boot_commands=len(rows),boot_words=len(image),crc_check='29b1',sample_rate_hz=RATE),indent=2)+'\n',encoding='utf-8')
    print('PASS model, boot commands',len(rows))


if __name__=='__main__':assets()
