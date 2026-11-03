"""Reproducible native bank: explicit Tone.js adaptations and original recipes.

No serial IO. --fetch saves pinned upstream source and its MIT notice once.
The generated JSON is consumed directly by Rust, not the legacy two-osc converter.
"""
from pathlib import Path
import argparse,copy,hashlib,json,math,urllib.request

SYSTEM=Path(__file__).resolve().parents[1]
ASSETS=SYSTEM.parent/'desktop-tauri/src-tauri/assets'
SHA='105c04cc00289caf49684ac5c7621bce8a042c4c'
BASE=f'https://github.com/Tonejs/Tone.js/blob/{SHA}/'
FILES=['LICENSE.md','Tone/instrument/AMSynth.ts','Tone/instrument/FMSynth.ts',
       'Tone/instrument/ModulationSynth.ts','Tone/instrument/NoiseSynth.ts',
       'examples/amSynth.html','examples/fmSynth.html']

def op(**kw):
    value=dict(enabled=True,carrier=False,wave='sine',mode='pm',sources=[],ratio=1.,fixed_hz=None,
               gain=1.,depth=0.,feedback=0.,morph=0.,pulse_width=.5,
               levels=[1.,.6,.6,0.],segment_ms=[5.,300.,0.,250.])
    value.update(kw)
    return value

def env(attack,decay,sustain,release):
    # Hardware time means a full-scale linear ramp; compensate level distance.
    return dict(levels=[1.,sustain,sustain,0.],
                segment_ms=[attack,decay/max(1e-4,1-sustain) if sustain<1 else 0,0,
                            release/max(.05,sustain)])

def hit(attack,decay,release=60):
    return dict(levels=[1.,0.,0.,0.],segment_ms=[attack,decay,0.,release])

def fixed(hz,**kw):return op(ratio=None,fixed_hz=hz,**kw)

def pair(mode,ratio=2,depth=.2,wave='sine',modwave='sine',gain=.72,
         carrier_env=None,mod_env=None,modgain=1.,modhz=None):
    m=op(wave=modwave,gain=modgain,ratio=ratio if modhz is None else None,fixed_hz=modhz,
         **(mod_env or env(2,200,.3,200)))
    c=op(carrier=True,wave=wave,mode=mode,sources=[0],gain=gain,depth=depth,
         **(carrier_env or env(5,400,.55,250)))
    return [m,c]

