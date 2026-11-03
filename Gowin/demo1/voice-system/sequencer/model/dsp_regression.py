"""Numerical and handshake regressions for the two measured setup-path repairs."""
import shutil
from pathlib import Path
from run_tests import ROOT,OUT,run

engine=ROOT.parent/'voice-engine'
work=OUT/'dsp';work.mkdir(exist_ok=True)
for name in ('rom','vectors'):shutil.copytree(engine/name,work/name,dirs_exist_ok=True)
sources=[engine/Path(s) for s in (engine/'sources.f').read_text().splitlines() if s.strip()]
(work/'reports').mkdir(exist_ok=True)
for top in ('tb_dx_envelope','tb_dx_operator','tb_voice_engine','tb_voice_schedule'):
    extra=[]
    if top=='tb_voice_schedule':
        # The archived stress fixture predates the master-lowpass ABI bump.
        fixture=work/'tb_axi_fx.v'
        fixture.write_text((engine/'sim/tb_axi_fx.v').read_text(encoding='utf-8').replace("check_word(4,32'h00010005,0)","check_word(4,32'h00010006,0)"),encoding='utf-8')
        extra=[fixture]
    run(top,sources+extra+[engine/f'sim/{top}.v'],'dsp')
