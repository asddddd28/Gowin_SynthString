"""运行独立键盘引脚到 DAC 引脚仿真，保留真实工具日志。"""
from pathlib import Path
import hashlib
import json
import os
import subprocess

ROOT=Path(__file__).resolve().parent
BIN=Path('D:/Xilinx/2025.1/Vivado/bin')
sources=json.loads((ROOT/'sources.json').read_text())+[str(ROOT/'sim/tb_keyboard_audio.v')]
source_hashes={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in sources}
calibration=json.loads((ROOT/'calibration.json').read_text(encoding='utf-8'))
for field,name in [('rest','raw_rest.hex'),('bottom','raw_bottom.hex')]:
    (ROOT/name).write_text(''.join(f"{round(k['calibration'][field]):03x}\n" for k in calibration['keys']))

def run(tool,args):
    command=subprocess.list2cmdline([str(BIN/(tool+'.bat')),*args])
    with (ROOT/'reports'/('sim_'+tool+'.log')).open('w',encoding='utf-8') as log:
        result=subprocess.run(command,cwd=ROOT,shell=True,stdout=log,stderr=subprocess.STDOUT)
    text=(ROOT/'reports'/('sim_'+tool+'.log')).read_text(encoding='utf-8',errors='replace')
    if result.returncode or 'FATAL_ERROR' in text or 'ERROR:' in text or 'Fatal:' in text:
        print(text[-5000:],flush=True)
        raise SystemExit('FAILED '+tool)
    print(tool+' completed',flush=True)
    return text

run('xvlog',sources)
run('xelab',['work.tb_keyboard_audio','-debug','typical','-s','keyboard_audio'])
text=run('xsim',['keyboard_audio','-runall'])
assert 'PASS keyboard ADC' in text
assert source_hashes=={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in sources},'Source changed during simulation'
report={'passed':True,'summary':[line for line in text.splitlines() if 'PASS keyboard ADC' in line],
        'source_sha256':source_hashes}
(ROOT/'reports/simulation.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report['summary']),flush=True)
