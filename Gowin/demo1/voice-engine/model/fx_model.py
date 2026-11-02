"""Integer reference for the shared stereo effects. No RTL control-state imitation."""
from pathlib import Path
import json
import random

UNITY = 1 << 26
FRACTION = 16
COMBS = (1493, 1601, 1747, 1999)
ALLPASS = (211, 431, 263, 487)


def tz(value, bits):
    return (abs(value) >> bits) * (-1 if value < 0 else 1)


def clamp(value, low, high):
    return max(low, min(high, value))


def store(value):
    """Q52 to signed 18-bit Q16, toward zero to avoid feedback limit cycles."""
    raw = tz(value, 52 - FRACTION)
    return clamp(raw, -(1 << 17), (1 << 17) - 1), not -(1 << 17) <= raw < (1 << 17)


def mix(dry, wet, amount):
    raw = (dry * (UNITY - amount) + wet * amount) >> 26
    return clamp(raw, -UNITY, UNITY), not -UNITY <= raw <= UNITY


class Delay:
    def __init__(self, bits=15):
        self.depth = 1 << bits
        self.clear()

    def clear(self):
        self.rings = [[0] * self.depth for _ in range(2)]
        self.position = 0

    def step(self, audio, config):
        left_time, right_time, feedback, wet, flags = config
        echoes = []
        for channel, time in enumerate((left_time, right_time)):
            whole, fraction = divmod(time, 65536)
            a = self.rings[channel][(self.position - whole) % self.depth] << 10
            b = self.rings[channel][(self.position - whole - 1) % self.depth] << 10
            echoes.append(a + ((b - a) * fraction >> 16))
        output, clipped = [], False
        for channel in range(2):
            source = echoes[1 - channel if flags & 2 else channel]
            injection = audio[channel] if flags & 1 else 0
            state, clip = store((injection << 26) + feedback * source)
            self.rings[channel][self.position] = state
            sample, clip_mix = mix(audio[channel], echoes[channel], wet if flags & 1 else 0)
            output.append(sample)
            clipped |= clip or clip_mix
        self.position = (self.position + 1) % self.depth
        return tuple(output), clipped


class Reverb:
    def __init__(self):
        self.clear()

    def clear(self):
        self.lines = [[0] * n for n in COMBS + ALLPASS]
        self.positions = [0] * 8
        self.lowpass = [0] * 4

    def step(self, audio, config):
        feedback, damping, wet, enabled = config
        mono = ((audio[0] + audio[1]) >> 1) if enabled else 0
        combs, clipped = [], False
        for index in range(4):
            delayed = self.lines[index][self.positions[index]] << 10
            lp = tz((UNITY - damping) * delayed + damping * self.lowpass[index], 26)
            self.lowpass[index] = lp
            state, clip = store((UNITY - feedback) * mono + feedback * lp)
            self.lines[index][self.positions[index]] = state
            combs.append(delayed)
            clipped |= clip
        feed = sum(combs) >> 2
        tails = []
        for channel in range(2):
            signal = feed
            for index in range(4 + channel * 2, 6 + channel * 2):
                delayed = self.lines[index][self.positions[index]] << 10
                value = tz((delayed << 26) - signal * (UNITY // 2), 26)
                state, clip = store((signal << 26) + value * (UNITY // 2))
                self.lines[index][self.positions[index]] = state
                clipped |= clip
                signal = value
            tails.append(signal)
        for index, line in enumerate(self.lines):
            self.positions[index] = (self.positions[index] + 1) % len(line)
        output = []
        for dry, tail in zip(audio, tails):
            sample, clip = mix(dry, tail, wet if enabled else 0)
            output.append(sample)
            clipped |= clip
        return tuple(output), clipped


def packed(words):
    return sum((word & 0xffffffff) << (32 * i) for i, word in enumerate(words))


def generate():
    root = Path(__file__).resolve().parents[1]
    randomizer = random.Random(7327)
    summaries = {}
    for name, effect in [('delay', Delay()), ('reverb', Reverb())]:
        rows, clips, nonzero = [], 0, 0
        count = 80000 if name == 'delay' else 100000
        for frame in range(count):
            clear = frame in (0, 6000, 14000, 19000)
            if clear:
                effect.clear()
            if name == 'delay':
                if frame < 6000:
                    config = (int(17.25 * 65536), int(29.75 * 65536), -UNITY * 3 // 4, UNITY, 3)
                elif frame < 14000:
                    config = (1 << 16, 2 << 16, UNITY * 9 // 10, UNITY // 2, 1)
                else:
                    config = (0x7fffffff, 32766 << 16, UNITY // 2, UNITY, 1)
            else:
                config = (UNITY * 7 // 10, UNITY * 3 // 10, UNITY * 3 // 4, 1)
                if 6000 <= frame < 14000:
                    config = (UNITY * 9 // 10, UNITY * 95 // 100, UNITY, 1)
            if frame < 1000 or 6000 <= frame < 9000:
                audio = tuple(randomizer.randint(-UNITY, UNITY) for _ in range(2))
                if name == 'reverb' and frame >= 6000:
                    audio = (UNITY, UNITY)
            elif frame in (14000, 19000):
                audio = (UNITY // 2, -UNITY // 3)
            else:
                audio = (0, 0)
            if 1000 <= frame < 1200:
                config = (*config[:-1], 0)  # bypass while tail decays
            result, clip = effect.step(audio, config)
            nonzero += result != (0, 0)
            clips += clip
            rows.append(f'{int(clear):x} {packed(config):040x} {packed(audio):016x} {packed(result):016x} {int(clip):x}')
        (root / f'vectors/fx_{name}.txt').write_text('\n'.join(rows) + '\n', encoding='utf-8')
        summaries[name] = dict(frames=count, clipped=clips, nonzero=nonzero, last=list(result))
        if name == 'reverb':
            assert result == (0, 0), 'Feedback must decay to digital silence'
    (root / 'reports/fx-model.json').write_text(json.dumps(summaries, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(summaries))


if __name__ == '__main__':
    generate()
