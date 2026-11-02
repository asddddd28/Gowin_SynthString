"""从五类音色定义生成可导入键位库和独立参数编码参考。"""
from pathlib import Path
import hashlib,json,math,sys

ROOT=Path(__file__).resolve().parent
APP=ROOT.parents[1]/'demo_test/desktop-tauri'
sys.path.insert(0,str(ROOT.parent/'keyboard-studio'))
from studio_model import RATE

def encode(patch):
    """依据 512 位合同构建参考；正数半值向上与当前 App 约定一致。"""
    def quantize(value):return math.floor(value+.5)
    def step(ms):
        raw=quantize(262143*16384/max(1,ms*RATE/1000));exponent=0
        while raw>2047:raw=(raw+1)//2;exponent+=1
        return raw|(exponent<<11)
    increment=quantize(440*2**((patch['note']-69)/12)*2**32/RATE)
    fields=[(0,quantize(increment*patch['ratio'])),(32,increment),
        (64,quantize(increment*patch['depth']) if patch['mode']=='fm' else 0),
        (171,patch['wave_b']),(174,patch['wave_a']),(177,quantize(patch['morph']/100*65535)),
        (196,quantize(patch['depth']*2**26) if patch['mode'] in ('am','ring') else 0),
        (228,{'am':1,'ring':2}.get(patch['mode'],0)),
        (230,quantize(2*math.sin(math.pi*patch['cutoff']/(2*RATE))*2**28)),
        (262,quantize((2-1.8*patch['resonance']/100)*2**28)),
        (294,0x0051eb85),(326,1<<28),(358,patch['filter']),(361,patch['velocity']),(368,1),
        (481,int(patch['mode']=='mix'))]
    for offset,env in [(96,patch['amp']),(376,patch['modulation'])]:
        fields.extend([(offset,1),(offset+1,step(env['attack'])),(offset+19,step(env['decay'])),
            (offset+37,quantize(env['sustain']/100*262143)),(offset+55,step(env['release']))])
    scale=max(100,patch['gain_a']+patch['gain_b']) if patch['mode']=='mix' else 100
    for name,offset in [('gain_a',449),('gain_b',465)]:
        fields.append((offset,quantize(patch[name]/scale*65535)))
    value=sum(number<<offset for offset,number in fields)
    return value.to_bytes(64,'little').hex()

def main():
    source=APP/'src/data/foundation-library.json'
    library=json.loads(source.read_text(encoding='utf-8'))
    presets={p['id']:p for p in library['presets']}
    assert len(presets)==16 and len(library['demo'])==32
    assert set(p['category'] for p in presets.values())=={'Drum','Bass','Pad','Key','Chord'}
    keys=[{**presets[item['id']]['patch'],'note':item['note']} for item in library['demo']]
    bank=dict(format='tang-axis-studio',version=1,
        description='K01–08 Drum，K09–14 Bass，K15–20 Pad，K21–26 Key，K27–29 C大三和弦，K30–32 C小三和弦；和弦由多个键共同演奏。',keys=keys)
    (ROOT/'banks/FiveFamilies-bank.json').write_text(json.dumps(bank,ensure_ascii=False,indent=2),encoding='utf-8')
    vectors=dict(presets=[dict(id=p['id'],hex=encode(p['patch'])) for p in presets.values()],
        demo=[dict(**item,hex=encode(patch)) for item,patch in zip(library['demo'],keys)])
    target=APP/'tests/data/foundation-profiles.json';target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(vectors,indent=2),encoding='utf-8')
    (ROOT/'reports/library.json').write_text(json.dumps(dict(presets=16,keys=32,
        categories={c:sum(p['category']==c for p in presets.values()) for c in ['Drum','Bass','Pad','Key','Chord']},
        source=str(source),sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        reference_scope='64-byte command payload only; does not prove audio similarity or hardware playback',
        firmware='Existing Studio protocol 3/4; bitstream unchanged'),ensure_ascii=False,indent=2),encoding='utf-8')
    print('Generated 16 preset and 32 demo-key reference payloads')

if __name__=='__main__':main()
