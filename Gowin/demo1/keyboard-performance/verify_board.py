"""Version-two telemetry; explicit volume/self-test steps, never synthetic key claims."""
from pathlib import Path
import argparse,json,time,serial
ROOT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--seconds',type=float,default=14);parser.add_argument('--exercise',action='store_true');parser.add_argument('--name',default='board_live');args=parser.parse_args()
assert args.name.replace('_','').isalnum()
port=serial.Serial(port=None,baudrate=115200,timeout=.02);port.dtr=False;port.rts=False;port.port='COM4';port.open()
end=time.monotonic()+1.5
while time.monotonic()<end:port.read(max(1,port.in_waiting))
port.reset_input_buffer();start=time.monotonic();buffer=bytearray();raw=bytearray();records=[];bad=0;sent=[];last_print=-1
steps=[(2,b'0'),(2.5,b'T'),(5,b'6'),(6,b'T'),(9,b'8'),(10,b'T'),(13,b'6')]
try:
 while time.monotonic()-start<args.seconds:
  now=time.monotonic()-start
  if args.exercise and len(sent)<len(steps) and now>=steps[len(sent)][0]:
   command=steps[len(sent)][1];port.write(command);sent.append({'time':now,'command':command.decode()})
  data=port.read(max(1,min(port.in_waiting,8192)));raw.extend(data);buffer.extend(data)
  while len(buffer)>=64:
   i=buffer.find(b'\xa5\x5a\x02\x40')
   if i<0:del buffer[:-3];break
   if i:del buffer[:i]
   if len(buffer)<64:break
   frame=bytes(buffer[:64]);checksum=0
   for b in frame[:62]:checksum^=b
   if frame[62]!=checksum or frame[63]!=13:bad+=1;del buffer[0];continue
   del buffer[:64]
   u=lambda n:int.from_bytes(frame[n:n+4],'little')
   f=dict(zip(['frames','pressed','delivered','nonzero','events'],[u(i) for i in range(4,24,4)]))
   f.update(time=time.monotonic()-start,cycles=int.from_bytes(frame[24:26],'little'),flags=frame[26],key=frame[27],raw=int.from_bytes(frame[28:30],'little'),volume=frame[30],active=frame[31],gain=u(32),input_peak=u(36),output_peak=u(40),clips=u(44),envelope_peak=u(48),wave_peak=u(52),modulation_peak=u(56),stages=frame[60]);records.append(f)
   if int(f['time'])!=last_print:print(json.dumps(f),flush=True);last_print=int(f['time'])
finally:
 if args.exercise:port.write(b'P6')
 port.close()
result={'packets':len(records),'bad_packets':bad,'commands':sent,'records':records,'scope':'Digital telemetry; audible/physical-key confirmation is separate'}
(ROOT/'reports'/(args.name+'.bin')).write_bytes(raw);(ROOT/'reports'/(args.name+'.json')).write_text(json.dumps(result,indent=2))
assert records and bad==0 and all(r['flags']&7==0 and r['cycles']==448 and r['stages']==127 for r in records)
if args.exercise:
 assert len(sent)==len(steps) and {0,6,8}.issubset({r['volume'] for r in records})
 assert any(r['volume']==0 and r['gain']==0 and r['flags']&16 for r in records)
 assert any(r['volume']==8 and r['output_peak']>0 and r['active']>0 for r in records)
print('PASS board telemetry and requested command readback',len(records),flush=True)
