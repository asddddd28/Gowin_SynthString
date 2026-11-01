"""Run selected local xsim bench, retain logs and source fingerprints."""
from pathlib import Path
import hashlib,json,subprocess,sys,time
ROOT=Path(__file__).resolve().parent;BIN=Path('D:/Xilinx/2025.1/Vivado/bin')
name=sys.argv[1];source_list=ROOT/('sources.json' if (ROOT/'sources.json').exists() else 'baseline_sources.json')
sources=json.loads(source_list.read_text())+[str(ROOT/'sim'/f'tb_{name}.v')]
fingerprints={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in sources}
for tool,args in [('xvlog',sources),('xelab',['work.tb_'+name,'-s',name]),('xsim',[name,'-runall'])]:
    log=ROOT/'reports'/f'{name}_{tool}.log'
    with log.open('w',encoding='utf-8') as output:
        process=subprocess.run(subprocess.list2cmdline([str(BIN/(tool+'.bat')),*args]),shell=True,cwd=ROOT,stdout=output,stderr=subprocess.STDOUT)
    result=log.read_text(encoding='utf-8',errors='replace')
    if process.returncode or 'ERROR:' in result or 'Fatal:' in result:
        print(result[-6000:],flush=True);raise SystemExit(1)
    print(tool+' complete',flush=True)
assert 'PASS' in result
assert fingerprints=={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in sources},'Source changed during test'
summary=[line for line in result.splitlines() if any(word in line for word in ['PASS','STAGE','CYCLES'])]
(ROOT/'reports'/f'{name}.json').write_text(json.dumps({'passed':True,'summary':summary,'source_sha256':fingerprints},indent=2))
print('\n'.join(summary),flush=True)
