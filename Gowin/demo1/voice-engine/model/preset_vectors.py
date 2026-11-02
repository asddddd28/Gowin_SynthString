"""Exercise the actual offline patch compiler against the independent renderer."""
import json
from pathlib import Path
from compile_voice_patch import compile_patch, RATE
from voice_engine_model import VoiceModel, packet, UNITY

ROOT=Path(__file__).resolve().parents[1]
NAMES=['FM_Keys','Round_Bass','Soft_Pad','Noise_Drum','Chord_Pad']

def generate():
    commands=[]; pcm=[]; seq=0
    for preset_index,name in enumerate(NAMES):
        patch=json.loads((ROOT/f'examples/{name}.json').read_text(encoding='utf-8'))
        patch['revision']=preset_index+1
        compiled=compile_patch(patch,epoch=77,sequence=seq)
        seq=compiled['next_sequence']
        rows=[]
        for op in range(6):
            rows.append((compiled['commands'][1+op*2]['words'][:6],compiled['commands'][2+op*2]['words'][:8]))
        for c in compiled['commands']:
            commands.append(f"{c['opcode']:02x} {c['address']:02x} {c['sequence']:08x} {packet(*c['words']):080x}")
        model=VoiceModel(rows)
        notes=[60,64,67] if name=='Chord_Pad' else [48] if name=='Round_Bass' else [60]
        for v,note in enumerate(notes):
            inc=round(440*2**((note-69)/12)*(1<<32)/RATE)
            model.on(100+v,inc,UNITY,UNITY//2)
        for frame in range(2048):
            if frame==1024:
                for v in range(len(notes)): model.off(100+v)
            l,r=model.frame();pcm.append(f'{packet(l,r):016x}')
    (ROOT/'vectors/preset_programs.txt').write_text('\n'.join(commands)+'\n',encoding='ascii')
    (ROOT/'vectors/preset_pcm.txt').write_text('\n'.join(pcm)+'\n',encoding='ascii')
    print(f'Five compiled presets: {len(commands)} program commands, {len(pcm)} PCM reference frames')

if __name__=='__main__': generate()
