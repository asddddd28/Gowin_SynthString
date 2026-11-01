"""Check test/source identity and timing, then optionally download SRAM only."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
from configure_cores import read_counts

ROOT = Path(__file__).resolve().parent
PROGRAMMER = 'C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe'

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--program', action='store_true')
parser.add_argument('--port', default='COM4', help='Reserve the debug UART before changing board firmware')
args = parser.parse_args()
counts = read_counts()
assert counts == dict(phase=1,wave=2,envelope=3,modulation=1,filter=1,vca=1), 'Only this configuration has a reviewed board implementation'
subprocess.run([__import__('sys').executable,str(ROOT/'configure_cores.py'),'--check'],check=True,cwd=ROOT)
names = ['parallel_equivalence','parallel_cycles','pool_backpressure','parallel_keyboard_audio'] + [f'parallel_cores_{n}' for n in range(1,5)]
for name in names:
    report = json.loads((ROOT/'reports'/f'{name}.json').read_text())
    assert report['passed'], name
    assert all(digest(path)==value for path,value in report['source_sha256'].items()), 'Source changed after '+name
original = json.loads((ROOT/'reports/baseline_hashes.json').read_text())
assert all(digest(path)==value for path,value in original.items()), 'Original project changed'
timing = json.loads((ROOT/'reports/gowin_summary.json').read_text())
assert timing['clean'] and not timing['timing']['violations']
assert all(not clock['failing'] and clock['constraintMhz']==50 for clock in timing['timing']['fmax'])
fs = ROOT/'impl/pnr/keyboard_parallel.fs'
sources = json.loads((ROOT/'sources.json').read_text())
assert fs.stat().st_mtime >= max(Path(path).stat().st_mtime for path in sources), 'Bitstream predates source'
evidence = dict(time=datetime.datetime.now().isoformat(),bitstream=str(fs),sha256=digest(fs),
                mode='SRAM only; no full readback verification',source_match=True,baseline_unchanged=True,
                timing_clean=True,cores=counts,tests=names,
                rtl_sha256={path:digest(path) for path in sources},
                project_sha256={str(p):digest(p) for p in [ROOT/'keyboard_parallel.gprj',ROOT/'build.tcl',ROOT/'core_counts.json']},
                hex_sha256={str(p):digest(p) for p in ROOT.rglob('*.hex') if 'impl' not in p.parts and 'xsim.dir' not in p.parts})
(ROOT/'reports/preflash.json').write_text(json.dumps(evidence,indent=2),encoding='utf-8')
print('PASS preflash sources, original backup, functional tests and timing:',evidence['sha256'],flush=True)
if args.program:
    # Do not replace firmware while another App is using this board. Opening
    # the UART first provides an OS-enforced exclusive reservation, without
    # terminating the other application or toggling DTR/RTS.
    import serial
    guard = serial.Serial(port=None,baudrate=115200,timeout=.02)
    guard.dtr=False; guard.rts=False; guard.port=args.port
    try:
        guard.open()
    except serial.SerialException as error:
        raise SystemExit(f'Board UART {args.port} is unavailable. No firmware was changed: {error}')
    try:
        with (ROOT/'reports/program.log').open('w',encoding='utf-8') as out:
            result = subprocess.run([PROGRAMMER,'--device','GW5AT-60B','--cable-index','4','--run','2',
                    '--frequency','15MHz','--fsFile',str(fs)],stdout=out,stderr=subprocess.STDOUT,timeout=90)
    finally:
        guard.close()
    log = (ROOT/'reports/program.log').read_text(encoding='utf-8',errors='replace')
    print(log[-1800:],flush=True)
    assert result.returncode==0 and 'Finished.' in log
    print('PASS parallel SRAM download',evidence['sha256'],flush=True)
