"""Freeze a self-contained 50 MHz candidate. Does not flash hardware."""
from pathlib import Path
import shutil, hashlib, json
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT.parents[1]
OUT=ROOT/'reports/unified-studio/build'
OUT.mkdir(parents=True,exist_ok=True)
entries=[]; files=[]
for name in (ROOT/'sources.f').read_text().splitlines():
    source=Path(name); destination=OUT/'snapshot'/source.relative_to(WORK)
    destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,destination)
    entries.append({'path':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
    files.append(f'<File path="{destination.as_posix()}" type="file.verilog" enable="1"/>')
for name in ('system.cst','system.sdc'):
    shutil.copyfile(ROOT/name,OUT/name)
    files.append(f'<File path="{(OUT/name).as_posix()}" type="file.{Path(name).suffix[1:]}" enable="1"/>')
for source in [*(ROOT/'rom').glob('*.hex'),*[ROOT/n for n in ('key_thresholds.hex','raw_rest.hex','raw_bottom.hex')]]:
    dest=OUT/source.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,dest)
    entries.append({'path':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
project=OUT/'synth_studio.gprj'
project.write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Project><Template>FPGA</Template><Version>5</Version>\n<Device name="GW5AT-60B" pn="GW5AT-LV60PG484AC1/I0">gw5at60b-002</Device>\n<FileList>\n'+'\n'.join(files)+'\n</FileList></Project>\n')
(OUT/'build.tcl').write_text(f'open_project {{{project.as_posix()}}}\nset_option -top_module SynthSystemTop\nset_option -verilog_std v2001\nset_option -use_cpu_as_gpio 1\nset_option -global_freq 50\nset_option -convert_sdp32_36_to_sdp16_18 1\nrun all\nexit\n')
(OUT.parent/'inputs.json').write_text(json.dumps(entries,indent=2))
print(project)