def build():
    rows=[]
    def add(id,title,category,description,ops,source='SynthString 原创',path=None,notes=None):
        padded=copy.deepcopy(ops)+[op(enabled=False,gain=0.) for _ in range(6-len(ops))]
        assert len(padded)==6
        rows.append(dict(id=id,title=title,category=category,description=description,
                         source=source,source_url=BASE+path if path else None,
                         adaptation=notes or ['为当前定点六算子引擎设计；不需要波表或效果器。'],
                         percussive=category=='Drum',patch=dict(name=title,operators=padded)))
    tone_note=['保留原有比率与双包络结构；指数曲线改为硬件线性段，起音重置相位，电平重新整理，非逐样本复刻。']
    ce=env(10,10,1,500);me=env(500,0,1,500)
    add('am-tone-basic','AM · Tone 柔和合成','AM','正弦载波与三倍频方波调制，调制缓慢进入。',
        pair('am',3,1,modwave='pulse',modgain=10**(-10/20),carrier_env=ce,mod_env=me),
        'Tone.js AMSynth 默认参数','Tone/instrument/ModulationSynth.ts',tone_note)
    fat=pair('am',2.5,1,wave='saw',modwave='pulse',modgain=10**(-10/20),
             carrier_env=env(100,200,.2,300),mod_env=env(500,10,1,500))
    for cents in [-10,10]:
        c=copy.deepcopy(fat[1]);c['ratio']=2**(cents/1200);fat.append(c)
    add('am-tone-saw','AM · Tone 锯齿合奏','AM','2.5 倍频 AM 与三层轻微失谐锯齿，适合短和弦。',fat,
        'Tone.js AMSynth 示例改编','examples/amSynth.html',tone_note+['fatsawtooth 改为三个显式载波，失谐 ±10 cents；当前锯齿未带限，高音区可能混叠。'])
    add('am-soft-bell','AM · 柔光钟','AM','非整数比率的边频，短调制包络带出柔和金属感。',
        pair('am',2.72,.95,carrier_env=env(2,950,.08,300),mod_env=env(1,450,.05,200)))
    add('am-reed','AM · 芦管','AM','三角载波与同频正弦 AM，带有中低频簧片感。',pair('am',1,.8,wave='triangle',carrier_env=env(25,180,.65,180),mod_env=env(12,140,.6,120)))
    add('am-tremolo-pad','AM · 呼吸铺底','AM','固定 4 Hz 振幅调制，缓慢起音，和弦共用现有复音。',pair('am',1,.7,wave='triangle',modhz=4,carrier_env=env(350,700,.7,650),mod_env=env(10,0,1,700)))
    add('am-pluck','AM · 木质拨弦','AM','双正弦 1.5 比率 AM，零持续电平，按住自然收尾。',pair('am',1.5,.9,carrier_env=hit(2,450,100),mod_env=hit(1,220,80)))

    # Tone FMSynth frequency deviation = carrier_hz * modulationIndex * (-10dB mod).
    # Integral of a +/-1 square is a triangle of amplitude 1/(4*f_mod).
    # Thus PM depth cycles = index * 10^(-10/20)/(4*harmonicity).
    fm_note=tone_note+['原方波线性 FM 转为三角波 PM，深度=index×10^(-10/20)/(4×比率)；稳态关系可对应，包络变化时仍为近似。']
    add('pm-tone-basic','PM · Tone 经典','PM','三角调制波驱动正弦载波，来自 Tone FMSynth 默认结构。',
        pair('pm',3,10*10**(-10/20)/12,modwave='triangle',carrier_env=ce,mod_env=me),
        'Tone.js FMSynth 默认参数改编','Tone/instrument/FMSynth.ts',fm_note)
    add('pm-tone-bright','PM · Tone 明亮主音','PM','较强的 PM 深度与渐入调制，适合旋律和合成器主音。',
        pair('pm',3,12.22*10**(-10/20)/12,modwave='triangle',carrier_env=env(10,200,1,500),mod_env=env(200,10,1,500)),
        'Tone.js FMSynth 示例改编','examples/fmSynth.html',fm_note)
    add('pm-electric-piano','PM · 柔亮电钢','PM','二倍频短调制与长载波衰减，独立音色包络。',pair('pm',2,.22,carrier_env=env(2,1150,.07,260),mod_env=hit(1,420,110)))
    add('pm-round-bass','PM · 圆润贝斯','PM','同频 PM 的短促泛音进入厚实基音，适合低音区。',pair('pm',1,.19,carrier_env=env(3,450,.45,130),mod_env=env(1,160,.08,70)))
    add('pm-marimba','PM · 木琴','PM','非整数比率短泛音与快速衰减，按住不会持续长鸣。',pair('pm',3.5,.14,carrier_env=hit(1,600,90),mod_env=hit(0,75,40)))
    add('pm-glass-bell','PM · 玻璃钟','PM','2.71 比率带出非谐波钟声，尾音逐渐变柔。',pair('pm',2.71,.32,carrier_env=hit(2,1800,450),mod_env=hit(1,1000,300)))

    drum_note=['固定频率，不随琴键音高改变；持续电平为零，按住自动衰减，提前松键按释放段收尾。',
               '共享低通会同时影响鼓与旋律；试听原始鼓色时可先旁路低通。']
    add('drum-kick','Drum · 深底鼓','Drum','55 Hz 正弦鼓身加短促 PM 起音和噪声击打。',
        [fixed(83,**hit(0,24,20)),fixed(55,carrier=True,sources=[0],depth=.22,gain=.85,**hit(.3,430,100)),
         fixed(4000,wave='noise',carrier=True,gain=.12,**hit(0,8,8))],notes=drum_note+['鼓身为固定频率加 PM 瞬态；没有模拟 808 的指数音高下滑。'])
    add('drum-snare','Drum · 电子军鼓','Drum','190 Hz 鼓膜与短噪声尾音，力度改变整体强度。',
        [fixed(330,gain=.6,**hit(0,35,20)),fixed(190,carrier=True,sources=[0],depth=.15,gain=.7,**hit(.5,150,60)),
         fixed(1,wave='noise',carrier=True,gain=.65,**hit(.5,210,60))],notes=drum_note)
    add('drum-tom','Drum · 低音通鼓','Drum','115 Hz 鼓身与二倍频 PM 瞬态，低沉的电子通鼓。',
        [fixed(230,**hit(0,45,25)),fixed(115,carrier=True,sources=[0],depth=.2,gain=.75,**hit(1,360,100))],notes=drum_note)
    for id,title,decay in [('drum-hat-closed','Drum · 闭镲',70),('drum-hat-open','Drum · 开镲',650)]:
        ops=[]
        for index,(mod,carrier) in enumerate([(3250,4870),(4310,6230),(5570,7910)]):
            ops += [fixed(mod,wave='pulse',gain=.9,**hit(.2,decay,40)),
                    fixed(carrier,carrier=True,mode='am',sources=[2*index],depth=1,gain=.6,**hit(.3,decay,70))]
        add(id,title,'Drum','三个非整数频率 AM 金属声部；'+('短尾闭镲。' if decay<100 else '长尾开镲。'),ops,notes=drum_note+['未加独立高通、未实现开/闭镲互斥组；高频为电子金属打击近似。'])
    add('drum-clave','Drum · 木击','Drum','1750 Hz 短正弦与弱 PM 瞬态，清晰的木质敲击。',
        [fixed(2800,**hit(0,6,8)),fixed(1750,carrier=True,sources=[0],depth=.08,gain=.75,**hit(.2,65,25))],notes=drum_note)
    add('drum-cowbell','Drum · 牛铃','Drum','540 / 800 Hz 方波 AM，带有电子鼓机式金属边频。',
        [fixed(800,wave='pulse',**hit(.2,180,60)),fixed(540,wave='pulse',carrier=True,mode='am',sources=[0],depth=.9,gain=.65,**hit(.5,300,100))],notes=drum_note)
    add('drum-tone-noise','Drum · Tone 噪声击','Drum','白噪声加 100 ms 衰减包络，适合短促沙锤与噪声打击。',
        [op(enabled=False,gain=0),fixed(1,wave='noise',carrier=True,gain=.5,**hit(5,100,40))],
        'Tone.js NoiseSynth 结构改编','Tone/instrument/NoiseSynth.ts',drum_note+['保留白噪声、100 ms 衰减与零持续，起音/释放和电平按当前键床重设；非真实鼓采样。'])
    assert len(rows)==20
    return dict(format='synthstring-native-presets-v1',version=1,source_commit=SHA,presets=rows)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--fetch',action='store_true');args=parser.parse_args()
    if args.fetch:
        dest=ASSETS/'native-bank-sources';manifest=[]
        for name in FILES:
            raw=urllib.request.urlopen(f'https://raw.githubusercontent.com/Tonejs/Tone.js/{SHA}/{name}',timeout=30).read()
            path=dest/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
            manifest.append(dict(path=name,url=BASE+name,sha256=hashlib.sha256(raw).hexdigest()))
        (dest/'SOURCE.json').write_text(json.dumps(dict(repository='https://github.com/Tonejs/Tone.js',commit=SHA,license='MIT',files=manifest),indent=2),encoding='utf-8')
    (ASSETS/'native-presets.json').write_text(json.dumps(build(),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Generated20 native presets:6 AM,6 PM,8 Drum')
