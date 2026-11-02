"""Isolated Gowin synthesis setup for the complete bounded AXI endpoint closure."""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'reports/gowin-fx'
out.mkdir(exist_ok=True)
(out/'rom').mkdir(exist_ok=True)
shutil.copyfile(ROOT/'rom/sine_q26.hex',out/'rom/sine_q26.hex')
for source in (ROOT/'rom').glob('dx_*.hex'):shutil.copyfile(source,out/'rom'/source.name)
files=[line for line in (ROOT/'sources.f').read_text(encoding='utf-8').splitlines() if line]
project='''<?xml version="1.0" encoding="UTF-8"?>
<Project><Template>FPGA</Template><Version>5</Version>
<Device name="GW5AT-60B" pn="GW5AT-LV60PG484AC1/I0">gw5at60b-002</Device><FileList>
'''+''.join(f'<File path="{(ROOT/f).as_posix()}" type="file.verilog" enable="1"/>\n' for f in files)+'</FileList></Project>\n'
(out/'synth_fx.gprj').write_text(project,encoding='utf-8')
(out/'synth.tcl').write_text(f'open_project {{{(out/"synth_fx.gprj").as_posix()}}}\nset_option -top_module AxiSynthEndpoint\nset_option -verilog_std v2001\nrun syn\nexit\n',encoding='utf-8')
print(out)
