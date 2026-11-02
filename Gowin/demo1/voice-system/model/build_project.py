"""Generate an isolated pin-constrained board project; never programs hardware."""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[1]
sources=(ROOT/'sources.f').read_text(encoding='utf-8').splitlines()
shutil.copyfile(ROOT.parent/'keyboard-studio/src/keyboard_axis.cst',ROOT/'system.cst')
(ROOT/'system.sdc').write_text('create_clock -name sys_clk -period 20.000 [get_ports {i_clk}]\n',encoding='utf-8')
files=''.join(f'<File path="{path}" type="file.verilog" enable="1"/>\n' for path in sources)
files+=''.join(f'<File path="{(ROOT/name).as_posix()}" type="file.{kind}" enable="1"/>\n' for name,kind in [('system.cst','cst'),('system.sdc','sdc')])
(ROOT/'synth_system.gprj').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Project><Template>FPGA</Template><Version>5</Version>\n<Device name="GW5AT-60B" pn="GW5AT-LV60PG484AC1/I0">gw5at60b-002</Device>\n<FileList>\n'+files+'</FileList></Project>\n',encoding='utf-8')
(ROOT/'build.tcl').write_text(f'open_project {{{(ROOT/"synth_system.gprj").as_posix()}}}\nset_option -top_module SynthSystemTop\nset_option -verilog_std v2001\nset_option -use_cpu_as_gpio 1\nrun all\nexit\n',encoding='utf-8')
print(ROOT/'synth_system.gprj')
