"""One-time reference fixtures from the previous Python parser and real captures.
The released Rust application does not run Python.
"""
from pathlib import Path
import sys, json, shutil
ROOT=Path(__file__).resolve().parents[1]
OLD=ROOT.parent/'desktop'
sys.path.insert(0,str(OLD))
from keyboard_core import StreamParser, Profile
from board_protocol import calibration_commands,command

out=ROOT/'src-tauri/tests/fixtures'
out.mkdir(parents=True,exist_ok=True)
capture=ROOT.parent/'diagnostics/hardware_lab/reports/live_serial.bin'
data=capture.read_bytes()
p=StreamParser();keys=p.feed(data)
last=[None]*32
for key,value in keys:last[key-1]=value
expected=dict(counts=[p.records,len(p.statuses),len(p.game_statuses),p.encoder_records,p.joystick_records,p.touchpad_records,p.guitar_records,p.hardware_records],
              keys=last,status=p.statuses[-1].__dict__,game=p.game_statuses[-1].__dict__,
              encoders=[v.__dict__ for v in list(p.encoder_samples)[-5:]],
              joystick=p.joystick_samples[-1].__dict__,
              pads=[dict(board=r.board,filtered=r.filtered,baseline=r.baseline,delta=r.delta,mask=r.mask,error=r.error) for r in list(p.touchpad_samples)[-2:]],
              guitar=[v.__dict__ for v in list(p.guitar_samples)[-2:]])
# Queued status collections have bounded capacity; count raw valid lines independently.
expected['counts'][1]=sum(l.startswith(b'@') for l in data.splitlines())
expected['counts'][2]=sum(l.startswith(b'#') for l in data.splitlines())
shutil.copy2(capture,out/'hardware_live.bin')
(out/'expected.json').write_text(json.dumps(expected,ensure_ascii=False,indent=2),encoding='utf8')
import os
source=Path(os.environ['LOCALAPPDATA'])/'TangKeyboardLab/calibration.json'
profile=Profile.load(source)
shutil.copy2(source,out/'legacy_calibration.json')
commands=[command(i,**fields).decode() for i,fields in enumerate(calibration_commands(profile))]
(out/'commands.json').write_text(json.dumps(commands,indent=2),encoding='utf8')
print(json.dumps(dict(bytes=len(data),counts=expected['counts'],commands=len(commands))))
