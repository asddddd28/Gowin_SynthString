"""Compile shared Delay/Reverb settings to the FX domain's AXI mailbox commands.

Offline only: no serial/USB connection or board mutation. Execute one command,
check completion, then advance sequence. On retry preserve opcode/words/sequence.
"""
import argparse
import json
import math
from pathlib import Path
from compile_voice_patch import number, RATE, UNITY


def flag(config, name, default):
    result=config.get(name,default)
    if not isinstance(result,bool): raise ValueError(name+' must be boolean')
    return int(result)


def compile_fx(config, epoch=1, sequence=0):
    for value,maximum,name in [(epoch,0xffffff,'epoch'),(sequence,0xfffffffc,'sequence')]:
        if isinstance(value,bool) or not isinstance(value,int) or not 0<=value<=maximum:
            raise ValueError(name+' out of range')
    delay=config.get('delay',{})
    reverb=config.get('reverb',{})
    times=[]
    for channel in ('left','right'):
        milliseconds=number(delay.get(channel+'_ms',250),1000/RATE,(32768-1/65536)*1000/RATE,channel+'_ms')
        times.append(min(0x7fffffff,round(milliseconds*RATE*65536/1000)))
    feedback=math.trunc(number(delay.get('feedback',0.35),-0.95,0.95,'delay feedback')*UNITY)
    delay_words=times+[feedback,round(number(delay.get('wet',0.25),0,1,'delay wet')*UNITY),
        flag(delay,'enabled',True)|(flag(delay,'pingpong',False)<<1)]
    reverb_words=[math.trunc(number(reverb.get('feedback',0.7),0,0.9,'reverb feedback')*UNITY),
        math.trunc(number(reverb.get('damping',0.3),0,0.95,'damping')*UNITY),
        round(number(reverb.get('wet',0.2),0,1,'reverb wet')*UNITY),flag(reverb,'enabled',True)]
    commands=[]
    for index,(opcode,words) in enumerate([(0xc0,delay_words),(0xc1,reverb_words),(0xc2,[])]):
        words=[x&0xffffffff for x in words]+[0]*(10-len(words))
        seq=sequence+index
        writes=[dict(address=0x100+4*n,value=word) for n,word in enumerate(words)]
        writes.extend([dict(address=0x128,value=opcode),dict(address=0x12c,value=seq),
            dict(address=0x134,value=epoch<<8),dict(address=0x138,value=seq),dict(address=0x130,value=1)])
        commands.append(dict(opcode=opcode,address=0,epoch=epoch,sequence=seq,words=words,axi_writes=writes))
    return dict(abi='0x00010005',domain='fx',name=config.get('name','Shared FX'),sample_rate_hz=RATE,
        next_sequence=sequence+3,commands=commands)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--epoch',type=int,default=1)
    parser.add_argument('--sequence',type=int,default=0)
    args=parser.parse_args()
    result=compile_fx(json.loads(args.config.read_text(encoding='utf-8')),args.epoch,args.sequence)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print(f"Compiled {result['name']}: 3 FX commands; next sequence {result['next_sequence']}")


if __name__=='__main__': main()
