"""电脑与 FPGA 共用的 115200 / 8N1 协议及配置校验。"""
import math
from functools import reduce
from operator import xor

SAMPLE_RATE = 96001.059322
PIANO = '钢琴（合成）'
WAVES = {'正弦': 0, '三角': 3, '锯齿': 2, '方波': 1, PIANO: 3, '自定义波表': 4}

def piano_sound(volume=25.0):
    return dict(attack=2.0, decay=1400.0, sustain=0.0, release=120.0, volume=volume, wave=PIANO, output_boost=0)



def packet(op, identity=0, note=0, velocity=0, value=0):
    """A5/op/id/note/velocity/value低/value高/XOR，固定八字节。"""
    data = bytes((0xA5, op, identity, note, velocity, value & 255, value >> 8))
    return data + bytes((reduce(xor, data),))


class StatusParser:
    """支持分包、粘包、噪声和校验失败后的逐字节重同步。"""
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, data):
        self.buffer.extend(data)
        results = []
        while len(self.buffer) >= 2:
            if self.buffer[0] != 0xa5 or self.buffer[1] not in (0x85, 0x86, 0x87, 0x88):
                del self.buffer[0]
                continue
            if len(self.buffer) < 16:
                break
            frame = self.buffer[:16]
            if reduce(xor, frame):
                del self.buffer[0]
                continue
            del self.buffer[:16]
            if frame[1] == 0x88:
                results.append(dict(pcm=True,result=frame[2],available=bool(frame[3]&1),count=int.from_bytes(frame[4:6],'little'),
                    crc=int.from_bytes(frame[6:8],'little'),token=int.from_bytes(frame[8:10],'little'),generation=int.from_bytes(frame[10:12],'little'),metadata=frame[12]))
                continue
            if frame[1] == 0x87:
                results.append(dict(profile=True,result=frame[2],key=frame[3],count=int.from_bytes(frame[4:6],'little'),
                    crc=int.from_bytes(frame[6:8],'little'),token=int.from_bytes(frame[8:10],'little'),generation=int.from_bytes(frame[10:12],'little'),profile_version=frame[12]))
                continue
            if frame[1] == 0x86:
                results.append(dict(table=True,result=frame[2],available=bool(frame[3]&1),
                                    two_frames=bool(frame[3]&2),pair_capable=bool(frame[12]&128),
                                    query_key=32+(frame[12]&31),frame_position=int.from_bytes(frame[13:15],'little'),
                                    count=int.from_bytes(frame[4:6],'little'),
                                    crc=int.from_bytes(frame[6:8],'little'),token=int.from_bytes(frame[8:10],'little'),
                                    generation=int.from_bytes(frame[10:12],'little')))
                continue
            results.append(dict(flags=frame[2], voices=frame[3], oscillators=frame[4],
                                cycles=int.from_bytes(frame[5:7], 'little'),
                                clips=int.from_bytes(frame[7:11], 'little'),
                                samples=int.from_bytes(frame[11:15], 'little')))
        return results


def note_name(note):
    return ('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B')[note % 12] + str(note // 12 - 1)


def defaults():
    chars = '12345678QWERTYUIASDFGHJKZXCVBNM,'
    config = {'version': 2, 'keys': [dict(name=f'KEY {i+1:02}', note=48+i, velocity=96,
             keycode=188 if c == ',' else ord(c), shortcut=c) for i, c in enumerate(chars)],
            'sound': dict(attack=10.0, decay=25.3, sustain=75.0, release=75.9, volume=25.0, wave='正弦')}

    from profiles import from_sound
    for key in config['keys']:key['synth']=from_sound(config['sound'])
    return config

def validate_config(config):
    if (not isinstance(config, dict) or config.get('version') not in (1,2)
            or not isinstance(config.get('keys'), list) or len(config['keys']) != 32):
        raise ValueError('配置必须包含版本 1/2 和恰好 32 个音键。')
    used = set()
    for item in config['keys']:
        if not isinstance(item, dict):
            raise ValueError('每个音键配置必须是对象。')
        for field, low, high in [('note', 0, 127), ('velocity', 1, 127), ('keycode', 1, 255)]:
            value = item.get(field)
            if type(value) is not int or not low <= value <= high:
                raise ValueError(f'{field} 超出范围 {low}..{high}')
        code = item['keycode']
        if code in (16, 17, 18, 27, 91, 92) or code in used:
            raise ValueError('快捷键不能重复，也不能使用 Esc、修饰键或 Windows 键。')
        used.add(code)
        for field in ('name', 'shortcut'):
            if not isinstance(item.get(field), str) or not 1 <= len(item[field]) <= 24:
                raise ValueError('名称与快捷键说明需为 1..24 个字符。')
    sound = config.get('sound', {})
    if not isinstance(sound, dict):
        raise ValueError('音色配置必须是对象。')
    boost=sound.setdefault('output_boost',0)
    if type(boost) is not int or not 0<=boost<=4:
        raise ValueError('输出增益档位必须在 0..4 范围内。')
    for name, low, high in [('attack', 0, 5000), ('decay', 0, 5000), ('release', 0, 5000),
                            ('sustain', 0, 100), ('volume', 0, 100)]:
        value = sound.get(name)
        if not isinstance(value, (int, float)) or not math.isfinite(value) or not low <= value <= high:
            raise ValueError(f'{name} 参数不合法。')
    if sound.get('wave') not in WAVES:
        raise ValueError('未知波形。')
    from profiles import from_sound,validate_profile
    for key in config['keys']:
        if 'synth' not in key:key['synth']=from_sound(sound)
        validate_profile(key['synth'])
    config['version']=2
    return config


def sound_packets(sound):
    """GUI 的 D/R 时间分别以峰值到持续电平、持续电平到零为基准。"""
    sustain = round(sound['sustain'] * 65535 / 100)
    level = sustain * 4
    piano = sound['wave'] == PIANO
    # A percussive preset has S=0; release must still ramp from a nonzero attack/decay level.
    release_reference = 262143 if sound['wave'] in (PIANO, '自定义波表') else level
    def step(distance, milliseconds):
        if milliseconds == 0 or distance == 0:
            return 0
        return min(65535, max(1, round(distance / (milliseconds * SAMPLE_RATE / 1000))))
    values = {0: round(sound['volume'] * 65535 / 100), 1: step(262143, sound['attack']),
              2: step(262143-level, sound['decay']), 3: sustain, 4: step(release_reference, sound['release']),
              5: WAVES[sound['wave']], 6: 0, 7: 52428 if piano else 65535,
              8: 13107 if piano else 0, 9: 0, 10: 32, 11: 0, 12: sound.get('output_boost',0)}
    return [packet(3, identity=k, value=v) for k, v in values.items()]
