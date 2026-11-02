"""Protocol 5 diagnostic client; one host process and one persistent session per board.

Does not open a port until main(). A timed-out packet remains in the session file
and is retried byte-for-byte on the next invocation, before any new command.
Resetting the FPGA also requires --new-session. Never use that flag just to retry.
"""
import argparse
import json
from pathlib import Path
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'model'))
from system_model import packet,decode_response,RATE,UNITY
from compile_voice_patch import compile_patch
from compile_fx import compile_fx
from dx7_bank import ROOT as ENGINE_ROOT, INITIAL, convert


class Client:
    def __init__(self,port,state_path):
        self.port=port
        self.path=Path(state_path)
        self.state=json.loads(self.path.read_text(encoding='utf-8')) if self.path.exists() else dict(next_sequence=0,pending=None)

    def save(self):
        self.path.parent.mkdir(parents=True,exist_ok=True)
        temp=self.path.with_suffix(self.path.suffix+'.tmp')
        temp.write_text(json.dumps(self.state,indent=2)+'\n',encoding='utf-8')
        temp.replace(self.path)

    def exchange(self,raw,retries=3):
        for _ in range(retries):
            self.port.write(raw)
            self.port.flush()
            buffer=bytearray()
            deadline=time.monotonic()+1.0
            while time.monotonic()<deadline:
                buffer.extend(self.port.read(32))
                while len(buffer)>=32:
                    try:response=decode_response(buffer[:32])
                    except ValueError:
                        del buffer[0]
                        continue
                    del buffer[:32]
                    if (response['sequence'],response['kind'],response['opcode'],response['address'])==(int.from_bytes(raw[4:8],'little'),raw[3],raw[8],raw[9]):
                        return response
        raise TimeoutError('No matching CRC-valid response; pending packet retained for exact retry')

    def finish_pending(self):
        if not self.state['pending']:return None
        raw=bytes.fromhex(self.state['pending'])
        response=self.exchange(raw)
        if response['transport_status'] in (2,3):
            raise RuntimeError('Host/board session mismatch. Use the matching session file; after FPGA reset only, start --new-session.')
        self.state.update(next_sequence=(int.from_bytes(raw[4:8],'little')+1)&0xffffffff,pending=None,last_response=response)
        self.save()
        return response

    def request(self,opcode=0,address=0,words=(),kind=0):
        if self.state['pending']:
            raise RuntimeError('Recover the pending request before submitting a new operation')
        self.state['pending']=packet(self.state['next_sequence'],opcode,address,words,kind).hex()
        self.save()
        response=self.finish_pending()
        if response['transport_status']:
            raise RuntimeError(f"Transport rejected request: {response}")
        if kind==0 and (response['result']>>64)&255:
            raise RuntimeError(f"Engine rejected command: {response}")
        return response

    def read(self,address):return self.request(words=[address],kind=1)['result']&0xffffffff


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',required=True)
    parser.add_argument('--state',type=Path)
    parser.add_argument('--new-session',action='store_true',help='Only after reset/reprogram of this FPGA; preserves previous state as .previous')
    commands=parser.add_subparsers(dest='action',required=True)
    commands.add_parser('status')
    commands.add_parser('recover')
    read=commands.add_parser('read');read.add_argument('address',type=lambda x:int(x,0))
    play=commands.add_parser('play');play.add_argument('--note',type=int,default=60);play.add_argument('--slot',type=int,default=0);play.add_argument('--seconds',type=float,default=1)
    play.add_argument('--velocity',type=int,default=100)
    upload=commands.add_parser('upload');upload.add_argument('file',type=Path);upload.add_argument('--slot',type=int,default=0);upload.add_argument('--fx',action='store_true')
    bank=commands.add_parser('bank',help='Load one of the initial four FM1 library programs into a resident slot')
    bank.add_argument('--program',type=int,required=True,choices=INITIAL)
    bank.add_argument('--slot',type=int,default=0)
    bank.add_argument('--revision',type=int,help='Optional explicit monotonic uint32 revision; otherwise timestamp plus persisted monotonicity')
    commands.add_parser('panic')
    args=parser.parse_args()
    if args.action=='play' and not (0<=args.note<=127 and 0<=args.slot<4 and 0<args.seconds<=30 and 1<=args.velocity<=127):parser.error('note/slot/duration/velocity out of range')
    if args.action=='bank' and (not 0<=args.slot<4 or (args.revision is not None and not 1<=args.revision<1<<32)):parser.error('slot/revision out of range')
    if args.action=='read' and not (0<=args.address<=0x60 and args.address%4==0):parser.error('read-only telemetry range is 0x00..0x60, aligned')
    state=args.state or Path(__file__).resolve().parent/f'session-{args.port.replace(":", "_")}.json'
    if args.new_session and state.exists():state.replace(state.with_suffix('.previous'))
    import serial
    with serial.Serial(args.port,115200,timeout=0.03,write_timeout=1) as port:
        client=Client(port,state)
        if args.action=='recover':
            print(json.dumps(client.finish_pending(),indent=2));return
        if client.state['pending']:raise RuntimeError('Previous operation has unknown outcome. Run recover first; it retries that exact packet.')
        if args.action=='status':
            status=client.request(kind=2)
            value=status['result']
            print(json.dumps(dict(flags=hex(value&0xffffffff),pressed=hex((value>>32)&0xffffffff),pcm_frames=(value>>64)&0xffffffff,
                bad_packets=(value>>112)&65535,underruns=(value>>96)&65535,response=status),indent=2))
            if value&1:
                print(json.dumps({hex(a):client.read(a) for a in (4,0x34,0x38,0x3c,0x40,0x44,0x48,0x4c,0x50,0x54,0x58,0x5c,0x60)},indent=2))
        elif args.action=='read':print(hex(client.read(args.address)))
        elif args.action=='panic':
            client.request(0xa7,words=[5,UNITY//2]);client.request(0xc3,words=[3])
        elif args.action=='play':
            if client.read(4)<0x00010005:raise RuntimeError('MIDI note/velocity metadata requires engine ABI 0x00010005 or newer')
            note_id=(client.state['next_sequence']+1)&0x7fffffff
            phase=round(440*2**((args.note-69)/12)*(1<<32)/RATE)
            client.request(0xa4,args.slot,[note_id,phase,UNITY,UNITY//2,0x80000000|args.velocity<<7|args.note])
            try:time.sleep(args.seconds)
            finally:client.request(0xa5,words=[note_id])
        elif args.action in ('upload','bank'):
            is_fx=args.action=='upload' and args.fx
            if args.action=='bank':
                data=(ENGINE_ROOT/'assets/fm1/factory.vmem').read_bytes()
                import hashlib
                from dx7_bank import FACTORY_SHA
                if hashlib.sha256(data).hexdigest()!=FACTORY_SHA:raise ValueError('FM1 bank source integrity failure')
                config=convert(data[args.program*128:(args.program+1)*128],args.program)
                previous=client.state.get('slot_revisions',{}).get(str(args.slot),1)
                config['revision']=args.revision or max(int(time.time()),previous+1)
            else:config=json.loads(args.file.read_text(encoding='utf-8'))
            program=compile_fx(config) if is_fx else compile_patch(config,slot=args.slot)
            required=int(program.get('abi','0x00010004'),16)
            if client.read(4)<required:raise RuntimeError(f'Program requires engine ABI {required:#010x}; no patch data uploaded')
            if is_fx:
                maximum=((client.read(0x50)+1)<<16)-1
                for command in program['commands']:
                    if command['opcode']==0xc0 and max(command['words'][:2])>maximum:
                        raise ValueError(f'Delay exceeds board capacity {maximum/65536/RATE*1000:.3f} ms; no settings uploaded')
            for command in program['commands']:client.request(command['opcode'],command['address'],command['words'])
            if not is_fx:
                client.state.setdefault('slot_revisions',{})[str(args.slot)]=config.get('revision',1)
                client.save()
            print(f"Uploaded {program.get('name','FX')}: {len(program['commands'])} commands")


if __name__=='__main__':main()
