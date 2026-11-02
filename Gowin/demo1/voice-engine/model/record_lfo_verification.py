"""汇总真实LFO仿真、综合、接口和严格门禁证据，不代替执行检查。"""
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
    names=['lfo_step','lfo_engine','axi_lfo','voice_engine','axi_synth_engine','axi_voice_endpoint','fm_operator','voice_presets','voice_context','voice_fabric','voice_operators']
    for name in names:
        prefix='lfo-final-' if name in names[:3] else 'lfo-reg-'
        path=ROOT/'reports'/f'{prefix}{name}-xsim.log'
        content=path.read_text(encoding='utf-8',errors='replace')
        passed=[line for line in content.splitlines() if line.startswith('PASS ')]
        if not passed or re.search(r'Fatal:|FATAL|ERROR:',content): raise ValueError(f'nonpassing log: {path}')
        tests[name]={'status':'passed','log':path.relative_to(ROOT).as_posix(),'sha256':digest(path),'evidence':passed}
    console=(ROOT/'reports/lfo-gowin-console.log').read_text(encoding='utf-8',errors='replace')
    if 'GowinSynthesis finish' not in console or re.search(r'ERROR\s*\(',console): raise ValueError('synthesis incomplete/failed')
    report=ROOT/'reports/gowin-lfo/impl/gwsynthesis/voice_lfo_syn.rpt.html'
    html=report.read_text(encoding='utf-8')
    text=re.sub('<[^>]+>',' ',html).replace('&nbsp',' ')
    resources={
        'logic':int(re.search(r'(\d+)\([^)]*\) / 59904',text).group(1)),
        'register':int(re.search(r'Register\s+(\d+) / 60780',text).group(1)),
        'bsram':int(re.search(r'BSRAM\s+(\d+) / 118',text).group(1)),
        'MULT27X36':int(re.search(r'MULT27X36\s+(\d+)',text).group(1)),
        'latch':int(re.search(r'Register as Latch\s+(\d+) /',text).group(1))}
    gate=json.loads((ROOT/'reports/lfo_gate.json').read_text(encoding='utf-8'))
    paths=[ROOT/'sources.f',ROOT/'lfo-plan.json',ROOT/'MODULATION.md',ROOT/'ENGINE.md',ROOT/'README.md',ROOT/'AXI-interface.md']
    for folder in ('rtl','model','sim','spec','examples','rom'):
        paths.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix in ('.v','.py','.json','.md','.hex','.svg'))
    result={
        'recorded_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'status':'functional_candidate_not_strict_release',
        'abi':'0x00010003','rtl_module_definitions':13,
        'capacity':{'voices':8,'audio_operators_per_voice':6,'lfos_per_patch':2,'routes_per_patch':8,'global_state_slots':8,'voice_state_slots':16,'physical_lfo_pipeline':1,'physical_route_multiplier':1},
        'clock_hz':50000000,'sample_rate_hz':48828.125,'sample_budget_cycles':1024,
        'measured_max_render_cycles':858,'remaining_cycles':166,
        'tests':tests,
        'compiler_check':json.loads((ROOT/'reports/lfo-compiler-check.json').read_text(encoding='utf-8')),
        'interface_check':json.loads((ROOT/'reports/lfo-interface-check.json').read_text(encoding='utf-8')),
        'synthesis':{'status':'passed','tool':'Gowin 1.9.11.03 Education','top':'VoiceSynthEngine','device':'GW5AT-60B / GW5AT-LV60PG484AC1/I0','resources':resources,'warnings':len(re.findall(r'WARN\s*\(',console)),'report':report.relative_to(ROOT).as_posix(),'report_sha256':digest(report),'boundary':'Voice Engine plus Modulation only. No legacy raw/context branch or AXI endpoint. 768 top-level probe signals are internal interfaces; no board PnR or flash.'},
        'strict_gate':{'ready':gate['delivery_ready'],'errors':gate['errors'],'strict_warnings':gate['strict_warnings'],'checks':gate['checks'],'report':'reports/lfo_gate.json'},
        'public_delivery_matrix':{**{k:v['status'] for k,v in gate['checks'].items()},'testbench':'passed','toolchain':'passed'},
        'toolchain_scope':'Eleven xsim suites and isolated Gowin synthesis; no PnR or hardware claim.',
        'remaining':['strict RTL gate','LFO delay/fade EG','MIDI clock phase lock','other modulation sources and filter target','independent modulation slave address window','board control/audio integration and Rust App'],
        'sha256':{p.relative_to(ROOT).as_posix():digest(p) for p in sorted(set(paths))}}
    (ROOT/'reports/lfo-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'Recorded {len(tests)} passing simulator suites; resources={resources}; strict gate ready={gate["delivery_ready"]}')

if __name__=='__main__':record()
