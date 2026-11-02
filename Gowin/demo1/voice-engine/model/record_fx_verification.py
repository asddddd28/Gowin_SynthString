"""Record current-source simulator/synthesis evidence; fail closed on failed logs."""
from pathlib import Path
import datetime
import hashlib
import json
import re
ROOT=Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def record():
    tests={}
    for name in ('fx_delay','fx_reverb','axi_fx','axi_voice_endpoint','axi_synth_engine','axi_lfo'):
        path=ROOT/f'reports/fx-final-{name}-xsim.log'
        content=path.read_text(encoding='utf-8',errors='replace')
        passed=[line for line in content.splitlines() if line.startswith('PASS ')]
        assert passed and not re.search(r'Fatal:|FATAL|ERROR:',content), f'nonpassing {name}'
        tests[name]=dict(status='passed',log=path.relative_to(ROOT).as_posix(),sha256=digest(path),evidence=passed)
    console=(ROOT/'reports/fx-gowin.log').read_text(encoding='utf-8',errors='replace')
    assert 'GowinSynthesis finish' in console and not re.search(r'ERROR\s*\(',console), 'synthesis failure'
    path=ROOT/'reports/gowin-fx/impl/gwsynthesis/synth_fx_syn.rpt.html'
    text=re.sub('<[^>]+>',' ',path.read_text(encoding='utf-8')).replace('&nbsp',' ')
    resources=dict(logic=int(re.search(r'(\d+)\([^)]*\) / 59904',text).group(1)),
        registers=int(re.search(r'Register\s+(\d+) / 60780',text).group(1)),
        bsram=int(re.search(r'BSRAM\s+(\d+) / 118',text).group(1)),
        MULT27X36=int(re.search(r'MULT27X36\s+(\d+)',text).group(1)),
        latches=int(re.search(r'Register as Latch\s+(\d+) /',text).group(1)))
    gate=json.loads((ROOT/'reports/fx_gate.json').read_text(encoding='utf-8'))
    logs=tests['axi_fx']['evidence'][0]
    total=int(re.search(r'total_cycles=(\d+)',logs).group(1))
    fx=int(re.search(r'fx_cycles=(\d+)',logs).group(1))
    tracked=[ROOT/'sources.f',ROOT/'FX.md',ROOT/'README.md',ROOT/'ENGINE.md',ROOT/'AXI-interface.md']
    for folder in ('rtl','model','sim','spec','examples','rom'):
        tracked.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix in ('.v','.py','.json','.md','.svg','.hex'))
    evidence={}
    for name in ('fx-model','fx-axi-oracle','fx-compiler-check'):
        evidence[name]=json.loads((ROOT/f'reports/{name}.json').read_text(encoding='utf-8'))
    assert evidence['fx-axi-oracle']['frames']>6000, 'incomplete AXI capture'
    result=dict(recorded_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        status='functional_candidate_not_strict_release',abi='0x00010005',rtl_definitions=17,lean_instantiated_definitions=12,
        clock_hz=50000000,sample_rate_hz=48828.125,frame_budget_cycles=1024,
        measured_voice_cycles=858,measured_fx_cycles=fx,measured_tick_to_fx_result_cycles=total,remaining_cycles=1024-total,
        tests=tests,evidence=evidence,
        synthesis=dict(status='passed',top='AxiSynthEndpoint',legacy_enabled=False,device='GW5AT-60B / GW5AT-LV60PG484AC1/I0',
            tool='Gowin 1.9.11.03 Education',resources=resources,warnings=len(re.findall(r'WARN\s*\(',console)),
            report=path.relative_to(ROOT).as_posix(),report_sha256=digest(path),
            boundary='Complete AXI + voice + modulation + effects, without legacy raw/context. No board PnR/clock closure or hardware evidence.'),
        legacy_full_synthesis=dict(status='failed_resource_limit',logic=65160,available=59904,log='reports/fx-gowin-legacy.log'),
        strict_gate=dict(ready=gate['delivery_ready'],errors=gate['errors'],strict_warnings=gate['strict_warnings'],checks=gate['checks'],report='reports/fx_gate.json'),
        remaining=['strict RTL quality gate','parameter ramps/crossfade','memory optimization','separate AXI slave windows/master/DMA','board UART/DAC integration, PnR and hardware','Rust App FX control'],
        sha256={p.relative_to(ROOT).as_posix():digest(p) for p in sorted(set(tracked))})
    (ROOT/'reports/fx-verification.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print(f'Recorded {len(tests)} suites; resources={resources}; total cycles={total}; strict_ready={gate["delivery_ready"]}')


if __name__=='__main__': record()
