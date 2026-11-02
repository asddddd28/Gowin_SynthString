"""Freeze source/assets and completed simulator logs for SRAM preflight."""
from pathlib import Path
import hashlib,json,datetime,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
files=[Path(f.attrib['path']) for f in ET.parse(ROOT/'synth_system.gprj').findall('.//File')]
files+=list((ROOT/'rom').glob('*.hex'))+[ROOT/n for n in ['key_thresholds.hex','raw_rest.hex','raw_bottom.hex','synth_system.gprj']]
logs=list((ROOT.parent/'voice-engine/reports').glob('dx-*-xsim.log'))+list((ROOT.parent/'voice-engine/reports').glob('fx-final-*-xsim.log'))+list((ROOT/'reports').glob('final-*-xsim.log'))
results=[]
for p in logs:
    raw=p.read_bytes();text=raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8',errors='replace')
    passed=[line.strip() for line in text.splitlines() if 'PASS ' in line]
    assert 'FATAL' not in text and 'FAIL ' not in text,str(p)
    if passed:results.append(dict(log=str(p),sha256=sha(p),summary=passed))
assert len(results)==16,len(results)
record=dict(time=datetime.datetime.now().isoformat(),source_sha256={str(p):sha(p) for p in files},rtl_suites=results,count=len(results))
(ROOT/'reports/board-tested-inputs.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
print('Recorded',len(results),'passing suites and',len(files),'source/asset hashes')
