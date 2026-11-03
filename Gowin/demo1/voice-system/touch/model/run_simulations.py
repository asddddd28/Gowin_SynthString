"""Run bounded local xsim simulations, preserving individual evidence logs."""
from pathlib import Path
import subprocess,shutil,sys
ROOT=Path(__file__).resolve().parents[2]
TOOLS=Path('D:/Xilinx/2025.1/Vivado/bin')
OUT=ROOT/'reports/touch-performance'
def run(work,top,project):
    if len(sys.argv)>1 and top not in sys.argv[1:]:return
    with (OUT/f'{top}.log').open('w',encoding='utf-8') as log:
        for tool,args in [('xvlog',['-i',str(ROOT.parents[1]/'demo_test/diagnostics/touchpad/vendor'),'-prj',str(project)]),('xelab',[top,'-s',top+'_sim']),('xsim',[top+'_sim','-tclbatch','run.tcl'])]:
            result=subprocess.run([str(TOOLS/(tool+'.bat')),*args],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=240)
            if result.returncode:raise RuntimeError(top+' '+tool)
    text=(OUT/f'{top}.log').read_text(encoding='utf-8',errors='replace')
    if 'PASS' not in text or 'Fatal:' in text or 'Error:' in text:raise RuntimeError(top+' failed: '+text[-2000:])
    print('PASS',top,flush=True)
run(ROOT/'reports/synthui-hdmi/sim','tb_display_control',Path('sources.prj'))
run(ROOT/'reports/synthui-hdmi/sim','tb_display_audio',Path('sources.prj'))
run(ROOT/'reports/synthui-hdmi/sim','tb_display_video',Path('sources.prj'))
run(ROOT/'reports/master-lowpass/sim','tb_master_lowpass',Path('sources.prj'))
run(OUT/'sim','tb_touch_position',Path('sources.prj'))
run(OUT/'sim','tb_touch_performance',Path('sources.prj'))
# Studio regression uses the complete wrapper and previous touch-disabled ABI.
work=OUT/'system-sim';work.mkdir(exist_ok=True)
shutil.copytree(ROOT/'rom',work/'rom',dirs_exist_ok=True)
for f in ['key_thresholds.hex','raw_rest.hex','raw_bottom.hex']:shutil.copy(ROOT/f,work/f)
shutil.copytree(ROOT/'sim',work/'sim',dirs_exist_ok=True)
sources=[Path(s) for s in (ROOT/'sources.f').read_text().splitlines() if s.strip()]+[ROOT/'sim/tb_studio_system.v']
(work/'sources.prj').write_text('\n'.join(f'verilog work "{p.as_posix()}"' for p in sources))
(work/'run.tcl').write_text('run all\nquit\n')
run(work,'tb_studio_system',Path('sources.prj'))
shutil.copy(ROOT.parent/'voice-engine/vectors/preset_programs.txt',work/'preset_programs.txt')
sources+=list((ROOT/'touch/sim').glob('tb_touch_*.v'))
(work/'sources.prj').write_text('\n'.join(f'verilog work "{p.as_posix()}"' for p in sources))
run(work,'tb_touch_voice',Path('sources.prj'))
run(work,'tb_touch_filter',Path('sources.prj'))
run(work,'tb_touch_system',Path('sources.prj'))
