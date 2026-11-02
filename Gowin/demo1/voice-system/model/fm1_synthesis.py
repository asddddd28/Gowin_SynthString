"""Isolated synthesis only; never replaces routed artifacts or programs hardware."""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'reports/gowin-fm1'
out.mkdir(exist_ok=True)
(out/'rom').mkdir(exist_ok=True)
for source in (ROOT/'rom').glob('*.hex'):shutil.copyfile(source,out/'rom'/source.name)
for name in ('key_thresholds.hex','raw_rest.hex','raw_bottom.hex'):shutil.copyfile(ROOT/name,out/name)
project=out/'synth_fm1.gprj'
project.write_text((ROOT/'synth_system.gprj').read_text(encoding='utf-8'),encoding='utf-8')
(out/'synth.tcl').write_text(f'open_project {{{project.as_posix()}}}\nset_option -top_module SynthSystemTop\nset_option -verilog_std v2001\nset_option -use_cpu_as_gpio 1\nrun syn\nexit\n',encoding='utf-8')
print(out)
