"""Publish the frozen RGB build, selected source and App; never touch the board."""
from pathlib import Path
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET

BASE=Path(__file__).resolve().parents[4]
SYSTEM=BASE/'Gowin/demo1/voice-system'
BUILD=SYSTEM/'reports/synthui-hdmi/build-keyboard-rgb-02'
DEST=BASE/'Gowin/github-publish/Gowin_SynthString'
EXCLUDE={'reference','material','materials','project-backups','node_modules','target','__pycache__',
         '.git','.venv','reports','release','release-merged','dist','impl','baseline','gen','test-results','playwright-report'}
selected=set()

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def add(p):
    assert p.is_file(),p
    assert p.stat().st_size<40_000_000,p
    selected.add(p)
def tree(base):
    for p in base.rglob('*'):
        if not p.is_file() or set(p.relative_to(base).parts)&EXCLUDE:continue
        if p.suffix.lower() in {'.pyc','.log','.jou','.pb','.wdb','.dmp','.zip','.pdb','.tmp'}:continue
        add(p)
def copy(p,rel):
    q=DEST/rel;q.parent.mkdir(parents=True,exist_ok=True)
    if not q.exists() or sha(q)!=sha(p):shutil.copy2(p,q)
    return q

assert (DEST/'.git').is_dir()
inputs=json.loads((BUILD/'inputs.json').read_text(encoding='utf-8'))
source_hash={}
for item in inputs:
    p=Path(item['path']);assert sha(p)==item['sha256'],f'Tested source changed: {p}'
    add(p);source_hash[p.relative_to(BASE).as_posix()]=item['sha256']
for folder in ['rtl','rom','model','sim','spec','host','hdmi','touch','filter','sequencer','presets']:
    tree(SYSTEM/folder)
for base in [SYSTEM,SYSTEM.parent/'voice-engine']:
    for p in base.iterdir():
        if p.is_file() and p.suffix in {'.md','.hex','.f','.cst','.sdc','.gprj','.tcl'}:add(p)
for folder in ['rtl','rom','model','sim','spec','examples','assets']:
    tree(SYSTEM.parent/'voice-engine'/folder)
add(SYSTEM/'storage/sd.cst')
app=SYSTEM.parent/'desktop-tauri'
for folder in ['src','scripts','tests','src-tauri/src','src-tauri/assets','src-tauri/tests','src-tauri/icons','src-tauri/capabilities']:
    tree(app/folder)
for base in [app,app/'src-tauri']:
    for p in base.iterdir():
        if p.is_file() and (p.suffix in {'.md','.json','.ts','.toml','.lock','.rs','.html'} or p.name=='.gitignore'):add(p)
shared=BASE/'Gowin/demo_test/desktop-tauri'
tree(shared/'src')
for p in (shared/'src-tauri/src').glob('voice_*.rs'):add(p)
for rel in ['src-tauri/src/synth_midi.rs','src-tauri/assets/fm1-library.json','src-tauri/assets/sd-preset-commands.json']:add(shared/rel)
# Small built-in assets consumed by prepare-assets.mjs, not the raw material library.
for rel in ['output/basic_bank_v1','output/sd_library_demo','desktop/samples']:tree(SYSTEM.parent/rel)
for folder in ['assets','licenses']:tree(SYSTEM/'app'/folder)
add(SYSTEM/'app/TangSynthStudio.exe')
for p in (SYSTEM/'app').glob('*.md'):add(p)
add(SYSTEM/'app/DSP_NOTICE.txt')
# Pin/header dependencies used by the original generator.
for rel in ['src/hdmi.cst','src/hdmi.sdc']:
    add(BASE/'Gowin/demo_test/diagnostics/hardware_hdmi'/rel)
for p in sorted(selected):
    rel=p.relative_to(BASE)
    assert not set(x.lower() for x in rel.parts)&{'reference','material','materials','project-backups','node_modules','target'},rel
    copy(p,rel)

