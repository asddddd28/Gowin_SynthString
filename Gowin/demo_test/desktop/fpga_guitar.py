"""FPGA G1 事件协议；电脑仅映射弦号和播放，不做跨弦判定。"""
from collections import deque
from dataclasses import dataclass
import re
import threading
from guitar_core import Pluck, NOTE_NAMES
from touchpad_core import TouchpadMapping, crc8

FRAME_SIZE = 37
FRAME = re.compile(rb'G1([12])([0-9A-F]{4})([0-9A-F]{4})([0-9A-F]{8})([0-9A-F])([0-9A-F]{2})([0-9A-F]{3})([0-9A-F]{3})([0-9A-F]{4})\*([0-9A-F]{2})\r\n')

@dataclass(frozen=True)
class GuitarRecord:
    board: int
    packet: int
    sample: int
    milliseconds: int
    flags: int
    mask: int
    x: int
    y: int
    dropped: int

def decode_guitar(packet):
    match=FRAME.fullmatch(packet)
    if not match or crc8(packet[:32])!=int(match[10],16):
        raise ValueError('FPGA 吉他事件格式或 CRC 错误')
    record=GuitarRecord(*(int(v,16) for v in match.groups()[:9]))
    if record.mask>63 or record.x>1023 or record.y>1023 or (record.mask and record.flags&3!=3):
        raise ValueError('FPGA 吉他事件字段无效')
    return record

class GuitarStream:
    """仅在串口线程使用；有界按行解析，T 遥测不参与拨弦判断。"""
    def __init__(self, callback):
        self.buffer=bytearray();self.callback=callback;self.errors=0
    def feed(self,data,now):
        self.buffer.extend(data)
        while b'\n' in self.buffer:
            end=self.buffer.index(10)+1
            line=bytes(self.buffer[:end]);del self.buffer[:end]
            if not line.startswith(b'G1'): continue
            try: record=decode_guitar(line)
            except ValueError: self.errors+=1;continue
            self.callback(record,now)
        if len(self.buffer)>512:
            self.buffer.clear();self.errors+=1

class FpgaGuitarState:
    def __init__(self,audio):
        self.audio=audio;self.lock=threading.RLock()
        self.enabled=False;self.mapping=TouchpadMapping()
        self.counts=[0]*6;self.last_hits=[float('-inf')]*6;self.events=deque(maxlen=64)
        self.records=[None,None];self.received=[float('-inf')]*2
        self.anchors=[None,None];self.rates=[0.,0.];self.packet_gaps=0;self.stale=0
    def configure(self,enabled,mapping):
        with self.lock:
            self.enabled=enabled;self.mapping=mapping
    def reset(self,board=None):
        # 止音不改变板上轨迹。清除连接状态由 reconnect 专门执行。
        self.audio.silence()
    def reconnect(self):
        with self.lock:
            self.enabled=False;self.records=[None,None];self.anchors=[None,None]
            self.received=[float('-inf')]*2;self.rates=[0.,0.]
    def expire(self,now):
        pass
    def receive(self,r,now):
        with self.lock:
            board=r.board-1;old=self.records[board]
            if old and r.packet==old.packet: return
            if old and (r.packet-old.packet)&65535!=1: self.packet_gaps+=1
            tick_delta=(r.milliseconds-old.milliseconds)&0xffffffff if old else 0
            if old and 0<tick_delta<1000:
                self.rates[board]=((r.sample-old.sample)&65535)*1000/tick_delta
            if old and tick_delta>0x7fffffff:
                self.anchors[board]=None
                old=None
            self.records[board]=r;self.received[board]=now
            anchor=self.anchors[board]
            if anchor is None:
                self.anchors[board]=(r.milliseconds,now);return
            expected=anchor[1]+((r.milliseconds-anchor[0])&0xffffffff)/1000
            if now<expected: self.anchors[board]=(r.milliseconds,now)
            if now-expected>.15:
                self.stale+=bool(r.mask);return
            if not self.enabled or not self.audio.ready or r.flags&3!=3: return
            mapping=self.mapping
            # 默认transpose为真，G1 X已经是原始五电极行轴；取消transpose时选硬件Y事件。
            axis=0 if mapping.transpose else 1
            mask=(r.mask>>(axis*3))&7
            direction=1 if r.flags&(4<<axis) else -1
            if mapping.flip_x: direction=-direction
            slots=[2-i if mapping.flip_x else i for i in range(3) if mask&(1<<i)]
            slots.sort(reverse=direction<0)
            side=1-board if mapping.swap_boards else board
            # 一次跨多弦按方向排列，最多增加3ms音频间隔；不重新分析位置。
            for index,slot in enumerate(slots):
                string=side*3+slot
                event=Pluck(string,board,direction,now,index*.0015)
                self.counts[string]+=1;self.last_hits[string]=now;self.events.append(event)
                self.audio.pluck(event)
    def snapshot(self):
        with self.lock:
            return dict(source='FPGA G1',counts=self.counts[:],total=sum(self.counts),
                events=[dict(**e.__dict__,note=NOTE_NAMES[e.string]) for e in self.events],
                boards=[r.__dict__ if r else None for r in self.records],
                sample_hz=self.rates[:],packet_gaps=self.packet_gaps,stale_events=self.stale)
