"""Codec, persisted retry and completion identity tests without opening hardware."""
import tempfile
import sys
import types
import json
from unittest.mock import patch
from pathlib import Path
from system_model import ROOT,packet,crc16,decode_response
sys.path.insert(0,str(ROOT/'host'))
from control import Client
import control


class Loopback:
    def __init__(self):self.writes=[];self.reply=b''
    def write(self,raw):
        self.writes.append(raw)
        header=bytes((0x53,0x52,5,raw[3]))+raw[4:8]+(123).to_bytes(16,'little')+bytes((0,raw[8],raw[9],int(len(self.writes)>1),0,0))
        self.reply=b'noise'+header+crc16(header).to_bytes(2,'little')
    def flush(self):pass
    def read(self,count):
        result,self.reply=self.reply[:count],self.reply[count:]
        return result


def check():
    port=Loopback()
    with tempfile.TemporaryDirectory() as temp:
        state=Path(temp)/'session.json'
        first=Client(port,state)
        assert first.read(4)==123
        assert first.state['next_sequence']==1
        pending=packet(1,0xa4,0,[10,100000,1<<26,1<<25])
        first.state['pending']=pending.hex();first.save()
        recovered=Client(port,state)
        answer=recovered.finish_pending()
        assert port.writes[-1]==pending and answer['replayed']
        assert recovered.state['next_sequence']==2 and recovered.state['pending'] is None
        malformed=bytes(32)
        try:decode_response(malformed)
        except ValueError:pass
        else:raise AssertionError('invalid CRC accepted')
    print('PASS host codec, noisy RX, persisted exact retry, sequence and CRC')
    bank_check()


class BoardLoopback(Loopback):
    def __init__(self,abi=0x00010005,fx=0):super().__init__();self.abi=abi;self.fx=fx
    def open(self):assert not self.dtr and not self.rts
    def __enter__(self):return self
    def __exit__(self,*args):return False
    def write(self,raw):
        super().write(raw)
        address=int.from_bytes(raw[10:14],'little')
        value=(self.abi if address==4 else self.fx if address==0x4c else 0) if raw[3]==1 else 0
        header=bytes((0x53,0x52,5,raw[3]))+raw[4:8]+value.to_bytes(16,'little')+bytes((0,raw[8],raw[9],0,0,0))
        self.reply=header+crc16(header).to_bytes(2,'little')


def bank_check():
    with tempfile.TemporaryDirectory() as temp:
        state=Path(temp)/'bank.json';port=BoardLoopback()
        module=types.SimpleNamespace(Serial=lambda *args,**kwargs:port)
        for index,program in enumerate((4,1,42,68,32,43,79,106)):
            slot=index%4
            args=['control.py','--port','MOCK','--state',str(state),'bank','--program',str(program),'--slot',str(slot),'--revision',str(2+index//4)]
            with patch.object(sys,'argv',args),patch.dict(sys.modules,{'serial':module}):control.main()
        commands=[raw for raw in port.writes if raw[3]==0]
        assert len(commands)==112
        assert [(raw[8],raw[9]) for raw in commands if raw[8]==0xa3]==[(0xa3,n%4) for n in range(8)]
        assert json.loads(state.read_text())['slot_revisions']=={str(n):3 for n in range(4)}
        # An older engine sees only the read-only preflight, never A0/A1 writes.
        old=BoardLoopback(0x00010004);module.Serial=lambda *args,**kwargs:old
        args=['control.py','--port','MOCK','--state',str(Path(temp)/'old.json'),'bank','--program','4']
        with patch.object(sys,'argv',args),patch.dict(sys.modules,{'serial':module}):
            try:control.main()
            except RuntimeError as error:assert 'ABI' in str(error)
            else:raise AssertionError('old engine accepted DX profile')
        assert len(old.writes)==1 and old.writes[0][3]==1
        for fx in (0,1):
            board=BoardLoopback(fx=fx);module.Serial=lambda *args,**kwargs:board
            args=['control.py','--port','MOCK','--state',str(Path(temp)/f'panic-{fx}.json'),'panic']
            with patch.object(sys,'argv',args),patch.dict(sys.modules,{'serial':module}):control.main()
            assert [raw[8] for raw in board.writes if raw[3]==0]==([0xa7,0xc3] if fx else [0xa7])
    print('PASS host FM1 eight-preset/four-slot upload, revision persistence, ABI preflight and dry/FX panic')


if __name__=='__main__':check()
