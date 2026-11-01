"""单指连续轨迹划弦；初次触摸、悬停、丢帧后的新轨迹均不拨弦。"""
from collections import deque
from dataclasses import dataclass

NOTE_NAMES = ('E2', 'A2', 'D3', 'G3', 'B3', 'E4')
MIDI_NOTES = (40, 45, 50, 55, 59, 64)
FREQUENCIES = tuple(440 * 2 ** ((note-69)/12) for note in MIDI_NOTES)
STRING_X = (.25, .50, .75)
STRING_Y = (.06, .94)


def display_point(point, mapping):
    if point is None:
        return None
    x, y = point
    return mapping.apply((x*6+.5)/7, (y*4+.5)/5)


@dataclass(frozen=True)
class Pluck:
    string: int
    board: int
    direction: int
    time: float
    delay: float


class StrumDetector:
    def __init__(self):
        self.previous = [None, None]
        self.sides = [[0]*3 for _ in range(2)]
        self.last_hits = [float('-inf')]*6
        self.counts = [0]*6
        self.events = deque(maxlen=64)
        self.hysteresis = .035
        self.cooldown = .075

    def reset(self, board=None):
        for i in range(2) if board is None else (board,):
            self.previous[i] = None
            self.sides[i] = [0]*3

    def expire(self, now):
        for board, previous in enumerate(self.previous):
            if previous and now-previous[2] > .25:
                self.reset(board)

    def side(self, x, line):
        return -1 if x < line-self.hysteresis else 1 if x > line+self.hysteresis else 0

    def update(self, board, point, sequence, now, swap_boards=False):
        if point is None or not STRING_Y[0] <= point[1] <= STRING_Y[1]:
            self.reset(board)
            return []
        x, y = point
        previous = self.previous[board]
        if previous and sequence == previous[3]:
            return []
        current = (x, y, now, sequence)
        if (previous is None or (sequence-previous[3]) & 65535 != 1
                or not 0 < now-previous[2] <= .25):
            self.previous[board] = current
            self.sides[board] = [self.side(x, line) for line in STRING_X]
            return []
        physical_side = 1-board if swap_boards else board
        crossings = []
        for slot, line in enumerate(STRING_X):
            side = self.side(x, line)
            old_side = self.sides[board][slot]
            if side:
                self.sides[board][slot] = side
                string = physical_side*3+slot
                if old_side and side != old_side and now-self.last_hits[string] >= self.cooldown:
                    fraction = max(0, min(1, (line-previous[0])/(x-previous[0]))) if x != previous[0] else 0
                    crossings.append((fraction, string, side))
        self.previous[board] = current
        crossings.sort()
        result = []
        for fraction, string, direction in crossings:
            delay = (fraction-crossings[0][0])*min(.08, now-previous[2])
            event = Pluck(string, board, direction, now, delay)
            self.last_hits[string] = now
            self.counts[string] += 1
            self.events.append(event)
            result.append(event)
        return result

    def snapshot(self):
        return dict(counts=self.counts[:], total=sum(self.counts),
                    events=[dict(**e.__dict__, note=NOTE_NAMES[e.string]) for e in self.events])
