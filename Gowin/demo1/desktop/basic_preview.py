"""可重建的桌面参考试听，非Surge渲染、非FPGA录音，也非定点逐位参考。"""
import io
import math
import struct
import wave

from profiles import validate_profile


def envelope(profile, prefix, time, gate):
    attack=profile[prefix+'attack']/1000
    decay=profile[prefix+'decay']/1000
    sustain=profile[prefix+'sustain']/100
    release=profile[prefix+'release']/1000
    def held(t):
        if attack>0 and t<attack:return t/attack
        if decay>0 and t<attack+decay:return 1-(1-sustain)*(t-attack)/decay
        return sustain
    if time<gate:return held(time)
    return held(gate)*max(0,1-(time-gate)/release) if release>0 else 0


def oscillator(kind, phase, samples):
    phase%=1
    if kind=='正弦':return math.sin(2*math.pi*phase)
    if kind=='方波':return 1 if phase<.5 else -1
    if kind=='锯齿':return 2*phase-1
    if kind=='三角':return 1-4*abs(phase-.5)
    if kind=='自定义波表':
        position=phase*1024;index=int(position);fraction=position-index
        return (samples[index]*(1-fraction)+samples[(index+1)%1024]*fraction)/32768
    raise ValueError('Unsupported preview waveform')


def render_preview(profile, samples=None, notes=(48,60,72), rate=24000):
    validate_profile(profile)
    if profile['mode']=='采样钢琴' or any(type(n) is not int or not 0<=n<=127 for n in notes) or not notes:
        raise ValueError('Invalid desktop preview request')
    if '自定义波表' in (profile['wave_a'],profile['wave_b']):
        if samples is None or len(samples)!=1024 or any(type(v) is not int or not -32768<=v<=32767 for v in samples):
            raise ValueError('Preview requires a validated1024-point frame')
    if type(rate) is not int or not 8000<=rate<=48000 or len(notes)>8:raise ValueError('Preview size/rate invalid')
    gate=.65
    duration=gate+min(profile['release']/1000,1.0)+.10
    output=[]
    for note in notes:
        hz=440*2**((note-69)/12)
        mod_hz=profile['mod_hz'] or hz*profile['ratio']
        for i in range(round(duration*rate)):
            t=i/rate;level=envelope(profile,'',t,gate);mod_level=envelope(profile,'m_',t,gate)
            a_phase=t*hz;b=oscillator(profile['wave_b'],t*mod_hz,samples)
            a=oscillator(profile['wave_a'],a_phase,samples);depth=profile['depth']*mod_level
            if profile['mode']=='FM / PM':
                value=oscillator(profile['wave_a'],a_phase+depth*b,samples)*profile['gain_a']/100
            elif profile['mode']=='AM':value=a*((1-depth)+depth*(b+1)/2)*profile['gain_a']/100
            elif profile['mode']=='环形调制':value=a*((1-depth)+depth*b)*profile['gain_a']/100
            else:value=(a*profile['gain_a']+b*profile['gain_b'])/100
            value*=level*.35
            output.append(max(-32768,min(32767,round(value*32767))))
        output.extend([0]*round(.12*rate))
    buffer=io.BytesIO()
    with wave.open(buffer,'wb') as wav:
        wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(rate)
        wav.writeframes(struct.pack('<'+str(len(output))+'h',*output))
    return buffer.getvalue()
