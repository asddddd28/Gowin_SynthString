"""Summarize actual logs and hashes; never infers hardware success from simulation."""
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from system_model import ROOT,ENGINE


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def record():
    tests={}
    paths=[ROOT/f'reports/final-{name}-xsim.log' for name in ('synth_system','synth_master','compact_delay')]
    paths += [ENGINE/f'reports/fx-final-{name}-xsim.log' for name in ('fx_delay','fx_reverb','axi_fx','axi_voice_endpoint','axi_synth_engine','axi_lfo')]
    paths += [ENGINE/f'reports/system-context-{name}-xsim.log' for name in ('voice_engine','voice_presets','lfo_engine')]
    for path in paths:
        content=path.read_text(encoding='utf-8',errors='replace')
        passed=[line for line in content.splitlines() if line.startswith('PASS ')]
        if not passed or re.search(r'Fatal:|FATAL|ERROR:',content):raise RuntimeError(f'failed simulator log: {path}')
        tests[path.stem]=dict(status='passed',log=str(path),sha256=sha(path),evidence=passed)
    host=subprocess.run([sys.executable,'model/check_host.py'],cwd=ROOT,text=True,capture_output=True,check=True)
    (ROOT/'reports/host-check.log').write_text(host.stdout,encoding='utf-8')
    tests['host']=dict(status='passed',evidence=host.stdout.strip())
    gate_path=ROOT/'reports/system-gate.json'
    gate=json.loads(gate_path.read_text(encoding='utf-8'))
    summary={key:gate[key] for key in ('delivery_ready','errors','strict_warnings','checks')}
    summary['raw_sha256']=sha(gate_path)
    (ROOT/'reports/gate-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    manifest={path:sha(Path(path)) for path in (ROOT/'sources.f').read_text(encoding='utf-8').splitlines()}
    audited=json.loads((ROOT/'reports/source-manifest.json').read_text(encoding='utf-8'))
    if manifest!=audited:raise RuntimeError('RTL changed after strict gate snapshot; rerun publish_specs and gate')
    assets={str(p.relative_to(ROOT)):sha(p) for p in [ROOT/'system.cst',ROOT/'system.sdc',ROOT/'build.tcl',*sorted((ROOT/'rom').glob('*.hex'))]}
    oracle_path=ENGINE/'reports/fx-axi-oracle.json'
    oracle=json.loads(oracle_path.read_text(encoding='utf-8'))
    if oracle['status']!='passed':raise RuntimeError('Audio oracle did not pass')
    oracle.update(source=str(oracle_path),sha256=sha(oracle_path))
    report=dict(recorded=datetime.datetime.now().astimezone().isoformat(),top='SynthSystemTop',tests=tests,
        source_sha256=manifest,assets_sha256=assets,strict_gate=summary,
        numerical_oracle=oracle,
        sample_budget=dict(clock_hz=50000000,frame_cycles=1024,voice_cycles=898,fx_cycles=71,total_cycles=971,remaining_cycles=53),
        hardware=dict(programmed_this_run=False,physical_audio_verified_this_run=False,old_board_sources_unchanged=True),
        limitations=['UART protocol5 is not wired to the existing App','One shared AXI slave mailbox, not independent DSP slave windows','Fixed six-operator resident descriptors, not general instruction PC/DMA','Full FPGA implementation and strict style gates are separate requirements'])
    build=(ROOT/'reports/build.log').read_text(encoding='utf-8',errors='replace')
    report['build_log']=dict(path='reports/build.log',sha256=sha(ROOT/'reports/build.log'),errors=re.findall(r'^.*ERROR.*$',build,re.M),warnings=re.findall(r'^.*WARN.*$',build,re.M))
    watchdog=ROOT/'reports/build-watchdog.json'
    if watchdog.exists():report['implementation']=json.loads(watchdog.read_text(encoding='utf-8-sig'))
    synth_path=ROOT/'impl/gwsynthesis/synth_system_syn.rpt.html'
    synth=synth_path.read_text(encoding='utf-8',errors='replace')
    table=synth.split('name="utilization"',1)[1].split('name="performance"',1)[0]
    cells=[re.sub('<[^>]+>','',x).replace('&nbsp','').strip() for x in re.findall(r'<td[^>]*>(.*?)</td>',table,re.S)]
    report['synthesis']=dict(report=str(synth_path),sha256=sha(synth_path),resource_table=cells,
        timing_scope='Pre-route estimation uses synthesis default100MHz; final50MHz routed timing is separate')
    (ROOT/'reports/system-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Recorded simulator suites',len(paths),'strict gate',summary['delivery_ready'],'hardware not programmed')


if __name__=='__main__':record()
