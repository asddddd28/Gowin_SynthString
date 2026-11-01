"""双 MPR121 原始帧校验、时效性及单指位置估算。"""
from dataclasses import asdict, dataclass
import json
import os
import re

FRAME_SIZE = 100
FRAME = re.compile(rb'T([12])([0-9A-F]{4})(5[A-D])([0-9A-F]{2})([0-7])([0-9A-F]{84})\*([0-9A-F]{2})\r\n')
ERRORS = {0: '正常采集', 1: '地址未应答', 2: '总线超时', 3: '配置未应答',
          4: '配置回读不符', 5: '采样未应答', 6: '过流停止', 7: '初始化中'}


@dataclass(frozen=True)
class TouchpadMapping:
    swap_boards: bool = False
    transpose: bool = True
    flip_x: bool = False
    flip_y: bool = False

    def __post_init__(self):
        if any(type(value) is not bool for value in asdict(self).values()):
            raise ValueError('触摸板方向选项必须为布尔值')

    def apply(self, x, y):
        # 每块板局部坐标沿左上到右下对角线镜像，再应用显示轴翻转。
        if self.transpose:
            x, y = y, x
        return (1-x if self.flip_x else x, 1-y if self.flip_y else y)

    @classmethod
    def load(cls, path):
        data = json.loads(path.read_text(encoding='utf8'))
        if not isinstance(data, dict) or set(data) != {'swap_boards', 'transpose', 'flip_x', 'flip_y'}:
            raise ValueError('触摸板方向配置字段不完整')
        return cls(**data)

    def save(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix('.tmp')
        temporary.write_text(json.dumps(asdict(self), ensure_ascii=False, indent=2), encoding='utf8')
        os.replace(temporary, path)


def crc8(data):
    value = 0
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = ((value << 1) ^ (7 if value & 128 else 0)) & 255
    return value


@dataclass(frozen=True)
class TouchpadRecord:
    board: int
    sequence: int
    address: int
    error: int
    lines: int
    raw: bytes

    @property
    def mask(self):
        return int.from_bytes(self.raw[:2], 'little') & 4095

    @property
    def fault(self):
        return bool(self.raw[1] & 128 or self.raw[2] or self.raw[3] & 0xcf)

    @property
    def filtered(self):
        return [int.from_bytes(self.raw[4 + 2*i:6 + 2*i], 'little') for i in range(12)]

    @property
    def baseline(self):
        return [n * 4 for n in self.raw[30:42]]

    @property
    def delta(self):
        return [b - f for b, f in zip(self.baseline, self.filtered)]


def decode_touchpad(packet):
    m = FRAME.fullmatch(packet)
    if not m or crc8(packet[:95]) != int(m[7], 16):
        raise ValueError('触摸板帧格式或 CRC 错误')
    board, sequence, address, error, lines = (int(v, 16) for v in m.groups()[:5])
    record = TouchpadRecord(board, sequence, address, error, lines, bytes.fromhex(m[6].decode()))
    if error not in ERRORS or (error == 0 and any(v > 1023 for v in record.filtered)):
        raise ValueError('触摸板数据超出范围')
    return record


def centroid(values, mask, first):
    # 连续电极上的差值作权重；相离的触点不强行合成一个位置。
    selected = [i for i in range(len(values)) if mask & (1 << (i + first))]
    if not selected or selected[-1] - selected[0] + 1 != len(selected):
        return None
    weights = [max(1, values[i]) for i in selected]
    return sum(i * w for i, w in zip(selected, weights)) / sum(weights) / (len(values) - 1)


class TouchpadState:
    def __init__(self):
        self.records = [None, None]
        self.received = [float('-inf')] * 2
        self.advanced = [float('-inf')] * 2
        self.total = [0, 0]

    def update(self, record, now):
        i = record.board - 1
        old = self.records[i]
        if old is None or record.sequence != old.sequence:
            self.advanced[i] = now
        self.records[i] = record
        self.received[i] = now
        self.total[i] += 1

    def invalidate(self):
        self.received = [float('-inf')] * 2
        self.advanced = [float('-inf')] * 2

    def fresh(self, i, now):
        r = self.records[i]
        return bool(r and r.error == 0 and 0 <= now-self.received[i] <= .6 and 0 <= now-self.advanced[i] <= .6)

    def position(self, i, now):
        r = self.records[i]
        if not self.fresh(i, now) or r.fault:
            return None
        y = centroid(r.delta[:5], r.mask, 0)
        x = centroid(r.delta[5:], r.mask, 5)
        return (x, y) if x is not None and y is not None else None

    def snapshot(self, now):
        return [dict(board=i+1, fresh=self.fresh(i, now), records=self.total[i],
                     position=self.position(i, now),
                     fpga=dict(sequence=r.sequence, address=r.address, error=r.error,
                               lines=r.lines, mask=r.mask, fault=r.fault, filtered=r.filtered,
                               baseline=r.baseline, delta=r.delta, raw=r.raw.hex()) if r else None)
                for i, r in enumerate(self.records)]
