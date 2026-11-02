"""Exercise real protocol-4 synthesis and record FPGA latency telemetry."""
from pathlib import Path
import argparse,datetime,json,serial,sys,time
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'keyboard-studio'))
from studio_model import crc,packet,profile

class Board:
    def __init__(self,name):
        self.port=serial.Serial(port=None,baudrate=115200,timeout=.02)
        self.port.dtr=False;self.port.rts=False;self.port.port=name;self.port.open()
        self.buffer=bytearray();self.raw=bytearray();self.records=[];self.bad=0;self.seq=50;self.commands=[]
        self.start=time.monotonic()
        end=self.start+1.5
        while time.monotonic()<end:self.port.read(max(1,self.port.in_waiting))
        self.port.reset_input_buffer()
    def poll(self,seconds):
        end=time.monotonic()+seconds
        while time.monotonic()<end:
            data=self.port.read(max(1,min(8192,self.port.in_waiting)));self.raw.extend(data);self.buffer.extend(data)
            while len(self.buffer)>=192:
                index=self.buffer.find(bytes([0xa5,0x5a,4,192]))
                if index<0:del self.buffer[:-3];break
                if index:del self.buffer[:index]
                if len(self.buffer)<192:break
                b=bytes(self.buffer[:192]);check=0
                for value in b[:190]:check^=value
                if b[190]!=check or b[191]!=13:self.bad+=1;del self.buffer[0];continue
                del self.buffer[:192]
                u=lambda offset:int.from_bytes(b[offset:offset+4],'little')
                r=dict(host_seconds=round(time.monotonic()-self.start,3),frames=u(4),pressed=u(8),delivered=u(12),nonzero=u(16),events=u(20),
                    cycles=int.from_bytes(b[24:26],'little'),flags=b[26],key=b[27],raw=int.from_bytes(b[28:30],'little'),volume=b[30],active=b[31],
                    gain=u(32),input_peak=u(36),output_peak=u(40),clips=u(44),stages=b[60],ack_seq=b[62],ack_op=b[63],ack_status=b[64],ack_key=b[65],ack_crc=int.from_bytes(b[66:68],'little'),commits=u(68))
                l=dict(records=u(80),key=b[84],flags=b[85],total=u(88),qualify=u(92),queue=u(96),compute=u(100),output=u(104),mix=u(108),
                    minimum=u(112),maximum=u(116),sum=int.from_bytes(b[120:128],'little'),late=u(128),timeouts=u(132),overwritten=u(136),scan_period=u(140),
                    physical_records=u(144),remote_records=u(148),tick=u(152),start=u(156),dac=u(160),budget=u(164),pending=u(168),onset_wait=u(172),canceled=u(176))
                r['latency']=l;self.records.append(r)
                assert r['flags']&7==0 and r['cycles']==385 and r['stages']==127,r
                if l['records']:
                    assert l['total']==sum(l[k] for k in ('qualify','queue','compute','onset_wait','output')),l
                    assert l['total']==(l['dac']-l['start'])&0xffffffff,l
                    assert l['minimum']<=l['total']<=l['maximum'] and l['mix']<=l['output'],l
    def send(self,op,key=0,payload=b''):
        self.seq=(self.seq+1)&255
        if op in (2,3,4,6,7) and len(payload)<=1:
            data=bytes([0xa5,0xc4,op,self.seq,key])+payload.ljust(1,b'\0');data+=crc(data).to_bytes(2,'little')
        else:data=packet(op,self.seq,key,payload)
        self.port.write(data);expected=(self.seq,op,key,int.from_bytes(data[-2:],'little'))
        self.commands.append(dict(op=op,key=key,seq=self.seq))
        return expected
    def acknowledge(self,expected):
        end=time.monotonic()+1
        while time.monotonic()<end:
            self.poll(.025)
            if self.records:
                r=self.records[-1]
                if tuple(r[k] for k in ('ack_seq','ack_op','ack_key','ack_crc'))==expected:
                    assert r['ack_status']==0,r
                    return r
        raise AssertionError('No matching ACK: '+str(expected))
    def command(self,op,key=0,payload=b''):return self.acknowledge(self.send(op,key,payload))
    def clear(self):
        self.port.write(b'L');self.poll(.25)
        assert self.records[-1]['latency']['records']==0

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--port',default='COM4');args=parser.parse_args()
    board=Board(args.port);result=dict(passed=False,created=datetime.datetime.now().isoformat(),scope='Digital FPGA telemetry and command path; acoustic confirmation is separate')
    modes=[];changed_key=None;original_volume=6
    try:
        board.poll(.65);assert board.records and board.bad==0,'No protocol-4 telemetry'
        result['initial']=board.records[-1];original_volume=result['initial']['volume']
        board.command(4);board.command(6,payload=bytes([3]));board.poll(.2);board.clear()
        free=[i for i in range(32) if not (board.records[-1]['pressed']>>i)&1];assert free,'All physical keys held'
        key=12 if 12 in free else free[0];changed_key=key
        for mode in ('mix','fm','am','ring'):
            value=profile(48+key,mode=mode,ratio=2,depth=.6,attack=2,decay=100,sustain=.7,release=90)
            board.command(1,key,value.to_bytes(64,'little'));before=board.records[-1]['latency']['records']
            board.command(2,key,bytes([96]));board.poll(.25);sounding=board.records[-1]
            assert sounding['latency']['records']>before and sounding['latency']['key']==key,sounding
            assert sounding['latency']['flags']&1==0 and sounding['latency']['qualify']==0,sounding
            assert sounding['output_peak']>0 and sounding['active']>0
            modes.append(dict(mode=mode,latency=sounding['latency'],output_peak=sounding['output_peak']))
            board.command(3,key);board.poll(.15)
        # Send a burst of note-ons; the arithmetic still handles all 32 voices.
        board.command(6,payload=bytes([1]));board.clear();before_nonzero=board.records[-1]['nonzero']
        free=[i for i in range(32) if not (board.records[-1]['pressed']>>i)&1]
        for key in free:expected=board.send(2,key,bytes([80]))
        board.acknowledge(expected);board.poll(.35);chord=board.records[-1]
        assert chord['active']==32 and chord['nonzero']>before_nonzero,chord
        assert chord['latency']['remote_records']==len(free) and chord['latency']['overwritten']==0,chord
        board.command(4);board.poll(.35)
        # A silent path must produce a timeout, never a fabricated zero latency.
        board.command(6,payload=bytes([0]));board.poll(.2);assert board.records[-1]['gain']==0
        board.clear();key=changed_key;board.command(2,key,bytes([96]));board.poll(1.15)
        muted=board.records[-1];assert muted['latency']['records']==0 and muted['latency']['timeouts']==1,muted
        board.command(3,key);board.poll(.2)
        original=int((ROOT/'note_profiles.hex').read_text().splitlines()[key],16)
        board.command(1,key,original.to_bytes(64,'little'));changed_key=None
        board.command(6,payload=bytes([original_volume]));board.poll(.2);board.clear()
        assert board.bad==0 and all(r['clips']==result['initial']['clips'] for r in board.records)
        result.update(passed=True,modes=modes,chord=chord,muted_timeout=muted,final=board.records[-1],packets=len(board.records),bad_packets=board.bad)
    finally:
        try:
            board.send(4)
            if changed_key is not None:
                original=int((ROOT/'note_profiles.hex').read_text().splitlines()[changed_key],16)
                board.send(1,changed_key,original.to_bytes(64,'little'))
            board.send(6,payload=bytes([original_volume]))
        finally:board.port.close()
        result.update(commands=board.commands,records=board.records)
        (ROOT/'reports/live_validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        (ROOT/'reports/live_serial.bin').write_bytes(board.raw)
    print(json.dumps({k:v for k,v in result.items() if k not in ('commands','records')},ensure_ascii=False,indent=2))

if __name__=='__main__':main()
