"""Read-only board capture. Does not change calibration, modes, bridge or firmware."""
import argparse
import json
import sys
import time
from pathlib import Path
from dataclasses import asdict
import serial

ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parents[1]/'desktop'))
from keyboard_core import StreamParser

args=argparse.ArgumentParser()
args.add_argument('--port',default='COM4')
args.add_argument('--seconds',type=float,default=8)
options=args.parse_args()
parser=StreamParser()
records={name:[] for name in ('key','encoder','joystick','touch','guitar','identity','status','game')}
port=serial.Serial(port=None,baudrate=115200,timeout=.03,write_timeout=.5,rtscts=False,dsrdtr=False)
port.dtr=False
port.rts=False
port.port=options.port
port.open()
warmup=time.monotonic()+1.0
with (ROOT/'reports/live_warmup.bin').open('wb') as warm:
    while time.monotonic()<warmup:
        warm.write(port.read(max(1,min(4096,port.in_waiting))))
# The first retained fragment can begin mid-line; align to LF before parsing.
aligned=False
started=time.monotonic()
with (ROOT/'reports/live_serial.bin').open('wb') as raw:
    try:
        while time.monotonic()-started<options.seconds:
            data=port.read(max(1,min(4096,port.in_waiting)))
            raw.write(data)
            if not aligned:
                if b'\n' not in data:
                    continue
                data=data.split(b'\n',1)[1]
                aligned=True
            elapsed=time.monotonic()-started
            records['key'].extend(dict(time=elapsed,key=k,raw=r) for k,r in parser.feed(data))
            for attr,name in [('encoder_samples','encoder'),('joystick_samples','joystick'),
                ('touchpad_samples','touch'),('guitar_samples','guitar'),('hardware_identities','identity'),
                ('statuses','status'),('game_statuses','game')]:
                queue=getattr(parser,attr)
                while queue:
                    row=asdict(queue.popleft())
                    if name=='touch': row['raw']=row['raw'].hex()
                    records[name].append(dict(time=elapsed,**row))
    finally:
        port.close()
summary={
    'seconds':time.monotonic()-started,'port':options.port,'tx_bytes':0,
    'counts':{name:len(rows) for name,rows in records.items()},
    'keys_seen':sorted({row['key'] for row in records['key']}),
    'errors':{name:getattr(parser,name) for name in ('sequence_errors','encoder_errors','joystick_errors',
        'touchpad_errors','guitar_errors','hardware_errors','status_errors','game_errors')},
    'last_status':records['status'][-1] if records['status'] else None,
    'screen_verification':'Requires user observation; not inferred from UART or JTAG.'}
(ROOT/'reports/live_validation.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
(ROOT/'reports/live_records.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
print(json.dumps(summary,indent=2))
if not records['identity'] or len(summary['keys_seen'])!=32 or any(summary['errors'].values()):
    raise SystemExit(1)
