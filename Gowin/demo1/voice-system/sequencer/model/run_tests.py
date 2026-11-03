"""隔离的本地 xsim 回归；Fatal 即失败，不能依赖 xsim 进程返回码。"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'reports/sequencer'
TOOLS = Path('D:/Xilinx/2025.1/Vivado/bin')


def run(top, sources, work_name):
    work = OUT/work_name
    work.mkdir(parents=True, exist_ok=True)
    (work/'sources.prj').write_text('\n'.join(f'verilog work "{p.as_posix()}"' for p in sources), encoding='utf-8')
    (work/'run.tcl').write_text('run all\nquit\n', encoding='utf-8')
    log_path = OUT/f'{top}.log'
    with log_path.open('w', encoding='utf-8') as log:
        for tool, args in [('xvlog',['-i',str(ROOT.parents[1]/'demo_test/diagnostics/touchpad/vendor'),'-prj','sources.prj']),
                           ('xelab',[top,'-s',top+'_sim']),('xsim',[top+'_sim','-tclbatch','run.tcl'])]:
            subprocess.run([str(TOOLS/(tool+'.bat')),*args],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=240,check=True)
    text=log_path.read_text(encoding='utf-8',errors='replace')
    assert 'PASS' in text and 'Fatal:' not in text and 'ERROR:' not in text, text[-2200:]
    print('PASS',top,flush=True)


if __name__ == '__main__':
    base = [ROOT/'sequencer/rtl/SynthSequencer.v', ROOT.parents[1]/'demo_test/diagnostics/tactile_buttons/src/TactileInput.v']
    run('tb_sequencer', base+[ROOT/'sequencer/sim/tb_sequencer.v'], 'unit')
