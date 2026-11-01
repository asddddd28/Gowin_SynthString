"""Only program the simulated, timing-clean Studio image to SRAM."""
from pathlib import Path
import datetime,hashlib,json,subprocess

ROOT=Path(__file__).resolve().parent
report=json.loads((ROOT/'reports/simulation.json').read_text())
assert report['passed']
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in report['source_sha256'].items()),'RTL differs from passing integration simulation'
assert json.loads((ROOT/'reports/gowin_summary.json').read_text())['clean']
for name,phrase in [('studio_control_xsim.log','PASS Studio control:'),('studio_mixer_xsim.log','PASS Studio mixer')]:
    assert phrase in (ROOT/'reports'/name).read_text()
fs=ROOT/'impl/pnr/keyboard_axis.fs'
assert fs.stat().st_mtime>=max(Path(p).stat().st_mtime for p in report['source_sha256'] if '/sim/' not in p)
sha=hashlib.sha256(fs.read_bytes()).hexdigest()
evidence={'time':datetime.datetime.now().isoformat(),'bitstream':str(fs),'sha256':sha,
          'source_match':True,'timing_clean':True,'mode':'SRAM only; no full readback verification'}
(ROOT/'reports/preflash.json').write_text(json.dumps(evidence,indent=2))
with (ROOT/'reports/program.log').open('w') as out:
    result=subprocess.run(['C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe',
        '--device','GW5AT-60B','--cable-index','4','--run','2','--frequency','15MHz','--fsFile',str(fs)],
        stdout=out,stderr=subprocess.STDOUT,timeout=90)
log=(ROOT/'reports/program.log').read_text()
print(log[-1500:])
assert result.returncode==0 and 'Finished.' in log
print('PASS Studio SRAM download',sha)
