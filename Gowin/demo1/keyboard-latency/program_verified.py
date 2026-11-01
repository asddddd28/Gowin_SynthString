"""Validate the exact tested inputs and timing before an SRAM-only download."""
from pathlib import Path
import argparse,datetime,hashlib,json,subprocess
import serial

ROOT=Path(__file__).resolve().parent
PROGRAMMER='C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe'
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--program',action='store_true');parser.add_argument('--port',default='COM4');args=parser.parse_args()
    reports={name:json.loads((ROOT/'reports'/f'{name}.json').read_text()) for name in ('latency_supervisor','latency_keyboard_audio')}
    for name,report in reports.items():
        assert report['passed'],name
        assert all(sha(p)==h for p,h in report['source_sha256'].items()),'Tested RTL changed: '+name
    baseline=json.loads((ROOT/'reports/baseline_hashes.json').read_text())
    assert all(sha(p)==h for p,h in baseline.items()),'Shared parallel/studio RTL changed'
    timing=json.loads((ROOT/'reports/gowin_summary.json').read_text())
    assert timing['clean'] and not timing['timing']['violations'],'Timing failed'
    assert timing['timing']['fmax'] and all(c['constraintMhz']==50 and not c['failing'] for c in timing['timing']['fmax'])
    build=(ROOT/'reports/build.log').read_text(encoding='utf-8',errors='replace')
    assert 'Bitstream generation completed' in build
    assert 'EX3988' not in build and 'ERROR ' not in build,'Synthesis failed or missing ROM'
    fs=ROOT/'impl/pnr/keyboard_latency.fs'
    sources=json.loads((ROOT/'sources.json').read_text())
    assets=[ROOT/'rtl/synth/sine.mem',ROOT/'note_profiles.hex',ROOT/'key_thresholds.hex',ROOT/'keyboard_latency.gprj',ROOT/'build.tcl',
            ROOT.parent/'keyboard-studio/src/keyboard_axis.cst',ROOT.parent/'keyboard-studio/src/keyboard_axis.sdc',ROOT.parent/'constraints/surge_svf_sample.gsc']
    for local in assets[:3]:
        assert sha(local)==sha(ROOT.parent/'keyboard-parallel'/local.relative_to(ROOT)),str(local)
    assert fs.stat().st_mtime>=max(Path(p).stat().st_mtime for p in [*sources,*assets]),'Bitstream predates input'
    evidence=dict(time=datetime.datetime.now().isoformat(),bitstream=str(fs),sha256=sha(fs),mode='SRAM only; no full readback verification',
        source_match=True,baseline_unchanged=True,timing_clean=True,
        rtl_sha256={p:sha(p) for p in sources},asset_sha256={str(p):sha(p) for p in assets},tests={k:v['summary'] for k,v in reports.items()})
    (ROOT/'reports/preflash.json').write_text(json.dumps(evidence,indent=2),encoding='utf-8')
    print('PASS preflash inputs, simulation and timing',evidence['sha256'],flush=True)
    if not args.program:return
    guard=serial.Serial(port=None,baudrate=115200,timeout=.02)
    guard.dtr=False;guard.rts=False;guard.port=args.port
    try:guard.open()
    except serial.SerialException as error:raise SystemExit(f'{args.port} is unavailable; no firmware changed: {error}')
    try:
        with (ROOT/'reports/program.log').open('w',encoding='utf-8') as out:
            run=subprocess.run([PROGRAMMER,'--device','GW5AT-60B','--cable-index','4','--run','2','--frequency','15MHz','--fsFile',str(fs)],
                stdout=out,stderr=subprocess.STDOUT,timeout=90)
    finally:guard.close()
    log=(ROOT/'reports/program.log').read_text(encoding='utf-8',errors='replace')
    assert run.returncode==0 and 'Finished.' in log,log[-1600:]
    print(log[-350:],flush=True)
    print('PASS latency supervisor SRAM download',evidence['sha256'],flush=True)

if __name__=='__main__':main()
