"""Integer reference for the resident six-operator engine. No RTL introspection."""
from pathlib import Path
import json
import math
import random
from voice_operator_model import MASK, UNITY, signed, packet
from voice_fabric_model import multi_envelope
from dx7_model import envelope as dx_envelope

ROOT = Path(__file__).resolve().parents[1]
SINE = [round(math.sin(2 * math.pi * n / 1024) * UNITY) for n in range(1024)]

def clamp(value, low=-UNITY, high=UNITY):
    return min(high, max(low, value))

def interp(table, phase):
    index, fraction = phase >> 22, phase & ((1 << 22) - 1)
    return table[index] + ((table[(index + 1) & 1023] - table[index]) * fraction >> 22)

def operator(words, tables=None):
    """21 word request -> five word completion; arithmetic shifts round down."""
    w = [x & MASK for x in words]
    phase, increment, modulation, depth, gain = w[:5]
    last, older, feedback, seed, flags, shape = w[15:]
    dx = bool(flags & 32)
    if dx:
        level,status,eg_amplitude = dx_envelope(w[5:15],flags>>6,shape)
        eg = packet(level,status)
    else:
        eg = multi_envelope(packet(*w[5:15]))
        eg_amplitude = eg & MASK
    waveform, mode = flags & 7, (flags >> 3) & 3
    offset = (signed(modulation)<<9) if dx else signed(modulation) * signed(depth) >> 26
    history = (signed(last) + signed(older)) >> 1
    fb = (history << (feedback+1) if feedback else 0) if dx else history * signed(feedback) >> 26
    next_phase = (phase + increment + (offset if mode == 1 else 0)) & MASK
    lookup = ((phase if dx else next_phase) + fb + (offset if mode == 0 else 0)) & MASK
    seed = seed or 1
    seed ^= (seed << 13) & MASK
    seed ^= seed >> 17
    seed ^= (seed << 5) & MASK
    seed &= MASK
    if waveform == 0:
        wave = interp(SINE, lookup)
    elif waveform == 1:
        wave = UNITY - (abs(lookup - (1 << 31)) >> 4)
    elif waveform == 2:
        wave = (lookup >> 5) - UNITY
    elif waveform == 3:
        wave = UNITY if lookup < shape else -UNITY
    elif waveform == 4:
        wave = signed(seed) >> 5
    elif waveform == 5:
        a, b = tables or (SINE, SINE)
        va, vb = interp(a, lookup), interp(b, lookup)
        wave = va + ((vb - va) * min(shape, 65536) >> 16)
    else:
        wave = 0
    factor = UNITY
    if mode == 2:
        factor += (clamp((signed(modulation) + UNITY) >> 1, 0, UNITY) - UNITY) * depth >> 26
    elif mode == 3:
        factor += (clamp(signed(modulation)) - UNITY) * depth >> 26
    wave = wave * factor >> 26
    amplitude = eg_amplitude * gain >> 26
    sample = wave * amplitude >> 26
    return packet(sample, next_phase, eg & MASK, eg >> 32, seed)

