"""Global lowpass integer reference and deterministic FPGA coefficient assets."""
from pathlib import Path
import math

RATE=50_000_000/1024
SPAN=math.log2(18000/20)
LIMIT=1023*256
MAX_DEPTH=round(6/SPAN*LIMIT)
DEFAULT=round(math.log2(2000/20)/SPAN*LIMIT)

def coefficient(index):
    frequency=20*900**(index/1023)
    distance=1-math.cos(math.tau*frequency/RATE)
    gain=math.sqrt(2)-1
    alpha=(math.sqrt(distance*distance+2*gain*distance)-distance)/gain
    return round(alpha*(1<<18))

COEFFICIENTS=[coefficient(i) for i in range(1024)]
SINES=[round(32767*math.sin(math.tau*i/256)) for i in range(256)]

class Lowpass:
    def __init__(self):
        self.phase=0;self.cutoff=DEFAULT;self.mix=0;self.states=[0]*4

    def step(self,left,right,flags=0,base=DEFAULT,increment=round(2**32/RATE),depth=0):
        self.phase=(self.phase+increment)&0xffffffff
        triangle=32767-((self.phase>>16)&32767)*2 if self.phase>>31 else -32767+((self.phase>>16)&32767)*2
        wave=triangle if flags&4 else SINES[self.phase>>24]
        target=max(0,min(LIMIT,base+((wave*depth)>>15 if flags&2 else 0)))
        difference=target-self.cutoff
        self.cutoff+= max(1,difference>>8) if difference>0 else min(-1,-((-difference)>>8)) if difference<0 else 0
        self.mix=max(0,min(1<<18,self.mix+(1024 if flags&1 else -1024)))
        alpha=COEFFICIENTS[self.cutoff>>8]
        wet=[]
        for channel,sample in enumerate((left,right)):
            for pole in range(2):
                n=channel*2+pole
                self.states[n]+=((sample-self.states[n])*alpha)>>18
                sample=self.states[n]
            wet.append(sample)
        return tuple(dry+(((value-dry)*self.mix)>>18) for dry,value in zip((left,right),wet))

if __name__=='__main__':
    root=Path(__file__).resolve().parents[2]
    for name,values,width in [('lowpass_alpha.hex',COEFFICIENTS,18),('lowpass_sine.hex',SINES,16)]:
        (root/'rom'/name).write_text('\n'.join(f'{v&((1<<width)-1):0{(width+3)//4}x}' for v in values)+'\n')
    assert all(0<a<(1<<18) for a in COEFFICIENTS)
    assert all(a<=b for a,b in zip(COEFFICIENTS,COEFFICIENTS[1:]))
    for n in (0,100,500,800,1023):
        a=COEFFICIENTS[n]/2**18;f=20*900**(n/1023)
        power=(a*a/(1+(1-a)**2-2*(1-a)*math.cos(math.tau*f/RATE)))**2
        assert abs(10*math.log10(power)+3.0103)<.02
    model=Lowpass()
    for n in range(1000):
        sample=round(math.sin(n)*2**30)
        assert model.step(sample,-sample)==(sample,-sample)
    print(f'PASS lowpass model and coefficient response; default={DEFAULT},max_depth={MAX_DEPTH}')
