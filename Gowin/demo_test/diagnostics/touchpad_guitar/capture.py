"""只读真实串口，保存T/G帧和独立采样率；不向调试器发送命令。"""
import argparse,json,sys,time
from pathlib import Path
import serial
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'desktop'))
from keyboard_core import StreamParser

p=argparse.ArgumentParser();p.add_argument('--seconds',type=float,default=10);p.add_argument('--name',default='live');a=p.parse_args()
root=Path(__file__).parent/'reports';parser=StreamParser();records=[];events=[];start=time.monotonic()
s=serial.Serial(port=None,baudrate=115200,timeout=.01,rtscts=False,dsrdtr=False)
s.dtr=False;s.rts=False;s.port='COM4';s.open()
try:
    until=time.monotonic()+2
    while time.monotonic()<until:s.read(max(1,min(4096,s.in_waiting)))
    start=time.monotonic()
    with (root/(a.name+'.bin')).open('wb') as f:
        while time.monotonic()-start<a.seconds:
            data=s.read(max(1,min(4096,s.in_waiting)));f.write(data);parser.feed(data);now=time.monotonic()-start
            while parser.touchpad_samples:
                r=parser.touchpad_samples.popleft()
                records.append(dict(time=now,board=r.board,sequence=r.sequence,error=r.error,mask=r.mask,raw=r.raw.hex(),filtered=r.filtered))
            while parser.guitar_samples:
                r=parser.guitar_samples.popleft();events.append(dict(received=now,**r.__dict__))
finally:s.close()
rates=[]
for board in (1,2):
    rs=[r for r in records if r['board']==board and not r['error']]
    rates.append(((rs[-1]['sequence']-rs[0]['sequence'])&65535)/(rs[-1]['time']-rs[0]['time']) if len(rs)>1 else 0)
summary=dict(seconds=time.monotonic()-start,raw_frames=parser.touchpad_records,guitar_frames=parser.guitar_records,
    crc_errors=dict(raw=parser.touchpad_errors,guitar=parser.guitar_errors),sample_hz=rates,
    error_codes=[sorted(set(r['error'] for r in records if r['board']==b)) for b in (1,2)],
    events=[r for r in events if r['mask']],last_guitar=events[-2:],records=records,guitar_records=events)
(root/(a.name+'.json')).write_text(json.dumps(summary,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in summary.items() if k not in ('records','guitar_records','events')}))
