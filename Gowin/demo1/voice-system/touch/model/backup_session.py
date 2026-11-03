from pathlib import Path
import os,shutil,json,hashlib,datetime
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'reports/touch-performance/before-board';OUT.mkdir(exist_ok=True)
source=Path('\\\\?\\'+str(Path(os.environ['LOCALAPPDATA'])/'SynthString/voice-engine/COM4.json'))
dest=OUT/'session-COM4.json'
assert not dest.exists(),'Keep first immutable user-state snapshot'
data=source.read_bytes();session=json.loads(data)
assert session['pending'] is None,'Unconfirmed request must be settled before reset'
dest.write_bytes(data)
for name in ['TangSynthStudio.exe','UNIFIED_STUDIO.md']:shutil.copyfile(ROOT/'app'/name,OUT/name)
bitstream=ROOT/'reports/synthui-hdmi/build-master-lowpass-uart/impl/pnr/synth_hdmi.fs'
shutil.copyfile(bitstream,OUT/'rollback.fs')
manifest={'time':datetime.datetime.now().astimezone().isoformat(),'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir() if p.is_file()},'rollback_source':str(bitstream)}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('Backed up user session, executable and rollback bitstream; volume',session['volume'],'wave',session.get('wave_name'), 'keys',len(session['keys']))
