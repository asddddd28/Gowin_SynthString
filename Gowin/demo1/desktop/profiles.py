"""Per-key patches and acknowledged atomic uploads (firmware protocol 0x20..0x27)."""
import binascii
import copy
import math
import secrets
from protocol import packet,SAMPLE_RATE,WAVES,PIANO
from envelope import encode_step,PRECISE_ENVELOPE

MODES={'波表混合':0,'FM / PM':1,'AM':2,'环形调制':3,'采样钢琴':4}
OSC_WAVES={k:v for k,v in WAVES.items() if k!=PIANO}

def from_sound(sound):
    piano=sound['wave']==PIANO
    return dict(mode='波表混合',wave_a='三角' if piano else sound['wave'],wave_b='正弦',
        ratio=1.0,depth=0.0,mod_hz=0.0,sensitivity=0.0,gain_a=80.0 if piano else 100.0,gain_b=20.0 if piano else 0.0,
        attack=sound['attack'],decay=sound['decay'],sustain=sound['sustain'],release=sound['release'],
        m_attack=0.0,m_decay=0.0,m_sustain=100.0,m_release=120.0)

def preset(name):
    p=from_sound(dict(wave='正弦',attack=5.,decay=500.,sustain=50.,release=120.))
    if name=='FM 电钢琴':p.update(mode='FM / PM',ratio=1.,depth=.22,attack=2.,decay=1200.,sustain=0.,m_attack=1.,m_decay=600.,m_sustain=0.,sensitivity=60.)
    elif name=='FM 钟声':p.update(mode='FM / PM',ratio=3.5,depth=.60,attack=1.,decay=2200.,sustain=0.,release=400.,m_attack=1.,m_decay=1200.,m_sustain=0.,sensitivity=50.)
    elif name=='FM 贝斯':p.update(mode='FM / PM',ratio=1.,depth=.35,attack=3.,decay=350.,sustain=35.,release=80.,m_attack=1.,m_decay=160.,m_sustain=5.,sensitivity=65.)
    elif name=='AM 颤音':p.update(mode='AM',depth=.8,mod_hz=5.,sustain=85.,m_sustain=100.)
    elif name=='环形金属':p.update(mode='环形调制',depth=1.,ratio=1.414,attack=3.,decay=700.,sustain=30.)
    elif name=='采样钢琴':p.update(mode='采样钢琴',attack=0.,decay=2500.,sustain=0.,release=180.)
    elif name!='正弦':raise ValueError('未知预设')
    return p

PRESETS=('正弦','FM 电钢琴','FM 钟声','FM 贝斯','AM 颤音','环形金属','采样钢琴')

def validate_profile(p):
    if not isinstance(p,dict) or p.get('mode') not in MODES or p.get('wave_a') not in OSC_WAVES or p.get('wave_b') not in OSC_WAVES:
        raise ValueError('合成器或振荡器波形不合法')
    ranges={'ratio':(1/256,8),'depth':(0,2 if p['mode'] in ('FM / PM','波表混合') else 1),
            'mod_hz':(0,1000),'sensitivity':(0,100),'gain_a':(0,100),'gain_b':(0,100)}
    if 'frame_position' in p:ranges['frame_position']=(0,100)
    for prefix in ('','m_'):
        ranges.update({prefix+'attack':(0,5000),prefix+'decay':(0,5000),prefix+'sustain':(0,100),prefix+'release':(0,5000)})
    for name,(lo,hi) in ranges.items():
        value=p.get(name)
        if type(value) not in (int,float) or not math.isfinite(value) or not lo<=value<=hi:
            raise ValueError(f'{name} 必须在 {lo}..{hi} 范围内')
    return p

def words(p):
    validate_profile(p)
    def env(prefix):
        sustain=round(p[prefix+'sustain']*65535/100)
        def step(distance,ms):
            return encode_step(distance,ms,SAMPLE_RATE)
        # Per-key release always uses peak as reference: S=0 still releases smoothly.
        return [step(262143,p[prefix+'attack']),step(262143-4*sustain,p[prefix+'decay']),sustain,step(262143,p[prefix+'release'])]
    return [MODES[p['mode']]|PRECISE_ENVELOPE,OSC_WAVES[p['wave_a']],OSC_WAVES[p['wave_b']],round(p['ratio']*256),round(p['depth']*4096),
            *env(''),*env('m_'),round(p['gain_b']*65535/100),round(p['sensitivity']*127/100),round(p['mod_hz']*16),round(p['gain_a']*65535/100),0]

def crc_words(data):
    return binascii.crc_hqx(b''.join(w.to_bytes(2,'little') for w in data),0xffff)

class ProfileTransfer:
    kind='profiles'
    def __init__(self,profiles,now):
        profiles=list(profiles)
        self.profiles=[(key,words(copy.deepcopy(p))) for key,p in profiles]
        self.positions=[(key,round(p.get('frame_position',0)*65535/100)) for key,p in profiles]
        self.position_requested=any('frame_position' in p for _,p in profiles)
        self.position_transfer=None
        if not self.profiles or any(not 32<=key<64 for key,_ in self.profiles):raise ValueError('无效按键配置')
        self.count=0;self.done=False;self.error=None;self.state='probe'
        self.deadline=now+3;self.query_at=0;self.generation=0;self.token=secrets.randbelow(65535)+1
    def advance(self,now,status=None):
        if self.done or self.error:return []
        if self.position_transfer is not None:
            frames=self.position_transfer.advance(now,status)
            self.done=self.position_transfer.done;self.error=self.position_transfer.error
            return frames
        key,data=self.profiles[self.count]
        if now>self.deadline:
            self.error='参数上传应答超时，请烧录逐键 FM/AM 固件并重新上传；本地配置尚未确认生效。'
            return [packet(0x23)]
        if status is not None:
            if self.state=='probe':
                if status.get('profile_version',0)<2:
                    self.error='当前固件不支持高精度包络，请烧录 precision 版固件后重新连接。'
                    return [packet(0x23)]
                self.generation=status['generation'];self.state='begin';self.deadline=now+3;self.query_at=now+.2
                return [packet(0x20,key,value=self.token),packet(0x27,key)]
            if status['token']!=self.token or status['key']!=key:return []
            if status['result']==4:
                self.error=f'音键 {key-31} 参数校验失败，请重新上传。';return [packet(0x23)]
            if self.state=='begin' and status['result']==1 and status['count']==0:
                self.state='commit';self.deadline=now+3;self.query_at=now+.2
                return [packet(0x21,key,note=i,value=w) for i,w in enumerate(data)]+[packet(0x22,key,self.token&255,self.token>>8,crc_words(data)),packet(0x27,key)]
            if self.state=='commit' and status['result']==3 and status['count']==18 and status['crc']==crc_words(data) and status['generation']==((self.generation+1)&65535):
                self.count+=1
                if self.count==len(self.profiles):
                    if self.position_requested:
                        from wavetable import PositionTransfer
                        self.position_transfer=PositionTransfer(self.positions,now)
                        return self.position_transfer.advance(now)
                    self.done=True;return []
                self.generation=status['generation'];self.token=(self.token%65535)+1;self.state='begin'
                self.deadline=now+3;self.query_at=now+.2;key=self.profiles[self.count][0]
                return [packet(0x20,key,value=self.token),packet(0x27,key)]
        if now>=self.query_at:
            self.query_at=now+.2;return [packet(0x27,key)]
        return []
