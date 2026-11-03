"""Program the frozen, timing-clean candidate to SRAM; retain rollback evidence."""
from pathlib import Path
import datetime
import hashlib
import json
import subprocess
import sys
import serial

ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT.parent/'reports/synthui-hdmi'
BUILD=REPORT/(sys.argv[1] if len(sys.argv)>1 else 'build-keyboard-precision')
timing=json.loads((REPORT/'timing.json').read_text(encoding='utf-8'))
assert Path(timing['build']['implDir']).resolve()==(BUILD/'impl').resolve(), 'Timing report belongs to a different candidate'
assert timing['clean'] and not timing['timing']['violations']
for c in timing['timing']['fmax']: assert not c['failing']
for entry in json.loads((BUILD/'inputs.json').read_text(encoding='utf-8')):
    assert hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest()==entry['sha256'],entry['path']
for path,marker in [('sim/audio.log','PASS audio:'),('sim/control.log','PASS control:'),('sim/video.log','PASS video:'),('audio-regression.log','PASS studio_system')]:
    text=(REPORT/path).read_text(encoding='utf-8')
    assert marker in text and 'Fatal:' not in text,path
assert 'Bitstream generation completed' in (BUILD/'run.log').read_text(encoding='utf-8')
bitstream=BUILD/'impl/pnr/synth_hdmi.fs'
record={'timestamp':datetime.datetime.now().astimezone().isoformat(),'sha256':hashlib.sha256(bitstream.read_bytes()).hexdigest(),'bitstream':str(bitstream),'mode':'SRAM','programmed':False}
(REPORT/'programmed.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
guard=serial.Serial(port=None,baudrate=115200,timeout=.02)
guard.dtr=False;guard.rts=False;guard.port='COM4';guard.open()
try:
    result=subprocess.run(['C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe','--device','GW5AT-60B','--cable-index','4','--run','2','--frequency','15MHz','--fsFile',str(bitstream)],capture_output=True,text=True,errors='replace',timeout=90)
finally:
    guard.close()
log=result.stdout+result.stderr
(REPORT/'program.log').write_text(log,encoding='utf-8')
assert result.returncode==0 and 'Finished.' in log,log
record['programmed']=True
(REPORT/'programmed.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
print('PASS SRAM programmed',record['sha256'])
print(log[-900:])
