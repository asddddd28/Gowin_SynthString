"""Independent DX compatibility arithmetic, at the system sample rate.

Scaling tables/formulas adapted from Google Music Synthesizer for Android:
Copyright 2012 Google Inc., Apache-2.0. See assets/fm1/DSP_NOTICE.txt.
This sample-stepped model intentionally does not claim bit-exact FM1 emulation.
"""
from pathlib import Path
import math

UNITY = 1 << 26
RATE = 50_000_000 / 1024
LEVEL_LUT = [0,5,9,13,17,20,23,25,27,29,31,33,35,37,39,41,42,43,45,46]
EXP_SCALE = [0,1,2,3,4,5,6,7,8,9,11,14,16,19,23,27,33,39,47,56,66,80,94,110,126,142,158,174,190,206,222,238,250]
VELOCITY = [0,70,86,97,106,114,121,126,132,138,142,148,152,156,160,163,166,170,173,174,178,181,184,186,189,190,194,196,198,200,202,205,206,209,211,214,216,218,220,222,224,225,227,229,230,232,233,235,237,238,240,241,242,243,244,246,246,248,249,250,251,252,253,254]
INCREMENTS = [round(((4+(q&3)) << (2+(q>>2))) * 44100/RATE) for q in range(64)]
EXP2 = [round(2**(i/256)*UNITY) for i in range(256)]
FLOOR = 16 << 16


def scale_level(value):
    if not isinstance(value, int) or not 0 <= value <= 99:
        raise ValueError('DX level must be 0..99')
    return value+28 if value >= 20 else LEVEL_LUT[value]


def scaling(note, velocity, output, profile):
    breakpoint = profile & 127
    offset = note-breakpoint-17
    group = abs(offset)//3
    depth = (profile >> (7 if offset < 0 else 14)) & 127
    curve = (profile >> (21 if offset < 0 else 23)) & 3
    magnitude = (group*depth*329 >> 12) if curve in (0,3) else (EXP_SCALE[min(group,32)]*depth*329 >> 15)
    key_delta = -magnitude if curve < 2 else magnitude
    vel_delta = ((((profile >> 28)&7) * (VELOCITY[velocity>>1]-239)+7) >> 3) << 4
    outlevel = max(0, (min(127,output+key_delta) << 5)+vel_delta)
    ratescale = (((profile>>25)&7)*min(31,max(0,note//3-7))) >> 3
    return outlevel, ratescale


def amplitude(level, stage):
    if stage == 0 or level <= FLOOR:
        return 0
    return EXP2[(level>>16)&255] >> max(0,17-(level>>24))


def envelope(words, metadata, profile):
    level, control, *params = words
    stage, event = control&7, (control>>3)&3
    bad = stage > 5
    if event == 1:
        stage, bad = 1, False
        if control&32: level = 0
    elif event == 3:
        stage, level, bad = 0, 0, False
    elif bad:
        stage, level = 0, 0
    elif event == 2 and stage:
        stage = 5
    reached = False
    if stage in (1,2,3,5):
        note, velocity, output = metadata&127, (metadata>>7)&127, (metadata>>14)&127
        out, rate = scaling(note,velocity,output,profile)
        index = 3 if stage == 5 else stage-1
        target = max(16,params[index]+out-4256) << 16
        inc = INCREMENTS[min(63,params[4+index]+rate)]
        if target > level:
            level = max(level,1716<<16)
            level = min(target,level+(((17<<24)-level)>>24)*inc)
        else:
            level = max(target,level-inc)
        reached = level == target
        if reached: stage = 0 if stage == 5 else stage+1
    status = stage | (bool(stage)<<3) | (reached<<4) | (bad<<6)
    return level, status, amplitude(level,stage)


def roms():
    root = Path(__file__).resolve().parents[1]/'rom'
    tables = {'dx_rate':INCREMENTS, 'dx_exp2':EXP2, 'dx_velocity':VELOCITY,
              'dx_keyscale':EXP_SCALE+[250]*31}
    for name, values in tables.items():
        (root/f'{name}.hex').write_text(''.join(f'{x:08x}\n' for x in values),encoding='ascii')
    # Truncation error of the exponential ROM, independent floating function.
    error = max(abs(amplitude(l,4)/UNITY-2**(l/(1<<24)-17)) /
                2**(l/(1<<24)-17) for l in range(1<<24,16<<24,7919))
    # Includes Q26 rounding near -96 dB; ROM-only truncation is below 0.271%.
    assert error < 0.0036
    assert scaling(60,100,127,0) == (4064,0)
    assert all(a <= b for a,b in zip(INCREMENTS,INCREMENTS[1:]))
    print(f'PASS DX arithmetic constants; exp2 worst relative error {error:.6f}')


if __name__ == '__main__': roms()
