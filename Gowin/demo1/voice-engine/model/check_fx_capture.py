"""Replay captured AXI-system audio and active configs through the independent model."""
from fx_model import Delay, Reverb
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]


def words(raw,count,signed=True):
    result=[(int(raw,16)>>(32*i))&0xffffffff for i in range(count)]
    return [v-(1<<32) if signed and v&(1<<31) else v for v in result]


def check():
    delay,reverb=Delay(),Reverb()
    inputs=(ROOT/'reports/fx-axi-input.txt').read_text(encoding='utf-8').splitlines()
    outputs=(ROOT/'reports/fx-axi-output.txt').read_text(encoding='utf-8').splitlines()
    assert len(inputs)-len(outputs) in (0,1), 'unexpected frame loss'
    for index,(source,destination) in enumerate(zip(inputs,outputs)):
        clear,frame,raw,delay_config,reverb_config=source.split()
        result_frame,result=destination.split()
        assert int(frame,16)==int(result_frame,16), f'frame tag at {index}'
        if int(clear,16)&1: delay.clear()
        if int(clear,16)&2: reverb.clear()
        intermediate,_=delay.step(words(raw,2),words(delay_config,5))
        expected,_=reverb.step(intermediate,words(reverb_config,4))
        assert tuple(words(result,2))==expected, f'frame {index}: {words(result,2)} != {expected}'
    report=dict(status='passed',frames=len(outputs),in_flight_at_stop=len(inputs)-len(outputs))
    (ROOT/'reports/fx-axi-oracle.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('PASS AXI full-chain integer oracle',report)


if __name__=='__main__': check()
