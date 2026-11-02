"""Program only this tested candidate to SRAM; verify source and timing evidence first."""
from pathlib import Path
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parent
report=json.loads((ROOT/'reports/simulation.json').read_text())
assert report['passed'] and all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==v for p,v in report['source_sha256'].items()),'Current RTL has not passed integration simulation'
summary=json.loads((ROOT/'reports/gowin_summary.json').read_text());assert summary['clean']
assert 'PASS loudness independent reference' in (ROOT/'reports/loudness_xsim.log').read_text()
assert 'PASS mixer arithmetic equivalence' in (ROOT/'reports/mixer_xsim.log').read_text()
fs=ROOT/'impl/pnr/keyboard_axis.fs';sha=hashlib.sha256(fs.read_bytes()).hexdigest()
pre={'bitstream':str(fs),'sha256':sha,'source_match':True,'timing_clean':True,'mode':'SRAM only; no full readback verification'}
(ROOT/'reports/preflash.json').write_text(json.dumps(pre,indent=2))
with (ROOT/'reports/program.log').open('w') as out:
 r=subprocess.run(['C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe','--device','GW5AT-60B','--cable-index','4','--run','2','--frequency','15MHz','--fsFile',str(fs)],stdout=out,stderr=subprocess.STDOUT,timeout=90)
text=(ROOT/'reports/program.log').read_text();print(text[-700:]);assert r.returncode==0 and 'Finished.' in text
print('PASS SRAM download',sha)