def preset(kind=0):
    """Six resident rows; flags carry route mask/carrier/wave/mode/enable/fixed/restart."""
    rows = []
    for op in range(6):
        wave = 0 if kind == 0 else op
        route = (1 << (op - 1)) if op else 0
        flags = route | (int(op == 5) << 6) | (wave << 7) | ((op % 4) << 10) | (1 << 12) | (1 << 14)
        depth = UNITY // 2 if op % 4 >= 2 else 0x10000000
        rows.append(([65536 * (1 + op % 3), UNITY // 2, depth, 0x02000000, flags, 32768 if wave == 5 else 0x80000000],
                     [UNITY, UNITY * 3 // 4, UNITY // 2, 0, UNITY // 4, UNITY // 16, UNITY // 32, UNITY // 16]))
    return rows

class VoiceModel:
    def __init__(self, patch):
        self.patches = {0: patch}
        self.voices = [None] * 8
        self.master = UNITY
        self.enabled = True
        self.sustain = False
        self.modulator = None

    def on(self, identity, inc, gain=UNITY, pan=UNITY//2, patch=0, note=60, velocity=100):
        for v in self.voices:
            if v and v['id'] == identity:
                return
        slot = next((n for n, v in enumerate(self.voices) if v is None), 0)
        self.voices[slot] = dict(id=identity, inc=inc, gain=gain, pan=pan, target_gain=gain,patch=patch,
                                target_pan=pan, held=True, event=1,note=note,velocity=velocity,
                                state=[[0,0,0,0,0,slot*8+o+1] for o in range(6)])
        if self.modulator:
            self.modulator.note_on(slot)

    def off(self, identity):
        for v in self.voices:
            if v and v['id'] == identity:
                v['held'] = False
                if not self.sustain:
                    v['event'] = 2

    def frame(self):
        left = right = 0
        if self.enabled and self.modulator:
            self.modulator.frame(self.voices)
        for slot, v in enumerate(self.voices):
            if not v or not self.enabled:
                continue
            for name in ('gain', 'pan'):
                delta = v['target_'+name] - v[name]
                v[name] += (max(1, delta >> 6) if delta > 0 else min(-1, -((-delta) >> 6)) if delta < 0 else 0)
            outputs = [0] * 6
            modulation_routes = self.modulator.route(slot,v['patch']) if self.modulator else [0]*15
            pitch_delta = clamp(modulation_routes[0])
            base_increment = clamp(v['inc'] + (v['inc'] * pitch_delta >> 26),0,0x7fffffff)
            voice_gain = clamp(v['gain']+modulation_routes[1],0,UNITY)
            voice_pan = clamp(v['pan']+modulation_routes[2],0,UNITY)
            carriers = []
            live = False
            for o, (core, egparams) in enumerate(self.patches[v['patch']]):
                tune,gain,depth,feedback,flags,shape = core
                gain = clamp(gain+modulation_routes[3+o],0,UNITY)
                depth = clamp(signed(depth)+modulation_routes[9+o],0,UNITY) if flags&2048 else clamp(signed(depth)+modulation_routes[9+o],-(1<<31),(1<<31)-1)
                if not flags & 4096:
                    continue
                phase,level,stage,last,older,seed = v['state'][o]
                modulation = clamp(sum(outputs[n] for n in range(o) if flags & (1 << n)), -(1<<31), (1<<31)-1)
                increment = tune if flags & 8192 else min((base_increment * tune) >> 16, 0x7fffffff)
                metadata = (v['note'] | v['velocity']<<7 | ((flags>>16)&127)<<14)<<6 if flags&32768 else 0
                result = operator([phase,increment,modulation,depth,gain,level,stage | v['event'] << 3 | ((flags >> 14)&1) << 5,
                                   *egparams,last,older,feedback,seed,(flags>>7)&7 | ((flags>>10)&3)<<3 | ((flags>>15)&1)<<5 | metadata,shape])
                words = [(result >> (32*n)) & MASK for n in range(5)]
                sample,phase,level,status,seed = words
                outputs[o] = signed(sample)
                v['state'][o] = [phase,level,status&7,signed(sample),last,seed]
                if flags & 64:
                    carriers.append(signed(sample))
                    live |= bool(status & 7)
            v['event'] = 0
            mono = sum(carriers) * (UNITY // max(1,len(carriers))) >> 26
            mono = mono * voice_gain >> 26
            left += mono * (UNITY-voice_pan) >> 26
            right += mono * voice_pan >> 26
            if not live and not v['held']:
                self.voices[slot] = None
        return clamp(((left >> 3) * self.master) >> 26), clamp(((right >> 3) * self.master) >> 26)

def generate():
    (ROOT/'rom').mkdir(exist_ok=True)
    (ROOT/'rom/sine_q26.hex').write_text(''.join(f'{v & MASK:08x}\n' for v in SINE),encoding='ascii')
    rng = random.Random(0x534958)
    rows=[]
    for n in range(2400):
        mode=n%4
        eg=[rng.randrange(UNITY+1) for _ in range(3)]+[0]+[rng.randrange(1,UNITY) for _ in range(4)]
        words=[rng.getrandbits(32),rng.getrandbits(31),rng.randrange(-3*UNITY,3*UNITY),
               rng.randrange(UNITY+1) if mode>=2 else rng.randrange(-(1<<31),(1<<31)),
               rng.randrange(UNITY+1),rng.randrange(UNITY+1),rng.randrange(6)|rng.randrange(4)<<3|32,
               *eg,rng.randrange(-UNITY,UNITY),rng.randrange(-UNITY,UNITY),rng.getrandbits(32),
               0 if n%7==0 else rng.getrandbits(32),(n%6)|(mode<<3),
               rng.randrange(65537) if n%6==5 else rng.getrandbits(32)]
        rows.append((packet(*words),operator(words)))
    (ROOT/'vectors/fm_operator.txt').write_text(''.join(f'{p:0168x} {r:040x}\n' for p,r in rows),encoding='ascii')
    wave_a=[(n*131072)-UNITY for n in range(1024)]
    wave_b=[-v for v in wave_a]
    (ROOT/'vectors/wave_upload.txt').write_text(''.join(f'{v&MASK:08x}\n' for v in wave_a+wave_b),encoding='ascii')
    wave_rows=[]
    for n in range(256):
        words=[rng.getrandbits(32),rng.getrandbits(31),rng.randrange(-UNITY,UNITY),UNITY//2,UNITY,
               UNITY,4,UNITY,UNITY,UNITY,0,1,1,1,1,0,0,0,1,5|((n%4)<<3),[0,65536,32768,12345][n%4]]
        wave_rows.append((packet(*words),operator(words,(wave_a,wave_b))))
    (ROOT/'vectors/fm_wave_uploaded.txt').write_text(''.join(f'{p:0168x} {r:040x}\n' for p,r in wave_rows),encoding='ascii')
    patch=preset(1)
    (ROOT/'vectors/engine_patch.txt').write_text(''.join(f'{packet(*c):080x} {packet(*e):080x}\n' for c,e in patch),encoding='ascii')
    (ROOT/'vectors/engine_patch_alt.txt').write_text(''.join(f'{packet(*c):080x} {packet(*e):080x}\n' for c,e in preset(0)),encoding='ascii')
    model=VoiceModel(patch)
    model.patches[1]=preset(0)
    expected=[]
    # Frames have deterministic commands injected strictly between renders.
    for frame in range(400):
        if frame==0:
            for v in range(8): model.on(v+100, 20000000 + v*1234567, UNITY-v*1000000, v*UNITY//7,v%2)
        if frame==80: model.on(100,20000000,UNITY,0)  # duplicate must not retrigger
        if frame==100:
            model.voices[0].update(inc=25000000,target_gain=UNITY//4,target_pan=UNITY*3//4)
        if frame==120: model.sustain=True
        if frame==130:
            for v in range(8): model.off(v+100)
        if frame==200:
            model.sustain=False
            for v in model.voices:
                if v and not v['held']: v['event']=2
        expected.append(model.frame())
    (ROOT/'vectors/engine_pcm.txt').write_text(''.join(f'{packet(l,r):016x}\n' for l,r in expected),encoding='ascii')
    (ROOT/'vectors/engine_manifest.json').write_text(json.dumps({'operator_vectors':len(rows),'uploaded_wave_vectors':len(wave_rows),'operator_total':len(rows)+len(wave_rows),'pcm_frames':len(expected)},indent=2)+'\n')
    print('Generated 2656 operator vectors and 400 eight-voice PCM frames')

if __name__=='__main__':
    generate()
