"""只读 COM4；先持续排空桥接缓存，再保存 CRC 正确的原始记录。"""
import argparse
import json
import time
import sys
from pathlib import Path
import serial

ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent.parent/'desktop'))
from touchpad_core import crc8

p=argparse.ArgumentParser()
p.add_argument('--name',default='capture')
p.add_argument('--seconds',type=float,default=8)
p.add_argument('--drain',type=float,default=3)
a=p.parse_args()
s=serial.Serial(port=None,baudrate=115200,timeout=.02)
s.dtr=False;s.rts=False;s.port='COM4';s.open()
data=bytearray();buffer=bytearray();records=[];errors=0
try:
    until=time.monotonic()+a.drain
    while time.monotonic()<until:s.read(min(4096,max(1,s.in_waiting)))
    started=time.monotonic()
    while time.monotonic()-started<a.seconds:
        b=s.read(min(4096,max(1,s.in_waiting)))
        data.extend(b);buffer.extend(b)
        while b'\n' in buffer:
            line,_,buffer=buffer.partition(b'\n');line+=b'\n'
            if len(line)!=100 or line[0] not in b'TD' or line[95:96]!=b'*':continue
            try:
                if crc8(line[:95])!=int(line[96:98],16):raise ValueError('CRC')
                records.append(dict(t=time.monotonic()-started,type=chr(line[0]),board=int(chr(line[1])),
                    sequence=int(line[2:6],16),address=int(line[6:8],16),error=int(line[8:10],16),
                    lines=int(line[10:11],16),raw=bytes.fromhex(line[11:95].decode()).hex()))
            except ValueError:errors+=1
finally:s.close()
(ROOT/'reports'/f'{a.name}.bin').write_bytes(data)
result=dict(bytes=len(data),frames=len(records),errors=errors,records=records)
(ROOT/'reports'/f'{a.name}.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print('bytes',len(data),'frames',len(records),'CRC errors',errors)
for board in [1,2]:
    subset=[r for r in records if r['board']==board]
    print('board',board,'error counts',{e:sum(r['error']==e for r in subset) for e in set(r['error'] for r in subset)})
    if subset:print(subset[-1])
