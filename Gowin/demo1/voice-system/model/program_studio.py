"""Program only the frozen, simulated, timing-clean Studio SRAM candidate."""
from pathlib import Path
import hashlib,json,subprocess,datetime
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/unified-studio'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
timing=json.loads((OUT/'timing.json').read_text(encoding='utf-8'))
assert timing['clean'] and not timing['timing']['violations']
assert timing['timing']['fmax'][0]['actualMhz']>=50
inputs=json.loads((OUT/'inputs.json').read_text())
for entry in inputs:
    p=Path(entry['path']);assert sha(p)==entry['sha256'],p
    frozen=OUT/'build/snapshot'/p.relative_to(ROOT.parents[1]) if p.suffix=='.v' else OUT/'build'/p.relative_to(ROOT)
    assert sha(frozen)==entry['sha256'],frozen
for name,match in [('simulate.log','PASS synth_system'),('studio-simulate.log','PASS studio_system')]:
    log=(OUT/name).read_text(encoding='utf-8');assert match in log and 'Fatal:' not in log
log=(OUT/'build/run.log').read_text(encoding='utf-8');assert 'Bitstream generation completed' in log and 'ERROR ' not in log
fs=OUT/'build/impl/pnr/synth_studio.fs'
evidence=dict(time=datetime.datetime.now().astimezone().isoformat(),bitstream=str(fs),sha256=sha(fs),mode='SRAM',port='COM4',timing=timing['timing'],resources=timing['resources'],checked_inputs=len(inputs),programmed=False)
(OUT/'preflash.json').write_text(json.dumps(evidence,indent=2),encoding='utf-8')
import serial
guard=serial.Serial(port=None,baudrate=115200,timeout=.02);guard.dtr=False;guard.rts=False;guard.port='COM4';guard.open()
try:
    r=subprocess.run(['C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe','--device','GW5AT-60B','--cable-index','4','--run','2','--frequency','15MHz','--fsFile',str(fs)],capture_output=True,text=True,errors='replace',timeout=90)
finally:guard.close()
log=r.stdout+r.stderr;(OUT/'program.log').write_text(log,encoding='utf-8')
assert r.returncode==0 and 'Finished.' in log,log
evidence['programmed']=True;(OUT/'programmed.json').write_text(json.dumps(evidence,indent=2),encoding='utf-8')
print('PASS SRAM programmed',evidence['sha256']);print(log[-900:])
