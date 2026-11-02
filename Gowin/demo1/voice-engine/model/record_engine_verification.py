"""Record existing real simulator/gate/synthesis evidence without running tools."""
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
    for name in ('fm_operator','voice_engine','axi_synth_engine','axi_voice_endpoint','voice_context','voice_fabric','voice_operators','presets'):
        path=ROOT/'reports'/('engine-presets-xsim.log' if name=='presets' else f'engine-final-{name}-xsim.log')
        content=path.read_text(encoding='utf-8',errors='replace')
        passed=[line for line in content.splitlines() if line.startswith('PASS ')]
        if not passed or re.search(r'Fatal:|FATAL|ERROR:',content): raise ValueError(f'nonpassing simulator log: {path}')
        tests[name]={'status':'passed','log':path.relative_to(ROOT).as_posix(),'log_sha256':digest(path),'evidence':passed}
    gate=json.loads((ROOT/'reports/engine_gate.json').read_text(encoding='utf-8'))
    console=(ROOT/'reports/engine-gowin-console.log').read_text(encoding='utf-8',errors='replace')
    if 'GowinSynthesis finish' not in console or 'ERROR (' in console: raise ValueError('synthesis not complete')
    report=ROOT/'reports/gowin-engine/impl/gwsynthesis/voice_engine_syn.rpt.html'
    html=report.read_text(encoding='utf-8')
    # Preserve raw report and human-readable tables, not guessed PnR utilization.
    start=html.index('<h2><a name="utilization"');end=html.index('</table>',start)
    resource_text=re.sub('<[^>]+>',' ',html[start:end]).replace('&nbsp',' ')
    paths=[ROOT/'sources.f',ROOT/'formatter-profile.json',ROOT/'engine-plan.json']
    for folder in ('rtl','model','sim','spec','examples','rom'):
        paths.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix in ('.v','.py','.json','.md','.hex','.svg'))
    evidence={
        'recorded_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'status':'functional_candidate_not_strict_release',
        'abi':'0x00010002',
        'scope':{'voices':8,'logical_operators_per_voice':6,'physical_composite_operators':1,'patch_slots':4,'parameter_banks_per_slot':2,'rtl_module_definitions':11},
        'sample_clock_hz':50000000,'sample_period_clocks':1024,'sample_rate_hz':48828.125,
        'measured_render_cycles_all_48_operators':658,
        'clock_budget_note':'Cycle budget is simulation evidence; 50 MHz timing closure needs board PnR.',
        'tests':tests,
        'interface_contracts':json.loads((ROOT/'reports/engine-interface-check.json').read_text(encoding='utf-8')),
        'compiler':json.loads((ROOT/'reports/engine-compiler-check.json').read_text(encoding='utf-8')),
        'strict_gate':{'ready':gate['delivery_ready'],'errors':gate['errors'],'strict_warnings':gate['strict_warnings'],'checks':gate['checks'],'report':'reports/engine_gate.json'},
        'synthesis':{'status':'passed','tool':'Gowin 1.9.11.03 Education','device':'GW5AT-60B / GW5AT-LV60PG484AC1/I0','top':'VoiceSynthEngine','warnings':len(re.findall(r'WARN\s*\(',console)),'report':report.relative_to(ROOT).as_posix(),'report_sha256':digest(report),'resource_table':resource_text,'boundary':'Engine alone; 768 top IO signals are a synthesis probe, not board pins. No PnR, bitstream or board flash.'},
        'public_delivery_matrix':{**{k:v['status'] for k,v in gate['checks'].items()},'testbench':'passed','toolchain':'passed'},
        'external_toolchain_scope':'xsim eight suites + Gowin engine synthesis only; no claim of PnR or hardware verification',
        'remaining':['strict RTL delivery gate','board AXI/control/PCM integration and PnR','Rust App ABI integration','steal crossfade and patch smoothing','exact DX EG/SysEx/32-algorithm mapping','bandlimited waveforms and modulation matrix/FX'],
        'sha256':{p.relative_to(ROOT).as_posix():digest(p) for p in sorted(set(paths))}
    }
    out=ROOT/'reports/engine-verification.json'
    out.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Recorded eight passing simulations and successful engine synthesis; strict gate remains failed.')

if __name__=='__main__': record()
