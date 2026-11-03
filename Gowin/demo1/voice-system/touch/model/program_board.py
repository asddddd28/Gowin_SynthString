"""SRAM only; exact frozen source and timing/evidence gates precede JTAG."""
from pathlib import Path
import datetime,hashlib,json,subprocess,serial
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'reports/touch-performance';BUILD=ROOT/'reports/synthui-hdmi/build-touch-final'
timing=json.loads((OUT/'timing-final.json').read_text(encoding='utf-8'))
assert Path(timing['build']['implDir']).resolve()==(BUILD/'impl').resolve()
assert timing['clean'] and not timing['timing']['violations']
assert all(not c['failing'] for c in timing['timing']['fmax'])
for entry in json.loads((BUILD/'inputs.json').read_text(encoding='utf-8')):
 assert hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest()==entry['sha256'],entry['path']
for header in ['i2c_master_defines.v','timescale.v']:
 original=ROOT.parents[1]/'demo_test/diagnostics/touchpad/vendor'/header
 assert original.read_bytes()==(BUILD/'snapshot'/original.relative_to(ROOT.parents[1])).read_bytes()
for test in ['tb_touch_position','tb_touch_performance','tb_touch_voice','tb_touch_filter','tb_touch_system','tb_studio_system','tb_display_control','tb_display_audio','tb_display_video','tb_master_lowpass']:
 text=(OUT/f'{test}.log').read_text(encoding='utf-8',errors='replace');assert 'PASS' in text and 'Fatal:' not in text and 'ERROR:' not in text,test
assert 'Bitstream generation completed' in (OUT/'gowin-final.log').read_text(encoding='utf-8',errors='replace')
bitstream=BUILD/'impl/pnr/synth_hdmi.fs'
record={'time':datetime.datetime.now().astimezone().isoformat(),'sha256':hashlib.sha256(bitstream.read_bytes()).hexdigest(),'bitstream':str(bitstream),'mode':'SRAM','programmed':False}
(OUT/'programmed.json').write_text(json.dumps(record,indent=2))
guard=serial.Serial(port=None,baudrate=115200,timeout=.02);guard.dtr=False;guard.rts=False;guard.port='COM4';guard.open()
try:
 result=subprocess.run(['C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe','--device','GW5AT-60B','--cable-index','4','--run','2','--frequency','15MHz','--fsFile',str(bitstream)],capture_output=True,text=True,errors='replace',timeout=90)
finally:guard.close()
log=result.stdout+result.stderr;(OUT/'program.log').write_text(log,encoding='utf-8')
assert result.returncode==0 and 'Finished.' in log,log
record['programmed']=True;(OUT/'programmed.json').write_text(json.dumps(record,indent=2))
print('PASS SRAM programmed',record['sha256']);print(log[-900:])
