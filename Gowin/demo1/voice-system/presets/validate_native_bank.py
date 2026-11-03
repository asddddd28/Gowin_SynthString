"""Integer audio validation of the full native bank; no hardware mutation."""
from pathlib import Path
import copy,hashlib,json,math,sys,time,wave,array

SYSTEM=Path(__file__).resolve().parents[1]
ENGINE=SYSTEM.parent/'voice-engine'
sys.path.insert(0,str(ENGINE/'model'))
from compile_voice_patch import compile_patch,RATE
from voice_engine_model import VoiceModel,UNITY

OUT=SYSTEM/'reports/native-presets';OUT.mkdir(exist_ok=True)
bank=json.loads((SYSTEM.parent/'desktop-tauri/src-tauri/assets/native-presets.json').read_text(encoding='utf-8'))

def compile_native(patch):
    p=copy.deepcopy(patch)
    for op in p['operators']:
        for name in ['ratio','fixed_hz']:
            if op[name] is None:del op[name]
    return compile_patch(p)

def model_for(commands,note=60,gain=UNITY,voices=1):
    rows=[(commands[1+2*i]['words'][:6],commands[2+2*i]['words'][:8]) for i in range(6)]
    model=VoiceModel(rows)
    for i in range(voices):model.on(i+1,round(440*2**((note+i-69)/12)*(1<<32)/RATE),gain,UNITY//2)
    return model

results=[];oracle=[]
for preset in bank['presets']:
    commands=compile_native(preset['patch'])['commands'];oracle.append(dict(id=preset['id'],commands=[dict(opcode=c['opcode'],address=c['address'],words=c['words'][:(1 if c['opcode']==0xa0 else 6 if c['opcode']==0xa1 else 8 if c['opcode']==0xa2 else 0)]) for c in commands]))
    model=model_for(commands);samples=[]
    hold=int(RATE*(2.0 if preset['percussive'] else 1.1));end=hold+int(RATE*1.0)
    for n in range(end):
        if n==hold:model.off(1)
        samples.append(model.frame()[0])
    peak=max(map(abs,samples))/UNITY;rms=math.sqrt(sum(v*v for v in samples)/len(samples))/UNITY
    assert 0.005<peak<.065,(preset['id'],peak)
    assert max(map(abs,samples[-1024:]))==0,(preset['id'],'release not silent')
    if preset['percussive']:assert max(map(abs,samples[hold-1024:hold]))==0,(preset['id'],'held drum not decayed')
    soft=model_for(commands,gain=UNITY//4);loud=model_for(commands);eight=model_for(commands,voices=8)
    soft_energy=full_energy=0;max_eight=0
    for _ in range(2048):
        soft_energy+=soft.frame()[0]**2;full_energy+=loud.frame()[0]**2
        max_eight=max(max_eight,abs(eight.frame()[0]))
    assert soft_energy<full_energy*.08 and full_energy>0
    assert max_eight<UNITY*.95,(preset['id'],'eight voice saturation')
    # Reference WAV is explicitly an integer-model preview, not a recording.
    pcm=array.array('h',[max(-32768,min(32767,v>>11)) for v in samples[::2]])
    with wave.open(str(OUT/(preset['id']+'-model.wav')),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(round(RATE/2));f.writeframes(pcm.tobytes())
    results.append(dict(id=preset['id'],peak=peak,rms=rms,max_8voices=max_eight/UNITY,
                        soft_full_rms_ratio=math.sqrt(soft_energy/full_energy),held_drum_decay=preset['percussive'],release_silent=True,
                        pcm_sha256=hashlib.sha256(pcm.tobytes()).hexdigest()))
    print('PASS',preset['id'],'peak',round(peak,4),'8voice',round(max_eight/UNITY,4),flush=True)
(OUT/'model.json').write_text(json.dumps(dict(status='PASS',presets=results),indent=2),encoding='utf-8')
(SYSTEM.parent/'desktop-tauri/src-tauri/assets/native-preset-oracle.json').write_text(json.dumps(oracle,indent=2),encoding='utf-8')
print('PASS20 presets:release silence,drum natural decay,velocity response,8voice headroom',flush=True)