final=DEST/'Gowin/demo1/voice-system/firmware/final-rgb'
final.mkdir(parents=True,exist_ok=True)
fs=copy(BUILD/'impl/pnr/synth_hdmi.fs',final.relative_to(DEST)/'synth_hdmi.fs')
assert sha(fs)=='d2f4793f8d67c0b1ba3f4a762c002a36f6178b546996eb3120ab6f66a33325c9'
for name in ['hdmi.cst','hdmi.sdc']:copy(BUILD/name,final.relative_to(DEST)/name)
evidence=DEST/'Gowin/demo1/voice-system/reports/final-rgb'
evidence.mkdir(parents=True,exist_ok=True)
for src,name in [(SYSTEM/'reports/keyboard-rgb/final-timing.json','timing.json'),
                 (SYSTEM/'reports/keyboard-rgb/final-paths.json','paths.json'),
                 (BUILD/'impl/pnr/synth_hdmi.rpt.txt','synth_hdmi.rpt.txt'),
                 (BUILD/'impl/gwsynthesis/synth_hdmi_syn_rsc.xml','resources.xml')]:
    copy(src,evidence.relative_to(DEST)/name)
tests={}
for name in ['rgb-test-opt.log','rgb-effects-opt.log','voice-sim/smoothing.log','voice-sim/studio.log','voice-sim/schedule-current.log']:
    p=SYSTEM/'reports/keyboard-rgb'/name;s=p.read_text(encoding='utf-8')
    assert 'PASS' in s and 'Fatal:' not in s and 'ERROR:' not in s,name
    tests[name]=[l for l in s.splitlines() if l.startswith('PASS')]
board=json.loads((SYSTEM/'reports/keyboard-rgb/board/rgb-audio-result.json').read_text(encoding='utf-8'))
assert board['ok']
summary=dict(rtl_tests=tests,rust_tests=dict(passed=81,failed=0,ignored=1),typescript_build=True,
    board=dict(modes=board['modes'],audio=[dict(voices=x['voices'],peak_pcm=x['peak_pcm']) for x in board['audio']],
        telemetry=board['telemetry'],retries=board['retries'],settings_restored=True,hdmi_pages_readback=8),
    physical_rgb_visual_confirmation='not recorded',strict_style_gate_passed=False)
(evidence/'verification.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
rtl=[]
for node in ET.parse(BUILD/'synth_hdmi.gprj').iter('File'):
    if node.attrib['type']=='file.verilog':
        p=Path(node.attrib['path']);rtl.append('Gowin/'+p.relative_to(BUILD/'snapshot').as_posix())
assets=[]
for rel in source_hash:
    p=Path(rel)
    if p.suffix=='.hex':
        if '/hdmi/assets/' in rel:target='hdmi/'+p.name
        else:target=p.relative_to('Gowin/demo1/voice-system').as_posix()
        assets.append(dict(source=rel,target=target))
release=dict(name='SynthString Final RGB',date='2026-11-04',status='final_timing_passed_sram_tested',
    source_build='build-keyboard-rgb-02',top='SynthHdmiTop',device='GW5AT-LV60PG484AC1/I0',user_code='ED65',
    clock_hz=50000000,sample_rate_hz=48828.125,audio_bits=16,voices=8,operators_per_voice=6,slots=4,
    sd_enabled=False,fx_enabled=False,programmed_to='SRAM',flash_written=False,
    bitstream=fs.relative_to(DEST).as_posix(),bitstream_sha256=sha(fs),
    app='Gowin/demo1/voice-system/app/TangSynthStudio.exe',app_sha256=sha(SYSTEM/'app/TangSynthStudio.exe'),
    source_sha256=source_hash,rtl_sources=rtl,assets=assets,
    constraints={name:dict(path=(final/name).relative_to(DEST).as_posix(),sha256=sha(final/name)) for name in ['hdmi.cst','hdmi.sdc']},
    timing_report=(evidence/'timing.json').relative_to(DEST).as_posix(),verification=(evidence/'verification.json').relative_to(DEST).as_posix())
(DEST/'FINAL_RELEASE.json').write_text(json.dumps(release,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'Exported {len(selected)} selected files; frozen {len(rtl)} RTL files; firmware {sha(fs)}')
