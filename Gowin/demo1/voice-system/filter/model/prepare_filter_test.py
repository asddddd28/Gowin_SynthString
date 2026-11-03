"""Model fixtures exercise bounds, stereo isolation, sweeps and bypass settling."""
from pathlib import Path
import math,random,shutil
from lowpass_model import Lowpass,DEFAULT,LIMIT,MAX_DEPTH,RATE

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'reports/master-lowpass/sim'
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'rom').mkdir(exist_ok=True)
for name in ['lowpass_alpha.hex','lowpass_sine.hex']:
    shutil.copyfile(ROOT/'rom'/name,OUT/'rom'/name)
    shutil.copyfile(ROOT/'rom'/name,ROOT.parent/'voice-engine/rom'/name)
rng=random.Random(17);model=Lowpass();vectors=[]
configs=[(0,DEFAULT,87961,0),(1,DEFAULT,87961,0),(1,0,87961,0),(3,DEFAULT,1759219,MAX_DEPTH),(7,DEFAULT,879609,MAX_DEPTH//2),(0,LIMIT,4398,0)]
for block,(flags,base,increment,depth) in enumerate(configs):
    for n in range(2048):
        if block in (0,3,4):left=rng.randint(-2**31,2**31-1);right=rng.randint(-2**31,2**31-1)
        elif block==2:left=0x70000000;right=0
        else:left=round(0.8*2**26*math.sin(math.tau*200*n/RATE));right=round(0.8*2**26*math.sin(math.tau*8000*n/RATE))
        a,b=model.step(left,right,flags,base,increment,depth)
        assert -2**31<=a<2**31 and -2**31<=b<2**31
        if block in (0,5) and n>=256:assert (a,b)==(left,right)
        fields=[(left,32),(right,32),(a,32),(b,32),(flags,3),(base,18),(increment,32),(depth,18),(block+1,8)]
        value=0;shift=0
        for data,width in fields:value|=(data&((1<<width)-1))<<shift;shift+=width
        vectors.append(f'{value:064x}')
(OUT/'vectors.hex').write_text('\n'.join(vectors)+'\n')
(OUT/'sources.prj').write_text('\n'.join(f'verilog work "{p.as_posix()}"' for p in [ROOT.parent/'voice-engine/rtl/AxisMasterLowpass.v',ROOT/'filter/tb_master_lowpass.v']))
(OUT/'run.tcl').write_text('run all\nquit\n')
print(f'Generated {len(vectors)} exact stereo vectors')
