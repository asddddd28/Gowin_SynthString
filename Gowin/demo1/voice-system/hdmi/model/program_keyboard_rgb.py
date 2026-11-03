"""Program only a timing-clean, source-matched RGB candidate to SRAM."""
from pathlib import Path
import datetime
import hashlib
import json
import subprocess
import serial

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'reports/keyboard-rgb'
summary=json.loads((OUT/'final-timing.json').read_text(encoding='utf-8'))
build=Path(summary['build']['implDir']).parent
assert build.name.startswith('build-keyboard-rgb-')
assert summary['clean'] and not summary['timing']['violations']
assert all(not c['failing'] for c in summary['timing']['fmax'])
assert 'Bitstream generation completed' in (build/'run.log').read_text(encoding='utf-8')
for entry in json.loads((build/'inputs.json').read_text(encoding='utf-8')):
    assert hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest()==entry['sha256'],entry['path']
for name,marker in [('rgb-test-opt.log','PASS keyboard RGB:'),('rgb-effects-opt.log','PASS: four effects'),
                    ('voice-sim/smoothing.log','PASS smoothing:'),('voice-sim/studio.log','PASS studio_system'),
                    ('voice-sim/schedule-current.log','PASS prefetch_ownership')]:
    log=(OUT/name).read_text(encoding='utf-8')
    assert marker in log and 'Fatal:' not in log and 'ERROR:' not in log,name
before=json.loads((OUT/'board/session-COM4.json').read_text(encoding='utf-8'))
assert not before['pending'] and not before.get('wave')
assert (OUT/'board/sequence-before.json').exists()
fs=build/'impl/pnr/synth_hdmi.fs'
record=dict(timestamp=datetime.datetime.now().astimezone().isoformat(),bitstream=str(fs),
    sha256=hashlib.sha256(fs.read_bytes()).hexdigest(),mode='SRAM',programmed=False)
path=OUT/'board/programmed.json'
path.write_text(json.dumps(record,indent=2),encoding='utf-8')
guard=serial.Serial(port=None,baudrate=115200,timeout=.02)
guard.dtr=False;guard.rts=False;guard.port='COM4';guard.open()
try:
    result=subprocess.run(['C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe',
        '--device','GW5AT-60B','--cable-index','4','--run','2','--frequency','15MHz','--fsFile',str(fs)],
        capture_output=True,text=True,errors='replace',timeout=90)
finally:
    guard.close()
log=result.stdout+result.stderr
(OUT/'board/program.log').write_text(log,encoding='utf-8')
assert result.returncode==0 and 'Finished.' in log,log
record['programmed']=True;path.write_text(json.dumps(record,indent=2),encoding='utf-8')
print('PASS SRAM programmed',record['sha256'],flush=True)
print(log[-1000:])
