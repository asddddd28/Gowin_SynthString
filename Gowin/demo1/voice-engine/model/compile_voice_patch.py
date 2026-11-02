"""Compile a six-row patch to resident engine commands and AXI register writes.

This is an offline compiler: it never opens a serial port or changes the board.
The controller submits the returned writes, checks each completion, then advances
the sequence. Retrying uses the same epoch/sequence and the same image.
"""
import argparse
import json
import math
from pathlib import Path

UNITY=1<<26
PHASE=1<<32
RATE=50_000_000/1024
WAVES={'sine':0,'triangle':1,'saw':2,'pulse':3,'noise':4,'wavetable':5}
MODES={'pm':0,'fm':1,'am':2,'ring':3}
LFO_WAVES={'sine':0,'triangle':1,'saw_up':2,'saw_down':3,'pulse':4,'sample_hold':5,'smooth_random':6}
TARGETS={'pitch':0,'gain':1,'pan':2,**{f'op{n}_gain':3+n for n in range(6)},**{f'op{n}_depth':9+n for n in range(6)}}

def lfo_words(config,tempo=120):
    wave=LFO_WAVES[config.get('wave','sine')]
    scope=config.get('scope','voice')
    if scope not in ('voice','global'): raise ValueError('LFO scope must be voice or global')
    enabled=config.get('enabled',True); unipolar=config.get('unipolar',False)
    if not isinstance(enabled,bool) or not isinstance(unipolar,bool): raise ValueError('LFO flags must be boolean')
    if 'beats_per_cycle' in config:
        if 'rate_hz' in config: raise ValueError('choose rate_hz or beats_per_cycle, not both')
        rate=number(tempo,1,999,'tempo_bpm')/60/number(config['beats_per_cycle'],0.03125,256,'beats_per_cycle')
    else: rate=config.get('rate_hz',1)
    rate=number(rate,0,100,'rate_hz')
    phase=number(config.get('phase',0),0,1,'phase')
    seed=config.get('seed',1)
    if not isinstance(seed,int) or isinstance(seed,bool) or not 0<=seed<PHASE: raise ValueError('LFO seed must be uint32')
    width=number(config.get('pulse_width',0.5),0,1,'LFO pulse_width')
    return [round(rate*PHASE/RATE),round(phase*PHASE)&0xffffffff,
            wave|(int(unipolar)<<3)|(int(scope=='voice')<<4)|(int(enabled)<<5),seed,min(PHASE-1,round(width*PHASE))]

def number(value, lower, upper, name):
    if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value) or not lower<=value<=upper:
        raise ValueError(f'{name}: expected finite value in [{lower}, {upper}]')
    return value

