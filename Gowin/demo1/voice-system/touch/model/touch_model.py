"""Reference semantics for normalized coordinates, diagonal controls and crossings."""
from pathlib import Path
import math

ROOT=Path(__file__).resolve().parents[2]
def centroid(weights,mask,centers):
    selected=[i for i in range(len(weights)) if mask>>i&1]
    if not selected or selected[-1]-selected[0]+1!=len(selected):return None
    total=sum(max(1,weights[i]) for i in selected)
    return sum(max(1,weights[i])*centers[i] for i in selected)//total

def selected_key(mask,row):
    keys=[i for i in range(8) if mask>>(row*8+i)&1]
    return row*8+max(keys) if keys else None

def targets(x,y,mode,gain=32,pitch=21,cutoff=64):
    diagonal=x-y
    if mode==0:return 65536+(diagonal*gain>>1),0,0
    if mode==1:
        index=max(0,min(255,128+(diagonal*pitch>>10)))
        return 65536,(round(65536*2**((index-128)/128))-65536)<<10,0
    if mode==2:return 65536,0,diagonal*cutoff*834>>10
    return 65536,0,0

class Crossings:
    def __init__(self):self.sides=[None]*4;self.time=None;self.hits=[-100]*4
    def step(self,y,now):
        if y is None or self.time is None or now-self.time>=40:self.sides=[None]*4
        mask=0
        if y is not None:
            for i,line in enumerate([128,384,640,896]):
                side=1 if y>line+20 else -1 if y<line-20 else None
                if side is not None:
                    if self.sides[i] is not None and side!=self.sides[i] and now-self.hits[i]>=12:mask|=1<<i;self.hits[i]=now
                    self.sides[i]=side
        self.time=now if y is not None else None
        return mask

if __name__=='__main__':
    assert selected_key(0b10101,0)==4 and selected_key(0,2) is None
    c=Crossings();assert c.step(0,0)==0;assert c.step(1023,10)==15;assert c.step(1023,20)==0
    assert c.step(None,25)==0 and c.step(0,30)==0 and c.step(1023,80)==0
    for mode in range(3):
        a=targets(0,1023,mode);b=targets(1023,0,mode);assert a[mode]<b[mode]
    (ROOT/'rom/touch_pitch.hex').write_text('\n'.join(f'{round(65536*2**((i-128)/128)):05x}' for i in range(256))+'\n')
    print('PASS model: row selection, no touchdown/stale pluck, diagonal endpoints, pitch ROM')
