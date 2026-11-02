"""Publish registered contracts and retain a complete source closure for audit."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from system_model import ROOT,ENGINE


def publish():
    subprocess.run([sys.executable,'model/contracts.py'],cwd=ROOT,check=True)
    changed=('AxisStereoDelay','AxisFxEngine','AxisSynthSystem','AxiVoiceEndpoint','AxiSynthEndpoint','VoiceSynthEngine','AxisFmOperator','AxisDxEnvelope','VoiceModulation')
    for name in changed:
        path=ENGINE/f'spec/{name}_contract.json'
        contract=json.loads(path.read_text(encoding='utf-8'))
        module=contract['modules'][0]
        text=('Synchronous program and packed163-bit context RAM: state17 waits after operator advance; pipelined modulation gives voice866 / full chain940 of1024. Allocation invalidates context flags; first use zeroes phase/EG/history and seeds noise=context+1; note gate events cannot bypass initialization.' if name=='VoiceSynthEngine' else
              'C_DELAY_ADDR_BITS defaults15 in the library; board top uses13. Depth=2**bits, Q16.16 maximum delay=(depth<<16)-1; capability registers report actual depth. Supported board configurations13/14/15.')
        if name=='VoiceSynthEngine':module['behavior']=[b for b in module['behavior'] if not b.startswith('Synchronous program')]
        if name not in ('AxisFmOperator','AxisDxEnvelope','VoiceModulation') and text not in module['behavior']:module['behavior'].append(text)
        path.write_text(json.dumps(contract,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    env=os.environ.copy()
    env['PYTHONPATH']='C:/Users/asddddd28/.agents/skills/readable-verilog-generator'
    env['PYTHONIOENCODING']='utf-8'
    paths=list((ROOT/'spec').glob('*_contract.json'))+[ENGINE/f'spec/{name}_contract.json' for name in changed]
    for path in paths:
        base=ENGINE if path.parent.parent==ENGINE else ROOT
        with (ROOT/f'reports/{path.stem}-spec.log').open('w',encoding='utf-8') as log:
            # Function-local variables in older modules confuse optional source
            # port extraction; the explicit contracts remain the rendered authority.
            result=subprocess.run([sys.executable,'-m','scripts.python.workflow.cli','write-spec','--spec',str(path),'--out-dir',str(base),'--language','zh'],cwd=base,env=env,stdout=log,stderr=subprocess.STDOUT)
        if result.returncode:raise RuntimeError(f'write-spec failed: {path}')
    modules={}
    for base in (ENGINE,ROOT):
        for path in (base/'spec').glob('*_contract.json'):
            for module in json.loads(path.read_text(encoding='utf-8'))['modules']:
                if not module['name'].startswith('tb_'):modules[module['name']]=module
    (ROOT/'spec/operators.json').write_text(json.dumps(dict(modules=list(modules.values())),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    closure=ROOT/'reports/gate-source';closure.mkdir(exist_ok=True)
    manifest={}
    for source in (ROOT/'sources.f').read_text(encoding='utf-8').splitlines():
        path=Path(source)
        shutil.copyfile(path,closure/path.name)
        manifest[source]=hashlib.sha256(path.read_bytes()).hexdigest()
    (ROOT/'reports/source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    old=json.loads((ROOT/'reports/shared-baseline.json').read_text(encoding='utf-8'))
    changes=[source for source,sha in old.items() if hashlib.sha256(Path(source).read_bytes()).hexdigest()!=sha]
    assert all('/voice-engine/' in source for source in changes),'Old board source was modified'
    (ROOT/'reports/shared-changes.json').write_text(json.dumps(dict(changed=changes,old_board_imports_unchanged=True),indent=2)+'\n',encoding='utf-8')
    print('Published specs',len(paths),'source closure',len(manifest),'intentional shared changes',len(changes))


if __name__=='__main__':publish()
