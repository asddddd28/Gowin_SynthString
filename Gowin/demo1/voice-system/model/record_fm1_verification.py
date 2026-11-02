"""Record current FM1 source/log evidence without claiming routed timing or hardware."""
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from system_model import ROOT, ENGINE


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def log_text(path):
    data=path.read_bytes()
    return data.decode('utf-16' if data[:2] in (b'\xff\xfe',b'\xfe\xff') else 'utf-8-sig',errors='replace')


def record():
    suites={}
    logs=[ENGINE/f'reports/dx-{name}-xsim.log' for name in ('dx_envelope','dx_operator','fm1_engine','fm_operator','voice_engine','voice_presets','lfo_engine')]
    logs += [ENGINE/f'reports/fx-final-{name}-xsim.log' for name in ('fx_delay','fx_reverb','axi_fx','axi_voice_endpoint','axi_synth_engine','axi_lfo')]
    logs += [ROOT/f'reports/final-{name}-xsim.log' for name in ('synth_system','synth_master','compact_delay')]
    for p in logs:
        text=log_text(p)
        evidence=[s for s in text.splitlines() if s.startswith('PASS ')]
        if not evidence or re.search(r'Fatal:|FATAL|ERROR:',text):raise RuntimeError(str(p))
        suites[p.stem]=dict(passed=True,path=str(p),sha256=sha(p),evidence=evidence)
    host=subprocess.run([sys.executable,'model/check_host.py'],cwd=ROOT,capture_output=True,text=True,check=True)
    (ROOT/'reports/fm1-host.log').write_text(host.stdout,encoding='utf-8')
    gate=json.loads((ROOT/'reports/fm1-gate.json').read_text(encoding='utf-8'))
    gate_summary={key:gate[key] for key in ('delivery_ready','errors','strict_warnings','checks')}
    gate_summary['sha256']=sha(ROOT/'reports/fm1-gate.json')
    (ROOT/'reports/fm1-gate-summary.json').write_text(json.dumps(gate_summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    manifest={line:sha(Path(line)) for line in (ROOT/'sources.f').read_text().splitlines()}
    assert manifest==json.loads((ROOT/'reports/source-manifest.json').read_text()),'Source changed after gate snapshot'
    for line,digest in manifest.items():assert sha(ROOT/'reports/fm1-gate-source'/Path(line).name)==digest
    synth=ROOT/'reports/gowin-fm1/impl/gwsynthesis/synth_fm1_syn.rpt.html'
    text=synth.read_text(encoding='utf-8',errors='replace')
    cells=[re.sub('<[^>]+>','',c).replace('&nbsp','').strip() for c in re.findall(r'<td[^>]*>(.*?)</td>',text.split('name="utilization"',1)[1].split('name="performance"',1)[0],re.S)]
    flat=re.sub(r'\s+',' ',re.sub('<[^>]+>',' ',text))
    start=flat.find('Actual Fmax');timing=flat[start:start+450]
    build=(ROOT/'reports/fm1-gowin-synthesis.log').read_text(encoding='utf-8',errors='replace')
    assert 'GowinSynthesis finish' in build and 'ERROR' not in build
    assets=[*sorted((ROOT/'rom').glob('*.hex')),ENGINE/'assets/fm1/factory.vmem',ENGINE/'assets/fm1/library.json']
    software=[ENGINE/f'model/{n}.py' for n in ('dx7_model','dx7_bank','compile_voice_patch','voice_engine_model','dx7_validation')]+[ROOT/'host/control.py']
    report=dict(recorded=datetime.datetime.now().astimezone().isoformat(),
        scope='Four FM1 factory presets; 128 preserved library entries, not 128 qualified playable presets',
        tests=suites,rtl_suites=len(suites),host=host.stdout.strip(),
        arithmetic=json.loads((ENGINE/'reports/fm1-vectors.json').read_text()),
        source_sha256=manifest,software_sha256={str(p):sha(p) for p in software},
        assets_sha256={str(p):sha(p) for p in assets},
        strict_gate=gate_summary,synthesis=dict(passed=True,report=str(synth),sha256=sha(synth),resources=cells,pre_route_timing=timing),
        sample_budget=dict(clock_hz=50000000,sample_rate=50000000/1024,voice_with_lfo_cycles=898,fx_cycles=71,total_cycles=971,frame_cycles=1024),
        audio=json.loads((ENGINE/'reports/fm1-audio/manifest.json').read_text()),
        hardware=dict(programmed=False,physical_audio_verified=False,routed_timing_verified=False),
        limitations=['Not bit-exact FM1/DX7','Only four factory presets qualified in RTL simulation',
            '128 entries are a host library; no SD demand loader or MIDI Program Change cache manager yet',
            'Old App is not connected to UART protocol5; use diagnostic CLI',
            'Synthesis Fmax is below50MHz; final implementation and strict gate remain unresolved'])
    (ROOT/'reports/fm1-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS log recording:',len(suites),'RTL suites; gate ready',gate_summary['delivery_ready'])
    print('Resources',cells)
    print('Timing',timing)


if __name__=='__main__':record()
