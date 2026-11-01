"""五路数字摇杆遥测；比较器只提供低、中、高三个区域。"""
import re
import json
import os
from dataclasses import asdict, dataclass
from collections import deque

FRAME_SIZE = 21
FRAME = re.compile(rb'J([0-9A-F]{4}) R([01][0-9A-F]) F([01][0-9A-F]) P([0-9A-F]{4})\r\n')
NAMES = ('XH', 'XL', 'YH', 'YL', 'SW')


@dataclass(frozen=True)
class JoystickMapping:
    swap: bool = False
    flip_x: bool = False
    flip_y: bool = False

    def __post_init__(self):
        if any(type(value) is not bool for value in asdict(self).values()):
            raise ValueError('摇杆映射选项必须为布尔值')

    def apply(self, x, y):
        if self.swap:
            x, y = y, x
        return (-x if x is not None and self.flip_x else x,
                -y if y is not None and self.flip_y else y)

    @classmethod
    def load(cls, path):
        data = json.loads(path.read_text(encoding='utf8'))
        if not isinstance(data, dict) or set(data) != {'swap', 'flip_x', 'flip_y'}:
            raise ValueError('摇杆映射配置字段不完整')
        return cls(**data)

    def save(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix('.tmp')
        temporary.write_text(json.dumps(asdict(self), ensure_ascii=False, indent=2), encoding='utf8')
        os.replace(temporary, path)


@dataclass(frozen=True)
class JoystickRecord:
    sequence: int
    raw: int
    filtered: int
    presses: int


def decode_joystick(packet):
    match = FRAME.fullmatch(packet)
    if match is None:
        raise ValueError('摇杆帧格式错误')
    return JoystickRecord(*(int(value, 16) for value in match.groups()))


def axis_region(bits):
    # 图中 H 阈值为2V，L阈值为3V，均接运放反相端。
    # 参数 bit0=H、bit1=L；01二进制表示两阈值之间。
    return {0: -1, 1: 0, 3: 1}.get(bits)


class JoystickState:
    def __init__(self):
        self.record = None
        self.updated = float('-inf')
        self.records = self.changes = 0
        self.transitions = deque(maxlen=128)

    def update(self, record, now):
        if self.record is None or (record.raw, record.filtered, record.presses) != (self.record.raw, self.record.filtered, self.record.presses):
            self.transitions.append(dict(received_monotonic=now, **record.__dict__))
        if self.record and record.filtered != self.record.filtered:
            self.changes += 1
        self.record, self.updated = record, now
        self.records += 1

    def fresh(self, now):
        return self.record is not None and 0 <= now - self.updated <= .6

    def snapshot(self, now):
        r = self.record
        return dict(fresh=self.fresh(now), records=self.records, changes=self.changes,
                    recent_transitions=list(self.transitions),
                    fpga=r.__dict__ if r else None,
                    x=axis_region(r.filtered & 3) if r else None,
                    y=axis_region((r.filtered >> 2) & 3) if r else None,
                    pressed=not bool(r.filtered & 16) if r and self.fresh(now) else False)
