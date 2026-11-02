"""Independent switch semantics and the B1 telemetry contract."""
from dataclasses import dataclass

@dataclass
class Switch:
    limit: int
    level: int = 0
    candidate: int = 0
    presses: int = 0
    releases: int = 0

    def sample(self, raw):
        if raw == self.level:
            self.candidate = 0
        elif self.candidate == self.limit - 1:
            self.level = raw
            self.candidate = 0
            if raw:
                self.presses = (self.presses + 1) & 65535
            else:
                self.releases = (self.releases + 1) & 65535
        else:
            self.candidate += 1

def crc8(data):
    crc = 0
    for value in data:
        crc ^= value
        for _ in range(8):
            crc = ((crc << 1) ^ (7 if crc & 128 else 0)) & 255
    return crc

def decode(line):
    assert len(line) == 87 and line[:2] == b'B1' and line[-2:] == b'\r\n'
    assert line[82] == 42 and crc8(line[:82]) == int(line[83:85], 16)
    raw, filtered = int(line[6:8], 16), int(line[8:10], 16)
    assert raw < 64 and filtered < 64
    return dict(sequence=int(line[2:6], 16), raw=raw, filtered=filtered,
                presses=[int(line[i:i+4],16) for i in range(10,34,4)],
                releases=[int(line[i:i+4],16) for i in range(34,58,4)],
                edges=[int(line[i:i+4],16) for i in range(58,82,4)])

if __name__ == '__main__':
    switch = Switch(5)
    for value in [1,0,1,1,0,1,1,1,1]: switch.sample(value)
    assert switch.level == 0 and switch.presses == 0
    switch.sample(1)
    assert switch.level == 1 and switch.presses == 1
    for _ in range(50): switch.sample(1)
    assert switch.presses == 1
    for _ in range(5): switch.sample(0)
    assert switch.releases == 1
    print('PASS independent debounce/hold/release model')
