"""Read real Studio telemetry, verify config ACK and one gentle remote note."""
from pathlib import Path
import json,time,serial
from studio_model import crc,packet,profile

ROOT=Path(__file__).resolve().parent
port=serial.Serial(port=None,baudrate=115200,timeout=.02)
port.dtr=False;port.rts=False;port.port='COM4';port.open()
raw=bytearray();buffer=bytearray();records=[];bad=0;seq=100;sent=[]
started=time.monotonic()
def poll(seconds):
    global bad
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        data=port.read(max(1,min(port.in_waiting,8192)));raw.extend(data);buffer.extend(data)
        while len(buffer)>=80:
            offset=buffer.find(b'\xa5\x5a\x03\x50')
            if offset<0:del buffer[:-3];break
            if offset:del buffer[:offset]
            if len(buffer)<80:break
            b=bytes(buffer[:80]);checksum=0
            for value in b[:78]:checksum^=value
            if b[78]!=checksum or b[79]!=13:bad+=1;del buffer[0];continue
            del buffer[:80]
            u=lambda n:int.from_bytes(b[n:n+4],'little')
            r=dict(time=round(time.monotonic()-started,3),frames=u(4),pressed=u(8),delivered=u(12),nonzero=u(16),events=u(20),
                cycles=int.from_bytes(b[24:26],'little'),flags=b[26],key=b[27],raw=int.from_bytes(b[28:30],'little'),volume=b[30],active=b[31],
                gain=u(32),input_peak=u(36),output_peak=u(40),clips=u(44),stages=b[60],
                ack_seq=b[62],ack_op=b[63],ack_status=b[64],ack_key=b[65],ack_crc=int.from_bytes(b[66:68],'little'),commits=u(68))
            records.append(r)
def command(op,key=0,payload=b''):
    global seq
    seq=(seq+1)&255
    if op in [2,3,4,6,7] and len(payload)<=1:
        data=bytes([0xa5,0xc4,op,seq,key])+payload.ljust(1,b'\0');data+=crc(data).to_bytes(2,'little')
    else:data=packet(op,seq,key,payload)
    expected_crc=int.from_bytes(data[-2:],'little')
    port.write(data);sent.append(dict(op=op,seq=seq,key=key,bytes=len(data)))
    end=time.monotonic()+1
    while time.monotonic()<end:
        poll(.04)
        if records:
            r=records[-1]
            if (r['ack_seq'],r['ack_op'],r['ack_key'],r['ack_crc'])==(seq,op,key,expected_crc):
                assert r['ack_status']==0,r
                return r
    raise AssertionError('No matching board ACK: '+str(sent[-1]))
result={'passed':False,'scope':'Digital board telemetry; analog listening confirmation is separate'}
original_volume=6
try:
    until=time.monotonic()+1.5
    while time.monotonic()<until:port.read(max(1,port.in_waiting))
    port.reset_input_buffer();poll(.6)
    assert records and bad==0,'Missing valid Studio protocol 3 telemetry'
    original_volume=records[-1]['volume']
    command(7);command(6,payload=bytes([3]))
    applied=command(1,12,profile(60,mode='fm',depth=.6,ratio=2,attack=5,decay=100,sustain=.65,release=120).to_bytes(64,'little'))
    before=records[-1]['nonzero'];command(2,12,bytes([96]));poll(.4)
    sounding=records[-1]
    command(3,12);poll(.5)
    command(1,12,profile(60).to_bytes(64,'little'))
    command(6,payload=bytes([original_volume]));poll(.3)
    assert sounding['active']>0 and sounding['delivered']&(1<<12) and sounding['nonzero']>before and sounding['output_peak']>0,sounding
    assert bad==0 and all(r['flags']&7==0 and r['cycles']==873 and r['stages']==127 for r in records)
    result.update(passed=True,packets=len(records),bad_packets=bad,initial=records[0],sounding=sounding,final=records[-1],config_commits=records[-1]['commits'])
finally:
    # Leave no held remote note, restore the original volume, then release the port.
    try:port.write(packet(4,240,0)+packet(6,241,0,bytes([original_volume])))
    finally:port.close()
    result.update(commands=sent,records=records)
    (ROOT/'reports/flash_live.bin').write_bytes(raw)
    (ROOT/'reports/flash_live.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:v for k,v in result.items() if k not in ['records','commands']},ensure_ascii=False))
