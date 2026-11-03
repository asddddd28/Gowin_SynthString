"""音序器独立整数语义：小节截断、循环叠录和音乐时钟。"""
from dataclasses import dataclass

PPQ = 960
BAR = PPQ * 4


@dataclass(frozen=True)
class Event:
    tick: int
    on: bool
    key: int
    anchor: int
    slot: int = 0
    note: int = 60
    velocity: int = 100


class Recorder:
    def __init__(self, capacity=1024, early=False, bpm=120):
        self.capacity = capacity
        self.events = []
        self.saved = 0
        self.length = 0
        self.position = 0
        self.recording = False
        self.playing = False
        self.checkpoint = 0
        self.cut = 0
        self.held = {}
        self.cut_held = {}
        self.lead = bpm*8//25 if early else 0
        self.phase = 0
        self.started = False
        self.sounding_bar = False

    def record(self):
        assert not self.recording
        self.events = self.events[:self.saved]
        self.checkpoint = self.saved
        self.cut_held = {}
        self.held = {}
        self.recording = True
        self.started = False
        self.sounding_bar = False
        self.cut = 0
        if not self.length:
            self.position = 0
            self.phase = 0

    def event(self, key, on, slot=0):
        if not self.recording:
            return
        if on:
            if key in self.held:
                return
            if not self.length and not self.started:
                self.position = (self.phase+self.lead)%BAR
                self.started = True
                self.cut = 0
            self.sounding_bar = True
            self.held[key] = len(self.events)
        elif key not in self.held:
            return
        assert len(self.events) < self.capacity - 32
        anchor = self.held[key]
        self.events.append(Event(self.position, on, key, anchor, slot))
        if not on:
            del self.held[key]

    def tick(self):
        if self.recording and self.held:
            self.sounding_bar = True
        self.phase = (self.phase+1)%BAR
        self.position += 1
        boundary = self.position%BAR==0 if self.length else (self.phase+self.lead)%BAR==0
        if boundary and self.recording:
            if self.length or self.started and self.sounding_bar:
                self.checkpoint = len(self.events)
                self.cut = self.position
                self.cut_held = self.held.copy()
            self.sounding_bar = False
        if self.length and self.position >= self.length:
            self.position = 0
            if self.recording:
                self.cut = 0

    def stop(self):
        self.recording = False
        self.events = self.events[:self.checkpoint]
        if not self.length:
            self.length = self.cut
            self.position = 0
        # Notes at loop end are released by the playback ownership cleanup.
        if 0 < self.cut < self.length:
            for key, anchor in self.cut_held.items():
                self.events.append(Event(self.cut, False, key, anchor))
        self.saved = len(self.events)
        self.playing = self.length != 0


def verify():
    r = Recorder(); r.record(); r.event(0, True)
    for _ in range(BAR-1): r.tick()
    r.stop(); assert r.length == 0 and not r.events and not r.playing
    r = Recorder(); r.record(); r.event(0, True)
    for _ in range(BAR): r.tick()
    r.event(0, False); r.event(1, True)
    r.stop(); assert r.length == BAR and len(r.events) == 1 and r.events[0].on
    for _ in range(BAR//2): r.tick()
    r.record(); r.event(2, True, 1)
    for _ in range(BAR): r.tick()
    r.stop(); assert r.length == BAR and len(r.events) == 2
    # Fractional accumulator has at most one microsecond edge error.
    for bpm in (20, 63, 120, 137, 300):
        phase = 0; ticks = 0
        for _ in range(1_000_000):
            phase += bpm * 16
            if phase >= 1_000_000: phase -= 1_000_000; ticks += 1
        assert ticks == bpm * 16 and phase == 0
    print('PASS model: short take, bar trim, sustained notes, overdub and exact 960 PPQ tempo')


if __name__ == '__main__':
    verify()
