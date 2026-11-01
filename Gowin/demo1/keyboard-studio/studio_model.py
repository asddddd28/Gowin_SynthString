"""独立的 Studio 配置/串口/混合整数合同，生成 RTL 前冻结。"""
from pathlib import Path
import math, json

ROOT=Path(__file__).resolve().parent
RATE=50_000_000/1024
def crc(data):
    result=0xffff
    for byte in data:
        result ^= byte<<8
        for _ in range(8):result=((result<<1)^0x1021 if result&0x8000 else result<<1)&65535
    return result

def packet(op,seq,key,payload=b''):
    assert 0<=key<128 and len(payload)<=64
    data=bytes([0xa5,0xc3,op,seq,key])+payload.ljust(64,b'\0')
    return data+crc(data).to_bytes(2,'little')

def step(ms):
    raw=round(262143*16384/max(1,ms*RATE/1000))
    exponent=0
    while raw>2047:raw=(raw+1)//2;exponent+=1
    return raw|(exponent<<11)

def profile(note=60,mode='mix',wave_a=0,wave_b=0,ratio=1,depth=0,
            attack=10,decay=150,sustain=.75,release=200,
            mod_attack=0,mod_decay=0,mod_sustain=1,mod_release=120,
            gain_a=1,gain_b=0,cutoff=2500,resonance=.1,filter_mode=1,velocity=96,morph=0):
    freq=440*2**((note-69)/12)
    increment=round(freq*2**32/RATE)
    # The SVF runs two internal substeps: f=2*sin(pi*cutoff/(2*sample_rate)).
    f=round(2*math.sin(math.pi*cutoff/(2*RATE))*2**28)
    damping=round((2-1.8*resonance)*2**28)
    scale=max(1,gain_a+gain_b)
    fields=[(round(increment*ratio),0),(increment,32),
      (round(increment*depth) if mode=='fm' else 0,64),(1,96),
      (step(attack),97),(step(decay),115),(round(sustain*262143),133),(step(release),151),
      (wave_b,171),(wave_a,174),(round(morph*65535),177),
      (round(depth*2**26) if mode in ['am','ring'] else 0,196),
      ({'am':1,'ring':2}.get(mode,0),228),(f,230),(damping,262),
      (0x0051eb85,294),(1<<28,326),(filter_mode,358),(velocity,361),(1,368),
      (1,376),(step(mod_attack),377),(step(mod_decay),395),(round(mod_sustain*262143),413),
      (step(mod_release),431),(round(gain_a/scale*65535),449),
      (round(gain_b/scale*65535),465),(int(mode=='mix'),481)]
    result=sum(value<<shift for value,shift in fields)
    assert result.bit_length()<=512
    return result

def mix(carrier,mod,depth,mode,ga,gb,blend):
    depth=min(2**26,depth);mod=max(-2**26,min(2**26,mod))
    distance=depth-((depth*mod)>>26)
    factor=2**26-(distance>>1) if mode==1 else 2**26-distance if mode==2 else 2**26
    a=(((carrier*factor)>>26)*ga)>>16
    b=(mod*gb)>>16
    return max(-2**31,min(2**31-1,a+(b if blend else 0)))

if __name__=='__main__':
    assert crc(b'123456789')==0x29b1
    assert len(packet(1,1,0,profile().to_bytes(64,'little')))==71
    (ROOT/'note_profiles.hex').write_text(''.join(f'{profile(48+i):0128x}\n' for i in range(32)))
    (ROOT/'reports').mkdir(exist_ok=True)
    (ROOT/'reports/model.json').write_text(json.dumps({'sample_rate':RATE,'profile_bits':512,
      'stages':[7,0,1,2,3,4,5,6],'prefetch_clocks':2,'crc_check':True,
      'memory':'synchronous profile/state banks; boot explicitly clears each state',
      'commit':'per-key next note-on snapshot; note-off must keep sounding profile',
      'gates':['compile','ast','readability','comment','naming','profile','testbench','toolchain'],
      'risks':['RAM read alignment','release uses active snapshot','timing and BSRAM fit','partial packets never commit'],
      'verification':['CRC/noise/timeout','dual envelopes','mix/FM/AM/ring','32 keys','ACK after commit','DAC deadline']},indent=2))
    print('PASS Studio independent model')
