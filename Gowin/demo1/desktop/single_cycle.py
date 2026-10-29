"""显式单周期PCM16 WAV入口；不把普通录音自动猜成波表。"""
import io
import struct
import wave

from wavetable import resample_frame


def convert_cycle(raw):
    if not isinstance(raw,bytes) or len(raw)>64*1024:
        raise ValueError('单周期WAV需为64KiB以内的字节数据')
    try:
        with wave.open(io.BytesIO(raw),'rb') as source:
            count=source.getnframes()
            if (source.getnchannels()!=1 or source.getsampwidth()!=2 or source.getcomptype()!='NONE'
                    or not 16<=count<=4096 or not 8000<=source.getframerate()<=192000):
                raise ValueError('仅支持16..4096点、单声道PCM16单周期WAV')
            payload=source.readframes(count)
            rate=source.getframerate()
    except (wave.Error,EOFError) as error:
        raise ValueError('WAV格式错误或截断') from error
    if len(payload)!=count*2: raise ValueError('WAV样点被截断')
    values=struct.unpack('<'+str(count)+'h',payload)
    dc=sum(values)/count
    peak=max(abs(v-dc) for v in values)
    if peak<1: raise ValueError('单周期没有可用的交流信号')
    normalized=[(v-dc)*.90/peak for v in values]
    samples=resample_frame(normalized)
    return samples,dict(source_samples=count,source_rate=rate,source_bits=16,
        output_samples=1024,output_bits=16,removed_dc=dc,normalization_peak=.90,
        resampling='periodic linear interpolation',mip_bandlimited=False)
