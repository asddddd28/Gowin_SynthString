"""Passive EncoderDebug telemetry and wrap-safe, session-relative positions."""
from collections import deque
from dataclasses import dataclass
import re

STALE_SECONDS = 0.6
EDGES_PER_DETENT = 4
# Observed left-to-right order. E4 is the remaining, not yet responsive channel.
PHYSICAL_ORDER = (5, 4, 3, 2, 1)
FRAME_SIZE = 34
FRAME = re.compile(rb'E([1-5]) A([0-3]) F([0-3]) Q([0-9A-F]{4}) P([0-9A-F]{4}) N([0-9A-F]{4}) X([0-9A-F]{4})\r\n')


@dataclass(frozen=True)
class EncoderRecord:
    channel: int
    raw: int
    filtered: int
    q: int
    positive: int
    negative: int
    invalid: int


def decode_encoder(packet):
    match = FRAME.fullmatch(packet)
    if not match:
        raise ValueError('编码器帧格式错误')
    channel, raw, filtered = (int(match[i]) for i in (1, 2, 3))
    q, positive, negative, invalid = (int(match[i], 16) for i in (4, 5, 6, 7))
    if q != (positive - negative) & 0xffff:
        raise ValueError('编码器 Q/P/N 计数不一致')
    return EncoderRecord(channel, raw, filtered, q if q < 32768 else q - 65536,
                         positive, negative, invalid)


class EncoderChannel:
    def __init__(self):
        self.record = None
        self.updated = self.moved = float('-inf')
        self.edges = self.positive = self.negative = self.invalid = 0
        self.discontinuities = 0
        self.motion = '静止'
        self.samples = 0

    def fresh(self, now):
        return self.record is not None and 0 <= now - self.updated <= STALE_SECONDS

    def direction(self, now):
        if not self.fresh(now):
            return '等待数据' if self.record is None else '数据超时'
        return self.motion if now - self.moved <= STALE_SECONDS else '静止'

    def update(self, record, now):
        previous, elapsed = self.record, now - self.updated
        self.record, self.updated = record, now
        self.samples += 1
        if previous is None:
            return None
        # Modulo subtraction handles both unsigned cumulative counters and signed Q wrap.
        dp = (record.positive - previous.positive) & 0xffff
        dn = (record.negative - previous.negative) & 0xffff
        dx = (record.invalid - previous.invalid) & 0xffff
        # A long gap or implausible counter jump is not evidence of physical rotation.
        # Rebase and explicitly mark it; telemetry has no boot/session identifier.
        if elapsed < 0 or elapsed > STALE_SECONDS or max(dp, dn, dx) > max(256, elapsed * 2000):
            self.discontinuities += 1
            self.moved = float('-inf')
            return '数据中断 / 计数重建基准'
        self.edges += dp - dn
        self.positive += dp
        self.negative += dn
        self.invalid += dx
        if dp or dn:
            self.motion = '顺时针 ↻' if dp > dn else '逆时针 ↺' if dn > dp else '往返 / 抖动'
            self.moved = now
        if dp or dn or dx:
            return f'+{dp} / −{dn} 边沿' + (f' · 非法跳变 +{dx}' if dx else '')
        return None


class EncoderState:
    def __init__(self):
        self.channels = [EncoderChannel() for _ in range(5)]
        self.events = deque(maxlen=12)

    def update(self, record, now):
        event = self.channels[record.channel - 1].update(record, now)
        if event:
            self.events.append((now, record.channel, event))

    def zero(self):
        """Zero display-relative positions only; preserve FPGA and diagnostic counters."""
        for channel in self.channels:
            channel.edges = 0

    def invalidate(self):
        for channel in self.channels:
            channel.updated = channel.moved = float('-inf')

    def snapshot(self, now):
        return [dict(channel=i + 1, physical=PHYSICAL_ORDER.index(i + 1) + 1,
                     fresh=c.fresh(now), direction=c.direction(now),
                     edges=c.edges, detents=c.edges / EDGES_PER_DETENT,
                     positive=c.positive, negative=c.negative, invalid=c.invalid,
                     discontinuities=c.discontinuities, samples=c.samples,
                     fpga=c.record.__dict__ if c.record else None)
                for i, c in enumerate(self.channels)]
