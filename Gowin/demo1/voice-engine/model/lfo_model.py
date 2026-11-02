"""LFO 与稀疏路由的独立整数语义；一帧每个源只推进一次。"""
from pathlib import Path
import json
import random
from voice_engine_model import SINE, interp, clamp
from voice_operator_model import UNITY, MASK, signed, packet

ROOT=Path(__file__).resolve().parents[1]

def random_next(seed):
    seed=seed or 1
    seed ^= (seed << 13) & MASK
    seed ^= seed >> 17
    return (seed ^ (seed << 5)) & MASK

def lfo_step(words):
    phase,increment,rng,held,flags,start,seed,width=[v & MASK for v in words]
    restart=bool(flags & 16)
    wide=phase+increment
    wrapped=bool(wide>>32) and not restart
    phase=start if restart else wide & MASK
    rng=rng or 1
    if restart:
        held=signed(seed or 1)>>5
        rng=random_next(seed)
    elif wrapped:
        held=signed(rng)>>5
        rng=random_next(rng)
    else:
        held=signed(held)
    target=signed(rng)>>5
    wave=flags&7
    if wave==0: value=interp(SINE,phase)
    elif wave==1: value=UNITY-(abs(phase-(1<<31))>>4)
    elif wave==2: value=(phase>>5)-UNITY
    elif wave==3: value=UNITY-(phase>>5)
    elif wave==4: value=UNITY if phase<width else -UNITY
    elif wave==5: value=target
    elif wave==6: value=held+((target-held)*phase>>32)
    else: value=0
    if flags&8: value=(value+UNITY)>>1
    return packet(value,phase,rng,held,int(wrapped)|(int(restart)<<1))

class ModulationModel:
    """Phase and seed state are independent from mutable patch and route parameters."""
    def __init__(self):
        self.lfos={}
        self.routes={}
        self.states=[[0,1,0] for _ in range(24)]
        self.initialized=[False]*24
        self.values=[0]*24

    def note_on(self,slot):
        self.initialized[8+slot*2:10+slot*2]=[False,False]

    def frame(self,voices):
        for context in range(24):
            voice=(context-8)//2 if context>=8 else None
            patch=voices[voice]['patch'] if voice is not None and voices[voice] else context//2 if voice is None else None
            config=self.lfos.get(patch,[[0]*5,[0]*5])[context%2]
            increment,start,flags,seed,width=config
            eligible=bool(flags&32) and (bool(flags&16)==(voice is not None)) and (voice is None or voices[voice] is not None)
            if not eligible: continue
            phase,rng,held=self.states[context]
            result=lfo_step([phase,increment,rng,held,(flags&15)|(int(not self.initialized[context])<<4),start,seed,width])
            self.values[context]=signed(result&MASK)
            self.states[context]=[(result>>(32*n))&MASK for n in (1,2,3)]
            self.initialized[context]=True

    def route(self,voice,patch):
        values=[]
        for index,config in enumerate(self.lfos.get(patch,[[0]*5,[0]*5])):
            context=8+voice*2+index if config[2]&16 else patch*2+index
            values.append(self.values[context] if config[2]&32 else 0)
        accum=[0]*15
        for flags,depth in self.routes.get(patch,[]):
            if flags&1: accum[(flags>>2)&15]+=values[(flags>>1)&1]*signed(depth)>>26
        return [clamp(v,-(1<<31),(1<<31)-1) for v in accum]

def generate():
    rng=random.Random(0x4c464f)
    rows=[]
    for wave in range(7):
        for polarity in (0,8):
            for restart in (0,16):
                for phase in [0,1,0x3fffffff,0x40000000,0x7fffffff,0x80000000,0xfffffffe,0xffffffff]:
                    rows.append([phase,1,0,0,wave|polarity|restart,phase,0,0x80000000])
    for _ in range(1800):
        rows.append([rng.getrandbits(32),rng.getrandbits(32),rng.getrandbits(32),rng.randrange(-UNITY,UNITY),
                     rng.randrange(7)|(rng.randrange(2)<<3)|(rng.randrange(2)<<4),rng.getrandbits(32),rng.getrandbits(32),rng.getrandbits(32)])
    for wave in (0,5,6):
        state=[0,1,0]
        for n in range(512):
            words=[state[0],0x01000000,state[1],state[2],wave|(16 if n==0 else 0),0,0x81328412,0x80000000]
            rows.append(words)
            result=lfo_step(words)
            state=[(result>>(32*k))&MASK for k in (1,2,3)]
    (ROOT/'vectors/lfo_step.txt').write_text(''.join(f'{packet(*w):064x} {lfo_step(w):040x}\n' for w in rows),encoding='ascii')
    (ROOT/'vectors/lfo_manifest.json').write_text(json.dumps({'transactions':len(rows)},indent=2)+'\n',encoding='utf-8')
    print(f'Generated {len(rows)} LFO oracle transactions')

if __name__=='__main__': generate()
