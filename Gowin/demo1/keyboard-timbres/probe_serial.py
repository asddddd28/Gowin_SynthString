"""区分静默接收与心跳发送时的串口丢字节，记录 Windows 串口错误。"""
from pathlib import Path
import ctypes,json,sys,time
import serial.serialwin32

ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'keyboard-latency'))
from live_latency import Board

def main():
    errors=[];reads=[];writes=[];started=time.monotonic()
    original=serial.serialwin32.win32.ClearCommError
    def observe(handle,flags,status):
        result=original(handle,flags,status)
        value=ctypes.cast(flags,ctypes.POINTER(ctypes.c_ulong)).contents.value
        if value:errors.append(dict(t=time.monotonic()-started,flags=value))
        return result
    serial.serialwin32.win32.ClearCommError=observe
    board=Board('COM4')
    read=board.port.read;write=board.port.write
    def record_read(size):
        data=read(size)
        if data:reads.append(dict(t=time.monotonic()-started,offset=len(board.raw),size=len(data)))
        return data
    def record_write(data):
        writes.append(dict(t=time.monotonic()-started,hex=data.hex()))
        return write(data)
    board.port.read=record_read;board.port.write=record_write
    phases=[]
    try:
        for name,heartbeat in [('receive_only',False),('with_heartbeat',True)]:
            end=time.monotonic()+16;due=0;before=board.bad;count=len(board.records)
            while time.monotonic()<end:
                board.poll(.05)
                if heartbeat and time.monotonic()>due:board.send(7);due=time.monotonic()+.4
            phases.append(dict(name=name,packets=len(board.records)-count,bad=board.bad-before))
            print(phases[-1],flush=True)
    finally:
        board.port.close();serial.serialwin32.win32.ClearCommError=original
        (ROOT/'reports/serial_probe.json').write_text(json.dumps(dict(phases=phases,windows_errors=errors,reads=reads,writes=writes),indent=2),encoding='utf-8')
        (ROOT/'reports/serial_probe.bin').write_bytes(board.raw)
    print('Windows errors',errors,flush=True)

if __name__=='__main__':main()
