"""Generate independently calculated audio/state vectors and command timelines."""
from pathlib import Path
from lfo_model import ModulationModel
from voice_engine_model import VoiceModel, preset, packet, UNITY
from compile_voice_patch import lfo_words

ROOT=Path(__file__).resolve().parents[1]
FRAMES=1600

def generate():
    model=VoiceModel(preset(1));mod=ModulationModel();model.modulator=mod
    setup=[];timeline=[];samples=[];states=[]
    banks={}
    target_sets=[[0,1,2,3,8,9,10,14],[0,1,2,4,5,6,7,8],[0,1,2,9,10,11,12,13],[0,0,0,1,2,8,13,14]]
    for p in range(4):
        model.patches[p]=preset(1)
        lfos=[lfo_words(dict(wave=['sine','saw_up','pulse','smooth_random'][p],scope='global',rate_hz=100-p*7,phase=p/4,seed=0x9e3779b9+p)),
              lfo_words(dict(wave=['triangle','saw_down','sample_hold','sine'][p],scope='voice',rate_hz=93-p*5,phase=p/8,seed=0xfedcba98+p,unipolar=p==2))]
        routes=[]
        for n,target in enumerate(target_sets[p]):
            depth=[UNITY//10,-UNITY//3,UNITY//2,UNITY//2,-UNITY//2,0x70000000,-0x70000000,UNITY//3][n]
            if p==3 and target==0: depth=0x7fffffff  # colliding positive depths exercise guard-bit saturation
            routes.append([1|((n%2)<<1)|(target<<2),depth])
        mod.lfos[p]=lfos;mod.routes[p]=routes;banks[p]=(lfos,routes)
        setup.append((0xa0,p,packet(1)))
        for op,(core,eg) in enumerate(model.patches[p]): setup.extend([(0xa1,p*8+op,packet(*core)),(0xa2,p*8+op,packet(*eg))])
        for n,c in enumerate(lfos):setup.append((0xb0,p*8+n,packet(*c)))
        for n,c in enumerate(routes):setup.append((0xb1,p*8+n,packet(*c)))
        setup.append((0xa3,p,0))
    setup.append((0xa7,0,packet(1,UNITY)))
    for frame in range(FRAMES):
        commands=[]
        if frame in (10,37,600):
            slots=range(4) if frame==10 else range(4,8) if frame==37 else range(8)
            for v in slots:
                identity=v+(200 if frame==600 else 100)
                inc=20000000+v*765432;gain=UNITY-v*2000000;pan=v*UNITY//7
                model.on(identity,inc,gain,pan,v%4)
                commands.append((0xa4,v%4,packet(identity,inc,gain,pan)))
        if frame==80:
            commands.append((0xa4,0,packet(100,20000000,UNITY,0)))
            model.on(100,20000000,UNITY,0,0)
        if frame==200:
            model.voices[1].update(inc=43000000,target_gain=UNITY//3,target_pan=UNITY*3//4)
            commands.append((0xa6,1,packet(101,43000000,UNITY//3,UNITY*3//4)))
        if frame==300:
            model.sustain=True;commands.append((0xa7,0,packet(3,UNITY)))
        if frame==320:
            for v in range(8):model.off(100+v);commands.append((0xa5,0,packet(100+v)))
        if frame==400:
            model.sustain=False
            for v in model.voices:
                if v and not v['held']:v['event']=2
            commands.append((0xa7,0,packet(1,UNITY)))
        if frame==520:
            mod.initialized[0]=False
            commands.append((0xb3,0,0))
        if frame==900:
            # New bank changes frequency/routes; live phase and RNG must continue.
            mod.lfos[0][0][0]//=2
            mod.routes[0][0][1]=-UNITY//4
            commands.append((0xa0,0,packet(2)))
            for op,(core,eg) in enumerate(model.patches[0]):commands.extend([(0xa1,op,packet(*core)),(0xa2,op,packet(*eg))])
            for n,c in enumerate(mod.lfos[0]):commands.append((0xb0,n,packet(*c)))
            for n,c in enumerate(mod.routes[0]):commands.append((0xb1,n,packet(*c)))
            commands.append((0xa3,0,0))
        timeline.append(str(len(commands)))
        timeline.extend(f'{op:02x} {addr:02x} {raw:080x}' for op,addr,raw in commands)
        l,r=model.frame();samples.append(f'{packet(l,r):016x}')
        states.append(' '.join(f'{packet(mod.values[c],mod.states[c][0],int(mod.initialized[c])<<10,mod.states[c][1]):032x}' for c in range(24)))
    (ROOT/'vectors/lfo_setup.txt').write_text(str(len(setup))+'\n'+'\n'.join(f'{op:02x} {a:02x} {raw:080x}' for op,a,raw in setup)+'\n',encoding='ascii')
    (ROOT/'vectors/lfo_timeline.txt').write_text('\n'.join(timeline)+'\n',encoding='ascii')
    (ROOT/'vectors/lfo_pcm.txt').write_text('\n'.join(samples)+'\n',encoding='ascii')
    (ROOT/'vectors/lfo_states.txt').write_text('\n'.join(states)+'\n',encoding='ascii')
    print(f'Generated {len(setup)} setup commands, {FRAMES} PCM frames and {FRAMES*24} LFO state snapshots')

if __name__=='__main__':generate()
