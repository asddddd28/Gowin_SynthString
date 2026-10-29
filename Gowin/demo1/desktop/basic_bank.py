"""基础音色目录和资源绑定；软件音色ID不会假装成为固件资源ID。"""
from dataclasses import dataclass
import copy
import hashlib
import io
import json
from pathlib import Path
import re
import wave

from profiles import validate_profile
from wavetable_bank import read_frame
from wavetable_library import load_library


def required_features(profile, resource_id):
    features=['voice_allocator','pitch_phase','amplitude_adsr','velocity_gain','per_key_profile']
    mode=profile['mode']
    if mode in ('FM / PM','AM','环形调制'):
        features+=['second_oscillator','modulation_adsr',{'FM / PM':'fm_pm','AM':'am','环形调制':'ring_modulation'}[mode]]
    elif profile['gain_b']>0:
        features+=['second_oscillator','oscillator_mix']
    if resource_id is not None:
        features+=['periodic_wavetable','linear_interpolation','double_bank_commit','uart_resource_upload']
    if profile['wave_a']!='自定义波表' or profile['wave_b']!='自定义波表':
        features+=['basic_waveform']
    return sorted(features+['uart_profile_confirmation'])


@dataclass(frozen=True)
class Timbre:
    timbre_id: int
    title: str
    category: str
    description: str
    profile: dict
    resource_id: object
    requirements: tuple
    preview: Path
    samples: object

    def upload(self):
        profile=copy.deepcopy(self.profile)
        frames=None if self.samples is None else [list(self.samples),list(self.samples)]
        return profile,frames


def load_basic_bank(path):
    path=Path(path)
    if path.is_dir():path=path/'BASICS.JSN'
    if path.stat().st_size>1024*1024: raise ValueError('音色目录过大')
    data=json.loads(path.read_text(encoding='utf-8'))
    if (not isinstance(data,dict) or data.get('format')!='tang-basic-bank-v1'
            or type(data.get('version')) is not int or data['version']!=1
            or not isinstance(data.get('timbres'),list) or not 1<=len(data['timbres'])<=32):
        raise ValueError('基础音色库格式或版本错误')
    resources={r.resource_id:r for r in load_library(path.parent)}
    result=[];seen=set()
    for row in data['timbres']:
        if not isinstance(row,dict): raise ValueError('音色描述错误')
        tid=row.get('timbre_id')
        if type(tid) is not int or not 1<=tid<=65535 or tid in seen: raise ValueError('音色ID错误或重复')
        for field in ('title','category','description'):
            value=row.get(field)
            if not isinstance(value,str) or not 1<=len(value)<=500 or any(ord(c)<32 for c in value):
                raise ValueError('音色说明无效：'+field)
        profile=copy.deepcopy(row.get('profile'));validate_profile(profile)
        if profile['mode']=='采样钢琴': raise ValueError('第一批基础库不包含PCM采样模式')
        rid=row.get('resource_id')
        custom='自定义波表' in (profile['wave_a'],profile['wave_b'])
        if (rid is not None and (type(rid) is not int or rid not in resources)) or custom!=(rid is not None):
            raise ValueError('音色波形与资源引用不一致')
        resource=None if rid is None else resources[rid]
        if resource is not None and (resource.frame_count!=1 or row.get('resource_sha256')!=hashlib.sha256(resource.data).hexdigest()):
            raise ValueError('基础音色只支持校验过的单周期资源')
        expected=required_features(profile,rid)
        if row.get('requirements')!=expected: raise ValueError('音色功能需求与参数不一致')
        filename=row.get('preview_file')
        if not isinstance(filename,str) or not re.fullmatch(r'P[0-9A-F]{7}\.WAV',filename):
            raise ValueError('试听文件名错误')
        preview=path.parent/filename
        if preview.is_symlink() or not 44<=preview.stat().st_size<=1024*1024:
            raise ValueError('试听文件无效或过大')
        audio=preview.read_bytes()
        if hashlib.sha256(audio).hexdigest()!=row.get('preview_sha256'):
            raise ValueError('试听文件校验错误')
        try:
            with wave.open(io.BytesIO(audio),'rb') as wav:
                if (wav.getnchannels()!=1 or wav.getsampwidth()!=2 or wav.getframerate()!=24000
                        or wav.getcomptype()!='NONE' or wav.getnframes()==0
                        or len(wav.readframes(wav.getnframes()))!=2*wav.getnframes()):
                    raise ValueError('试听需为完整的24kHz单声道PCM16参考音频')
        except (wave.Error,EOFError) as error:
            raise ValueError('试听WAV结构错误') from error
        result.append(Timbre(tid,row['title'],row['category'],row['description'],profile,rid,
                            tuple(expected),preview,None if resource is None else tuple(read_frame(resource.data,0))))
        seen.add(tid)
    return result
