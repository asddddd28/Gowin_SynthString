"""在既有协议 4 固件上逐一试听五类音色，结束时恢复 App 导出的参数。"""
from pathlib import Path
import datetime,json,sys,time

ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'keyboard-latency'))
from live_latency import Board
from prepare_library import APP,encode

def main():
    library=json.loads((APP/'src/data/foundation-library.json').read_text(encoding='utf-8'))
    original=json.loads((ROOT/'baseline/User-bank-before.json').read_text(encoding='utf-8'))['keys']
    board=Board('COM4');changed=set();volume=6
    result=dict(passed=False,time=datetime.datetime.now().isoformat(),presets=[],chords=[],
        scope='Live FPGA telemetry; tone descriptions require listening, no analog audio capture')
    def poll(seconds):
        until=time.monotonic()+seconds;heartbeat=time.monotonic()
        while time.monotonic()<until:
            board.poll(min(.1,max(.001,until-time.monotonic())))
            assert not board.records[-1]['pressed'],'Physical key pressed during automated test'
            if time.monotonic()-heartbeat>=.4:board.send(7);heartbeat=time.monotonic()
    def apply(key,patch):
        changed.add(key);board.command(1,key,bytes.fromhex(encode(patch)))
    try:
        board.poll(.5);assert board.records,'No protocol-4 data'
        initial=board.records[-1];result['initial']=initial;volume=initial['volume']
        assert initial['pressed']==0,'Release physical keys before this test'
        board.command(4);board.command(6,payload=bytes([3]));poll(2)
        key=12
        for entry in library['presets']:
            patch=entry['patch'];apply(key,patch);before=board.records[-1];offset=len(board.records)
            board.command(2,key,bytes([patch['velocity']]))
            poll(1.7 if entry['category']=='Pad' else .45)
            sounded=board.records[-1];l=sounded['latency']
            assert l['remote_records']==before['latency']['remote_records']+1,(entry['id'],l)
            assert l['key']==key and l['flags']&1==0,(entry['id'],l)
            assert sounded['nonzero']>before['nonzero'],entry['id']
            board.command(3,key);poll(patch['amp']['release']/1000+.18)
            assert board.records[-1]['active']==0,(entry['id'],'release did not finish')
            result['presets'].append(dict(id=entry['id'],category=entry['category'],name=entry['name'],
                note=patch['note'],latency_us=l['total']/50,
                nonzero_frames=sounded['nonzero']-before['nonzero'],
                sampled_peak=max(r['output_peak'] for r in board.records[offset:]),
                release_complete=True))
            print('PASS',entry['id'],'latency_us',l['total']/50,flush=True)
        by_id={p['id']:p['patch'] for p in library['presets']}
        for name,preset,notes in [('C_major','chord_ep',[60,64,67]),('C_minor','chord_pad',[60,63,67])]:
            keys=[26,27,28]
            for key,note in zip(keys,notes):apply(key,{**by_id[preset],'note':note})
            before=board.records[-1]['latency']['remote_records']
            for key in keys:ack=board.send(2,key,bytes([80]))
            board.acknowledge(ack);poll(.4 if preset=='chord_ep' else 1)
            sounding=board.records[-1]
            assert sounding['active']==3 and sounding['latency']['remote_records']==before+3,sounding
            for key in keys:ack=board.send(3,key)
            board.acknowledge(ack);poll(by_id[preset]['amp']['release']/1000+.2)
            assert board.records[-1]['active']==0
            result['chords'].append(dict(name=name,notes=notes,active_voices=sounding['active'],peak=sounding['output_peak'],release_complete=True))
            print('PASS chord',name,flush=True)
        assert board.bad==0,f'{board.bad} incomplete or invalid telemetry packets'
        assert board.records[-1]['clips']==initial['clips'],'Clip counter increased'
        result.update(passed=True,bad_packets=board.bad,clip_increase=0,cycles=385)
    finally:
        errors=[]
        try:
            board.command(4)
            for key in sorted(changed):
                try:board.command(1,key,bytes.fromhex(encode(original[key])))
                except Exception as error:errors.append(f'key {key}: {error}')
            board.command(6,payload=bytes([volume]))
        except Exception as error:errors.append(str(error))
        finally:board.port.close()
        result.update(restored_app_profiles=not errors,restoration_errors=errors,
            restoration_note='Restored exported App parameters, not FPGA profile readback',
            records=board.records,commands=board.commands,packets=len(board.records),bad_packets=board.bad)
        (ROOT/'reports/live_foundations.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        (ROOT/'reports/live_serial.bin').write_bytes(board.raw)
    assert result['passed'] and result['restored_app_profiles']
    print('PASS 16 presets + two triads; exported profiles restored',flush=True)

if __name__=='__main__':main()
