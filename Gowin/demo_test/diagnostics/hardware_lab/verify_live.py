"""综合固件实板检查：保存真实混合帧，并以匹配CRC/序号的ACK验证命令。"""
import json,os,sys,time
from pathlib import Path
from dataclasses import asdict
import serial
root=Path(__file__).resolve().parent
sys.path.insert(0,str(root.parents[1]/'desktop'))
from keyboard_core import StreamParser,Profile
from board_protocol import command,calibration_commands,QUERY,EFFECT,GAME_START,GAME_STOP

parser=StreamParser();records={key:[] for key in ('key','encoder','joystick','touch','guitar','identity','status','game')}
acks=[];seq=100;tx=0;start=time.monotonic()
config=Path(os.environ['LOCALAPPDATA'])/'TangKeyboardLab'
profile=Profile.load(config/'calibration.json')
effect=json.loads((config/'effects.json').read_text(encoding='utf8')) if (config/'effects.json').exists() else dict(mode=1,direction=0)
port=serial.Serial(port=None,baudrate=115200,timeout=.01,write_timeout=.5,rtscts=False,dsrdtr=False)
port.dtr=False;port.rts=False;port.port='COM4';port.open()
raw_file=(root/'reports/live_serial.bin').open('wb')
def read():
    data=port.read(max(1,min(4096,port.in_waiting)));raw_file.write(data)
    now=time.monotonic()-start
    records['key'].extend(dict(time=now,key=k,raw=r) for k,r in parser.feed(data))
    for attr,name in [('encoder_samples','encoder'),('joystick_samples','joystick'),('touchpad_samples','touch'),('guitar_samples','guitar'),('hardware_identities','identity'),('statuses','status'),('game_statuses','game')]:
        queue=getattr(parser,attr)
        while queue:
            r=queue.popleft();item=asdict(r)
            if name=='touch':item['raw']=r.raw.hex()
            records[name].append(dict(time=now,**item))
def collect(seconds):
    until=time.monotonic()+seconds
    while time.monotonic()<until:read()
def transact(fields):
    global seq,tx
    before=len(records['status']);sent=time.monotonic()
    packet=command(seq,**fields);tx+=port.write(packet)
    deadline=sent+1.5
    while time.monotonic()<deadline:
        read()
        matching=[r for r in records['status'][before:] if r['seq']==seq and r['result']!=128]
        if matching:
            r=matching[-1];assert r['result']==0,(fields,r)
            acks.append(dict(command=fields,response=r,round_trip_ms=(time.monotonic()-sent)*1000))
            seq=(seq+1)%255
            return r
    raise RuntimeError(f'ACK timeout {fields}')
error=None
try:
    until=time.monotonic()+2
    while time.monotonic()<until:port.read(max(1,min(4096,port.in_waiting)))
    start=time.monotonic();collect(2)
    assert records['identity'],'No validated integrated capability frame'
    transact(dict(code=QUERY))
    for fields in calibration_commands(profile):transact(fields)
    assert acks[-1]['response']['configured']
    for mode in (0,1,2,3,4,6):transact(dict(code=EFFECT,mode=mode))
    for game in (1,2,3):
        transact(dict(code=GAME_START,key=game));collect(.4)
        state=records['game'][-1];assert state['game']==game and state['phase']==1,state
        transact(dict(code=GAME_STOP,mode=effect['mode'],direction=effect['direction']))
    transact(dict(code=EFFECT,mode=effect['mode'],direction=effect['direction']))
    collect(12)
except Exception as exc:
    error=str(exc)
finally:
    port.close();raw_file.close()
rates=[]
for board in (1,2):
    rs=[r for r in records['touch'] if r['board']==board and r['error']==0]
    rates.append(((rs[-1]['sequence']-rs[0]['sequence'])&65535)/(rs[-1]['time']-rs[0]['time']) if len(rs)>1 else 0)
errors=dict(key_sequence=parser.sequence_errors,encoder=parser.encoder_errors,encoder_sequence=parser.encoder_sequence_errors,
 joystick=parser.joystick_errors,joystick_sequence=parser.joystick_sequence_errors,touch=parser.touchpad_errors,guitar=parser.guitar_errors,
 identity=parser.hardware_errors,status=parser.status_errors,game=parser.game_errors)
summary=dict(error=error,seconds=time.monotonic()-start,frames={k:len(v) for k,v in records.items()},errors=errors,
 touch_sample_hz=rates,touch_error_codes=[sorted(set(r['error'] for r in records['touch'] if r['board']==b)) for b in (1,2)],
 acknowledged_commands=len(acks),tx_bytes=tx,max_ack_ms=max((r['round_trip_ms'] for r in acks),default=None),
 final_status=records['status'][-1] if records['status'] else None,final_game=records['game'][-1] if records['game'] else None,
 last_guitar=records['guitar'][-2:],raw_range=[min((r['raw'] for r in records['key']),default=None),max((r['raw'] for r in records['key']),default=None)],
 physical_input_test='Not performed by this script; no fabricated sensor inputs')
(root/'reports/live_validation.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding='utf8')
(root/'reports/live_records.json').write_text(json.dumps(dict(records=records,acknowledgements=acks),indent=2),encoding='utf8')
print(json.dumps(summary,ensure_ascii=False))
if error or any(errors.values()):raise SystemExit(1)
