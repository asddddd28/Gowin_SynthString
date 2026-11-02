"""Export the exact qualified bank/FX commands and editable DX values for Tauri."""
import hashlib
import json
from pathlib import Path
from dx7_bank import ROOT, INITIAL, FACTORY_SHA, unpack_voice, convert, catalog
from compile_voice_patch import compile_patch
from compile_fx import compile_fx

data=(ROOT/'assets/fm1/factory.vmem').read_bytes()
assert hashlib.sha256(data).hexdigest()==FACTORY_SHA
voices=[data[i:i+128] for i in range(0,len(data),128)]
presets=[]
for slot,program in enumerate(INITIAL):
    raw=unpack_voice(voices[program]);patch=convert(voices[program],program)
    operators=[dict(output=o['output'],rates=o['rates'],levels=o['levels'],ratio=p.get('ratio'),fixed_hz=p.get('fixed_hz'))
        for o,p in zip(raw['operators'],patch['operators'])]
    presets.append(dict(program=program,name=raw['name'],algorithm=raw['algorithm']+1,
        operators=operators,commands=compile_patch(patch,slot=slot)['commands']))
entries=[{k:e[k] for k in ('program','name','algorithm','status','blocked_by')}
    for e in catalog(voices,'FM1 factory')['entries']]
room=json.loads((ROOT/'examples/fx_room.json').read_text(encoding='utf-8'))
dry=json.loads(json.dumps(room));dry['delay']['enabled']=False;dry['reverb']['enabled']=False
result=dict(presets=presets,library=entries,room=compile_fx(room)['commands'],dry=compile_fx(dry)['commands'])
out=ROOT.parents[1]/'demo_test/desktop-tauri/src-tauri/assets/fm1-library.json'
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Exported four resident presets and 128 library entries:',out)
