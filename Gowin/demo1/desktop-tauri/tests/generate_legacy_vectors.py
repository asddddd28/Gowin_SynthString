"""One-time compatibility oracle. Python is NOT required to build or run the app/tests.

Regenerate deliberately when the established hardware protocol changes; review the
JSON diff. Rust tests consume the checked-in file without invoking this script.
"""
import copy
import json
from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / 'desktop'))
from protocol import defaults, validate_config, sound_packets, piano_sound
from profiles import words, preset, PRESETS, ProfileTransfer, crc_words
from wavetable import TableTransfer, PairTransfer, table_crc, harmonic_piano_table
from pcm import PcmTransfer, crc_words as pcm_crc
from basic_bank import load_basic_bank
from wavetable_library import load_library

rng = random.Random(31004)
profiles = [s.profile for s in load_basic_bank(ROOT / 'src-tauri/assets/basic_bank')]
profiles += [preset(n) for n in PRESETS]
for i in range(200):
    p = copy.deepcopy(profiles[i % 23])
    for prefix in ('', 'm_'):
        for name in ('attack', 'decay', 'release'):
            p[prefix + name] = rng.choice([0, .001, 1, 5000, rng.uniform(0, 5000)])
        p[prefix + 'sustain'] = rng.choice([0, 100, rng.uniform(0, 100)])
    p.update(ratio=rng.uniform(1 / 256, 8), depth=rng.random(),
             gain_a=rng.random() * 100, gain_b=rng.random() * 100,
             sensitivity=rng.random() * 100, mod_hz=rng.random() * 1000)
    profiles.append(p)

cases = []
def record(kind, init, transfer, drive):
    transfer.token = 65535
    steps = []
    def step(status=None, now=None):
        now = len(steps) * .01 if now is None else now
        frames = transfer.advance(now, status)
        steps.append(dict(now=now, status=status, frames=[list(f) for f in frames],
                          count=transfer.count, done=transfer.done, error=bool(transfer.error)))
    drive(step, transfer)
    cases.append(dict(kind=kind, init=init, token=65535, steps=steps))

sample = harmonic_piano_table()
for pair in (False, True):
    frames = [sample, list(reversed(sample))] if pair else [sample]
    flat = sum(frames, [])
    def drive(step, t):
        s = dict(table=True, result=0, available=True, pair_capable=True,
                 two_frames=pair, count=0, crc=65535, token=123, generation=65535)
        step(); step(s)
        step(dict(s, token=123, result=1))  # stale token ignored
        for count in range(0, len(flat) + 1, 32):
            step(dict(s, token=t.token, result=1, count=count, crc=table_crc(flat[:count])))
        final = dict(s, token=t.token, result=3, count=len(flat), crc=table_crc(flat), generation=0)
        step(dict(final, generation=65535))  # stale generation cannot confirm
        step(final)
    record('pair' if pair else 'table', frames, PairTransfer(frames, 0) if pair else TableTransfer(sample, 0), drive)

image = dict(format='tang-pcm-v1', sample_rate=24000, samples=sample, loop_start=0, loop_end=1024, root_note=60)
def pcm_drive(step, t):
    s = dict(pcm=True, result=0, available=False, count=0, crc=65535, token=12, generation=65535, metadata=0)
    step(); step(s); step(dict(s, token=t.token, result=1))
    for count in range(0, 1025, 32):
        step(dict(s, token=t.token, result=1, metadata=4, count=count, crc=pcm_crc(t.meta + sample[:count])))
    step(dict(s, token=t.token, result=3, metadata=4, count=1024, crc=t.crc, generation=0, available=True))
record('pcm', image, PcmTransfer(image, 0), pcm_drive)

batch = [(32, dict(preset('FM 电钢琴'), frame_position=31.25)), (63, dict(preset('AM 颤音'), frame_position=100))]
def profile_drive(step, t):
    s = dict(profile=True, result=0, key=32, count=0, crc=0, token=0, generation=65535, profile_version=2)
    step(); step(s)
    for i, (key, p) in enumerate(batch):
        step(dict(s, key=key, token=t.token, result=1))
        step(dict(s, key=key, token=t.token, result=3, count=18, crc=crc_words(words(p)), generation=i))
    step(dict(table=True, pair_capable=True))
    for key,p in batch:
        step(dict(table=True, pair_capable=True, query_key=key, frame_position=round(p['frame_position'] * 65535 / 100)))
record('profiles', batch, ProfileTransfer(batch, 0), profile_drive)

def bad_crc(step, t):
    step(dict(table=True, pair_capable=True, generation=2))
    step(dict(table=True, token=t.token, result=1, count=0, crc=123))
record('table', [sample], TableTransfer(sample, 0), bad_crc)
record('pair', [sample, sample], PairTransfer([sample, sample], 0), lambda step,t: step(dict(table=True, pair_capable=False, generation=2)))
record('profiles', batch, ProfileTransfer(batch, 0), lambda step,t: step(dict(profile=True, profile_version=1)))
record('table', [sample], TableTransfer(sample, 0), lambda step,t: step(now=10))

sound = validate_config(defaults())['sound']
sounds = [sound, piano_sound()] + [dict(sound, wave=w, sustain=s, attack=a, release=a, volume=37.0, output_boost=2)
    for w in ('正弦', '自定义波表') for s in (0, 100, 33.3) for a in (0, .001, 5000)]
library = load_library(ROOT / 'src-tauri/assets/wavetable_library')
result = dict(defaults=validate_config(defaults()), profiles=[dict(profile=p, words=words(p)) for p in profiles],
    sounds=[dict(sound=s, frames=[list(f) for f in sound_packets(s)]) for s in sounds],
    piano=sample, transfers=cases,
    pairs=[dict(index=i, position=pos, job=r.job(pos), frames=r.pair(pos)[0]) for i,r in enumerate(library) for pos in (0, .001, 31.25, 75, 100)])
target = ROOT / 'src-tauri/tests/fixtures/legacy-vectors.json'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
print(f'{len(profiles)} profiles, {len(sounds)} outputs, {len(cases)} transfer transcripts -> {target}')
