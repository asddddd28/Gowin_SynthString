"""Independent integer oracle for the board's smaller delay RAM, including wrap."""
import random
from system_model import ROOT, ENGINE
from fx_model import Delay, UNITY, packed
from contracts import publish


def generate():
    model=Delay(13)
    rng=random.Random(7601)
    rows=[]
    for frame in range(50000):
        clear=frame in (0,21000)
        if clear:model.clear()
        config=(0x1fffffff,8190<<16,-UNITY//2,UNITY,3)
        if frame>=40000:config=(int(11.75*65536),int(23.25*65536),UNITY//3,UNITY//2,1)
        audio=tuple(rng.randrange(-UNITY,UNITY) for _ in range(2)) if frame<200 or 22000<=frame<22200 or frame>=40000 else (0,0)
        result,clip=model.step(audio,config)
        rows.append(f'{int(clear):x} {packed(config):040x} {packed(audio):016x} {packed(result):016x} {int(clip):x}')
    (ROOT/'sim/compact_delay.txt').write_text('\n'.join(rows)+'\n',encoding='utf-8')
    name='tb_compact_delay'
    publish(name,[('output','o_done',1)],['13-bit ring oracle, maximum fractional delay, two wraps, clear, busy parameter snapshot and output stalls.'],f'sim/{name}.v')
    source=(ENGINE/'sim/tb_fx_delay.v').read_text(encoding='utf-8')
    source=source.replace('tb_fx_delay',name).replace('AxisStereoDelay Dut_Inst','AxisStereoDelay #(.C_DELAY_ADDR_BITS(13)) Dut_Inst').replace('vectors/fx_delay.txt','sim/compact_delay.txt')
    (ROOT/f'sim/{name}.v').write_text(source,encoding='utf-8')
    print('Generated compact delay oracle',len(rows))


if __name__=='__main__':generate()
