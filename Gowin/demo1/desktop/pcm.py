"""PCM sample image validation and CRC-confirmed bounded UART transfer."""
import binascii
import json
import secrets
from pathlib import Path
from protocol import packet

def validate_image(image):
    if not isinstance(image,dict) or image.get('format')!='tang-pcm-v1' or image.get('sample_rate')!=24000:
        raise ValueError('请选择 tang-pcm-v1 格式的 24 kHz 钢琴采样 JSON。')
    samples=image.get('samples')
    if not isinstance(samples,list) or not 512<=len(samples)<=16384 or any(type(v) is not int or not -32768<=v<=32767 for v in samples):
        raise ValueError('PCM 必须包含 512..16384 个 16 位有符号采样点。')
    for k in ('loop_start','loop_end','root_note'):
        if type(image.get(k)) is not int:raise ValueError(f'{k} 必须为整数')
    if not 0<=image['loop_start']<image['loop_end']<=len(samples) or image['loop_end']-image['loop_start']<512 or not 0<=image['root_note']<=127:
        raise ValueError('循环范围或原始音高无效；循环长度至少512点。')
    return image

def load_image(path):
    p=Path(path)
    if p.stat().st_size>1024*1024:raise ValueError('采样 JSON 不得超过 1 MiB。')
    return validate_image(json.loads(p.read_text(encoding='utf-8-sig')))

def metadata(image):return [len(image['samples']),image['loop_start'],image['loop_end'],image['root_note']]
def crc_words(words):return binascii.crc_hqx(b''.join((v&65535).to_bytes(2,'little') for v in words),0xffff)

class PcmTransfer:
    kind='pcm'
    def __init__(self,image,now):
        validate_image(image)
        self.meta=metadata(image);self.samples=tuple(image['samples']);self.count=0;self.expected=0
        self.crc=crc_words(self.meta+list(self.samples));self.token=secrets.randbelow(65535)+1
        self.state='probe';self.generation=0;self.done=False;self.error=None;self.deadline=now+5;self.query_at=0
    def advance(self,now,status=None):
        if self.done or self.error:return []
        if now>self.deadline:
            self.error='PCM 上传超时：确认已烧录采样版固件、板载按键已松开。单缓冲接收开始后旧采样失效，请重传。'
            return [] if self.state=='probe' else [packet(0x33)]
        if status is not None:
            if self.state=='probe':
                self.generation=status['generation'];self.state='begin';self.deadline=now+5;self.query_at=now+.2
                return [packet(0x30,value=self.token),packet(0x36)]
            if status['token']!=self.token:return []
            if status['result']==4:
                self.error='FPGA 拒绝 PCM 的顺序、元数据或 CRC；采样不可用，请重新上传。';return [packet(0x33)]
            if self.state=='begin' and status['result']==1 and status['count']==0 and status.get('metadata',0)==0:
                self.state='block';self.expected=0;self.deadline=now+5;self.query_at=now+.2
                return [packet(0x34,i,value=v) for i,v in enumerate(self.meta)]+[packet(0x36)]
            if self.state=='block' and status['result']==1 and status.get('metadata')==4 and status['count']==self.expected:
                if status['crc']!=crc_words(self.meta+list(self.samples[:self.expected])):
                    self.error='PCM 校验不一致；请重传。';return [packet(0x33)]
                self.count=self.expected;self.deadline=now+5;self.query_at=now+.2
                if self.count==len(self.samples):
                    self.state='commit';return [packet(0x32,self.token&255,self.token>>8,value=self.crc),packet(0x36)]
                end=min(self.count+32,len(self.samples));self.expected=end
                return [packet(0x31,i&255,i>>8,value=self.samples[i]&65535) for i in range(self.count,end)]+[packet(0x36)]
            if self.state=='commit' and status['result']==3 and status['available'] and status['count']==len(self.samples) and status['crc']==self.crc and status['generation']==((self.generation+1)&65535):
                self.done=True;return []
        if now>=self.query_at:self.query_at=now+.2;return [packet(0x36)]
        return []
