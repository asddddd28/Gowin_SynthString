"""Semantic oracle for the local monitor; no external services or board access."""
from dataclasses import dataclass, field

RATE = 50_000_000 / 1024

def key_row(slot, note, velocity):
    if not (0 <= slot < 4 and 0 <= note < 128 and 1 <= velocity < 128):
        raise ValueError('invalid key')
    phase = round(440 * 2 ** ((note - 69) / 12) * 2**32 / RATE)
    return phase | ((slot | note << 2 | velocity << 9) << 32)

def pcm16(q26):
    rounded = (abs(q26) + 1024) >> 11
    return max(-32768, min(32767, -rounded if q26 < 0 else rounded))

@dataclass
class Monitor:
    captured: list = field(default_factory=list)
    busy: bool = False
    ready: bool = False
    generation: int = 0
    pending: tuple | None = None
    target: int | None = None
    latency: int = 0
    maximum: int = 0
    observations: int = 0

    def trigger(self):
        if self.busy:
            raise ValueError('busy')
        self.captured = []
        self.busy, self.ready = True, False
        self.generation = (self.generation + 1) & 65535

    def start(self, key, clock):
        if self.pending is None:
            self.pending, self.target = (key, clock), None

    def commit(self, key, frame, success=True):
        if self.pending and self.pending[0] == key:
            if success:
                self.target = frame
            else:
                self.pending = None

    def sample(self, value, frame, clock):
        if self.busy:
            self.captured.append(pcm16(value))
            if len(self.captured) == 512:
                self.busy, self.ready = False, True
        if self.pending and self.target == frame:
            self.latency = (clock - self.pending[1]) & 0xffffffff
            self.maximum = max(self.maximum, self.latency)
            self.observations += 1
            self.pending = None

def verify():
    assert pcm16(1 << 26) == 32767 and pcm16(-(1 << 26)) == -32768
    assert key_row(3, 72, 127) != key_row(0, 48, 100)
    m = Monitor(); m.trigger(); m.start(3, 100); m.commit(3, 10)
    for i in range(512):
        m.sample((i-256)*2048, i, 120+i*1024)
    assert m.ready and len(m.captured) == 512 and m.captured[0] == -256
    assert m.latency == 10260 and m.observations == 1
    before = m.captured[:]; m.sample(0, 512, 600000); assert before == m.captured
    m.start(1, 100); m.start(2, 101); m.commit(2, 1); assert m.target is None
    m.commit(1, 1, False); assert m.pending is None
    print('PASS studio_monitor_model mapping/capture/quantization/latency')

if __name__ == '__main__':
    verify()
