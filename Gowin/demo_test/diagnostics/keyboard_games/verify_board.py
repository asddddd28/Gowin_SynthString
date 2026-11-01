"""Actual UART acceptance including autonomous operation while the handle is closed."""
import argparse,json,sys,time,hashlib
from dataclasses import asdict
from pathlib import Path
root=Path(__file__).resolve().parent
sys.path.insert(0,str(root.parents[1]/'desktop'))
import serial
from board_protocol import command,calibration_commands,QUERY,GAME_START
from keyboard_core import StreamParser,Profile

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--profile',type=Path,required=True);args=ap.parse_args()
    profile=Profile.load(args.profile);parser=StreamParser();replies=[];games=[];seq=80
    report=dict(passed=False,profile=profile.name,profile_sha256=hashlib.sha256(args.profile.read_bytes()).hexdigest(),commands=[],port='COM4',baud=115200)
    stream=serial.Serial(port=None,baudrate=115200,timeout=.03,write_timeout=1);stream.dtr=False;stream.rts=False;stream.port='COM4'
    out=root/'reports';binary=(out/'hardware_serial.bin').open('wb')
    def receive(duration):
        deadline=time.monotonic()+duration
        while time.monotonic()<deadline:
            data=stream.read(max(1,stream.in_waiting));binary.write(data);parser.feed(data)
            while parser.statuses:replies.append(parser.statuses.popleft())
            while parser.game_statuses:
                status=parser.game_statuses.popleft();games.append((time.monotonic(),status))
    def exchange(fields,expected=0,repeat=None):
        nonlocal seq
        current=seq if repeat is None else repeat
        if repeat is None:seq=(seq+1)%255
        start=len(replies);stream.write(command(current,**fields));stream.flush()
        deadline=time.monotonic()+1.5
        while time.monotonic()<deadline:
            receive(.02)
            matches=[x for x in replies[start:] if x.seq==current and x.result!=128]
            if matches:
                status=matches[-1];report['commands'].append(dict(fields=fields,status=asdict(status)))
                assert status.result==expected,(status,expected)
                return status
        raise RuntimeError('ACK timeout')
    try:
        stream.open();receive(2);parser=StreamParser();replies.clear();games.clear()
        state=exchange(dict(code=QUERY));assert not state.configured
        exchange(dict(code=GAME_START,key=1),2)
        for fields in calibration_commands(profile):state=exchange(fields)
        assert state.configured and state.generation==1
        exchange(dict(code=GAME_START,key=4),3)
        started=time.monotonic();exchange(dict(code=GAME_START,key=2));exchange(dict(code=GAME_START,key=2),repeat=(seq-1)%255)
        deadline=time.monotonic()+4
        while (not games or games[-1][1].phase!=2) and time.monotonic()<deadline:receive(.05)
        before=games[-1][1];assert before.game==2 and before.phase==2 and before.epoch==1
        report['countdown_observed_s']=time.monotonic()-started
        # No serial writes or host game logic during this interval.
        stream.close();disconnected=time.monotonic();time.sleep(5);stream.open();receive(2)
        after=games[-1][1]
        assert after.game==2 and after.phase==2 and after.epoch==before.epoch
        assert 4<=before.seconds-after.seconds<=10,(before,after)
        state=exchange(dict(code=QUERY));assert state.mode==5 and state.generation==1
        report.update(passed=True,autonomous_before=asdict(before),autonomous_after=asdict(after),closed_handle_interval_s=5,
                      elapsed_including_reopen_s=time.monotonic()-disconnected,records=parser.records,
                      status_crc_errors=parser.status_errors,game_crc_errors=parser.game_errors,
                      # Ordering across handle closure is deliberately discontinuous.
                      sequence_errors_across_deliberate_disconnect=parser.sequence_errors,
                      game_frames=len(games),final_board=asdict(state),final_game=asdict(games[-1][1]))
        assert parser.status_errors==0 and parser.game_errors==0
    except Exception as exc:report['error']=repr(exc);raise
    finally:
        stream.close();binary.close();report['serial_closed']=True
        (out/'hardware_serial.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='commands'},ensure_ascii=False))

if __name__=='__main__':main()