def compile_patch(patch, slot=0, epoch=1, sequence=0):
    number(slot,0,3,'slot'); number(epoch,0,(1<<24)-1,'epoch'); number(sequence,0,(1<<32)-25,'sequence')
    if not all(isinstance(v,int) for v in (slot,epoch,sequence)):
        raise ValueError('slot, epoch and sequence must be integers')
    operators=patch['operators']
    if not isinstance(operators,list) or len(operators)!=6: raise ValueError('exactly six rows required (unused rows may be disabled)')
    revision=patch.get('revision',1)
    if not isinstance(revision,int) or isinstance(revision,bool) or not 1<=revision<PHASE: raise ValueError('revision must be uint32 and positive')
    rows=[]; carriers=0
    for index,op in enumerate(operators):
        wave=WAVES[op.get('wave','sine')]; mode=MODES[op.get('mode','pm')]
        enabled=op.get('enabled',True); carrier=op.get('carrier',False)
        if not isinstance(enabled,bool) or not isinstance(carrier,bool): raise ValueError('enabled/carrier must be booleans')
        sources=op.get('sources',[])
        if any(not isinstance(n,int) or isinstance(n,bool) or n<0 or n>=index for n in sources) or len(set(sources))!=len(sources):
            raise ValueError('sources must uniquely reference earlier rows; feedback has its own field')
        flags=sum(1<<n for n in sources)|(int(carrier)<<6)|(wave<<7)|(mode<<10)|(int(enabled)<<12)|(1<<14)
        if 'fixed_hz' in op:
            tuning=round(number(op['fixed_hz'],0,RATE/2-1,'fixed_hz')*PHASE/RATE); flags|=1<<13
        else: tuning=round(number(op.get('ratio',1),0,64 if 'dx7' in op else 16,'ratio')*65536)
        gain=round(number(op.get('gain',1),0,1,'gain')*UNITY)
        depth=round(number(op.get('depth',0),0,1,'depth')*UNITY) if mode>=2 else round(number(op.get('depth',0),-0.5,0.499999,'depth')*PHASE)
        feedback=round(number(op.get('feedback',0),-0.5,0.499999,'feedback')*PHASE)
        shape=round(number(op.get('morph',0),0,1,'morph')*65536) if wave==5 else min(PHASE-1,round(number(op.get('pulse_width',0.5),0,1,'pulse_width')*PHASE))
        if 'dx7' in op:
            if wave != 0 or mode != 0: raise ValueError('DX profile requires sine/PM')
            dx=op['dx7']
            def uint(value, maximum, name):
                number(value,0,maximum,name)
                if not isinstance(value,int): raise ValueError(f'{name}: integer required')
                return value
            output=uint(dx['output'],127,'DX output')
            shape=uint(dx['profile'],0x7fffffff,'DX scaling')
            if any(((shape>>n)&127)>99 for n in (0,7,14)): raise ValueError('DX scaling range')
            flags|=(1<<15)|(output<<16)
            depth=0;feedback=uint(dx.get('feedback',0),7,'DX feedback')
            levels=[uint(x,4032,'DX EG level') for x in dx['levels']]
            steps=[uint(x,63,'DX EG rate') for x in dx['rates']]
            if len(levels)!=4 or len(steps)!=4 or levels[3]!=0: raise ValueError('DX requires four stages and zero release level')
        else:
            levels=op.get('levels',[1,0.7,0.5,0])
            times=op.get('segment_ms',[5,80,120,180])
            if len(levels)!=4 or len(times)!=4 or levels[3]!=0: raise ValueError('four levels/times required; release target must be zero')
            levels=[round(number(v,0,1,'level')*UNITY) for v in levels]
            # Native full-scale linear ramp duration; DX mode has a separate log EG.
            steps=[max(1,round(UNITY/(max(1,number(t,0,60000,'segment_ms')*RATE/1000)))) for t in times]
        rows.append(([tuning,gain,depth,feedback,flags,shape],levels+steps))
        carriers+=enabled and carrier
    if not carriers: raise ValueError('at least one enabled carrier required')
    raw=[(0xa0,slot,[revision])]
    for n,(core,eg) in enumerate(rows): raw.extend([(0xa1,slot*8+n,core),(0xa2,slot*8+n,eg)])
    lfos=patch.get('lfos',[]); routes=patch.get('routes',[])
    if not isinstance(lfos,list) or len(lfos)>2 or not isinstance(routes,list) or len(routes)>8:
        raise ValueError('at most two LFOs and eight modulation routes')
    for index,config in enumerate(lfos): raw.append((0xb0,slot*8+index,lfo_words(config,patch.get('tempo_bpm',120))))
    for index,route in enumerate(routes):
        source=route['source']; target=TARGETS[route['target']]
        if not isinstance(source,int) or isinstance(source,bool) or not 0<=source<len(lfos): raise ValueError('route source must identify a declared LFO')
        enabled=route.get('enabled',True)
        if not isinstance(enabled,bool): raise ValueError('route enabled must be boolean')
        phase_depth=target>=9 and operators[target-9].get('mode','pm') in ('pm','fm')
        depth=round(number(route['depth'],-0.5 if phase_depth else -1,0.499999 if phase_depth else 1,'route depth')*(PHASE if phase_depth else UNITY))
        raw.append((0xb1,slot*8+index,[int(enabled)|(source<<1)|(target<<2),depth]))
    raw.append((0xa3,slot,[]))
    commands=[]
    for offset,(opcode,address,words) in enumerate(raw):
        words=[x&0xffffffff for x in words]+[0]*(10-len(words))
        seq=sequence+offset
        writes=[{'address':0x100+4*n,'value':word} for n,word in enumerate(words)]
        writes += [{'address':0x128,'value':opcode},{'address':0x12c,'value':seq},
                   {'address':0x134,'value':epoch<<8|address},{'address':0x138,'value':seq},{'address':0x130,'value':1}]
        commands.append(dict(opcode=opcode,address=address,epoch=epoch,sequence=seq,words=words,axi_writes=writes))
    return dict(abi='0x00010005' if any('dx7' in op for op in operators) else '0x00010003',name=patch.get('name','Untitled'),sample_rate_hz=RATE,
                slot=slot,revision=revision,next_sequence=sequence+len(raw),commands=commands)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('patch',type=Path); parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--slot',type=int,default=0); parser.add_argument('--epoch',type=int,default=1)
    parser.add_argument('--sequence',type=int,default=0)
    args=parser.parse_args()
    result=compile_patch(json.loads(args.patch.read_text(encoding='utf-8')),args.slot,args.epoch,args.sequence)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f"Compiled {result['name']}: {len(result['commands'])} commands; next sequence {result['next_sequence']}")

if __name__=='__main__': main()
