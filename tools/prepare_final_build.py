"""Create a portable project from the exact final-release input list; never flash."""
from pathlib import Path
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
release=json.loads((ROOT/'FINAL_RELEASE.json').read_text(encoding='utf-8'))
OUT=ROOT/'build/final-rgb'
for rel,digest in release['source_sha256'].items():
    assert hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()==digest,rel
for info in release['constraints'].values():
    assert hashlib.sha256((ROOT/info['path']).read_bytes()).hexdigest()==info['sha256']
OUT.mkdir(parents=True,exist_ok=True)
project=ET.Element('Project')
ET.SubElement(project,'Template').text='FPGA'
ET.SubElement(project,'Version').text='5'
ET.SubElement(project,'Device',name='GW5AT-60B',pn=release['device']).text='gw5at60b-002'
files=ET.SubElement(project,'FileList')
for rel in release['rtl_sources']:
    ET.SubElement(files,'File',path=(ROOT/rel).as_posix(),type='file.verilog',enable='1')
for name,info in release['constraints'].items():
    shutil.copy2(ROOT/info['path'],OUT/name)
    ET.SubElement(files,'File',path=(OUT/name).as_posix(),type='file.'+Path(name).suffix[1:],enable='1')
for asset in release['assets']:
    dest=OUT/asset['target'];dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/asset['source'],dest)
path=OUT/'synth_hdmi.gprj'
ET.ElementTree(project).write(path,encoding='utf-8',xml_declaration=True)
(OUT/'build.tcl').write_text(f'''open_project {{{path.as_posix()}}}
set_option -top_module SynthHdmiTop
set_option -verilog_std v2001
set_option -use_cpu_as_gpio 1
set_option -global_freq 50
set_option -convert_sdp32_36_to_sdp16_18 1
run all
exit
''',encoding='utf-8')
print(f'Prepared {len(release["rtl_sources"])} RTL files and {len(release["assets"])} ROM/assets: {OUT}')
print('Run gw_sh.exe build.tcl from this directory. Recheck timing on every rebuild.')
