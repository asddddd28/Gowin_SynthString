"""Single-cycle tables and a bounded, acknowledged UART upload transaction."""
import binascii
import json
import math
import secrets
import struct
from pathlib import Path
from protocol import packet

TABLE_SIZE = 1024

def validate_samples(samples):
    if not isinstance(samples, list) or len(samples) != TABLE_SIZE:
        raise ValueError('波表必须恰好包含 1024 个有符号 16 位整数。')
    if any(type(x) is not int or not -32768 <= x <= 32767 for x in samples):
        raise ValueError('每个采样点必须是 -32768..32767 的整数。')
    return samples

def load_surge_frames(path):
    """读取 Surge 的 vawt 文件，保留所有帧供用户明确选择。"""
    path = Path(path)
    if path.suffix.lower() == '.wav':
        return load_surge_wav(path)
    if path.stat().st_size > 8 * 1024 * 1024 + 12:
        raise ValueError('Surge 波表超过 8 MiB。')
    raw = path.read_bytes()
    if len(raw) < 12:
        raise ValueError('Surge 波表头被截断。')
    tag, size, count, flags = struct.unpack_from('<4sIHH', raw)
    if tag != b'vawt' or not 16 <= size <= 4096 or size & (size - 1) or not 1 <= count <= 512:
        raise ValueError('Surge 波表标记、帧长或帧数不合法。')
    if flags & ~15 or flags & 3 or (flags & 8 and not flags & 4):
        raise ValueError('这里只支持单周期波表；采样模式、循环采样或未知格式不能直接导入。')
    integer = bool(flags & 4)
    width = 2 if integer else 4
    payload_end = 12 + size * count * width
    if len(raw) != payload_end:
        raise ValueError('Surge 波表数据长度不匹配。')
    values = struct.unpack_from('<' + str(size * count) + ('h' if integer else 'f'), raw, 12)
    scale = 32768 if flags & 8 else 16384
    normalized = [v / scale if integer else v for v in values]
    if any(not math.isfinite(v) or not -1 <= v <= 1 for v in normalized):
        raise ValueError('Surge 波表含有非有限值或超过满幅的数据，请先在软件中归一化。')
    return [normalized[start:start + size] for start in range(0, len(normalized), size)]


def load_surge_wav(path):
    """读取带 srge 周期元数据的单声道 WAV；拒绝把普通录音猜成波表。"""
    if path.stat().st_size > 8 * 1024 * 1024 + 4096:
        raise ValueError('Surge WAV 波表超过大小限制。')
    raw = path.read_bytes()
    if len(raw) < 12 or raw[:4] != b'RIFF' or raw[8:12] != b'WAVE':
        raise ValueError('不是 RIFF WAVE 文件。')
    declared = struct.unpack_from('<I', raw, 4)[0] + 8
    # 本项目固定 Surge 导出器把 fmt 的 RIFF 总长度多计两字节；各 chunk 仍须完整。
    if declared not in (len(raw), len(raw) + 2):
        raise ValueError('WAV 文件总长度不匹配。')
    chunks = {}
    position = 12
    while position < len(raw):
        if position + 8 > len(raw):
            raise ValueError('WAV chunk 头被截断。')
        tag, size = struct.unpack_from('<4sI', raw, position)
        position += 8
        if position + size > len(raw):
            raise ValueError('WAV chunk 数据被截断。')
        if tag in chunks:
            raise ValueError('WAV 含有重复的 chunk。')
        chunks[tag] = raw[position:position + size]
        position += size + (size & 1)
        if position > len(raw):
            raise ValueError('WAV 缺少对齐字节。')
    if b'srge' not in chunks or b'srgo' in chunks or len(chunks[b'srge']) != 8:
        raise ValueError('需要 Surge 单周期波表元数据 srge；普通 WAV 和采样录音不支持此入口。')
    version, size = struct.unpack('<II', chunks[b'srge'])
    fmt = chunks.get(b'fmt ', b'')
    data = chunks.get(b'data', b'')
    if len(fmt) < 16:
        raise ValueError('WAV 缺少格式参数。')
    encoding, channels, _, _, _, bits = struct.unpack_from('<HHIIHH', fmt)
    if version != 1 or not 16 <= size <= 4096 or size & (size - 1) or channels != 1 or (encoding, bits) not in ((3, 32), (1, 16)):
        raise ValueError('仅支持单声道浮点 32 位或 PCM 16 位的 Surge 波表。')
    width = bits // 8
    if not data or len(data) % (size * width) or len(data) // (size * width) > 512:
        raise ValueError('WAV 波表帧数据长度不合法。')
    values = struct.unpack('<' + str(len(data) // width) + ('f' if encoding == 3 else 'h'), data)
    normalized = [v if encoding == 3 else v / 32768 for v in values]
    if any(not math.isfinite(v) or not -1 <= v <= 1 for v in normalized):
        raise ValueError('WAV 波表需要有限且不超过满幅的采样值。')
    return [normalized[start:start + size] for start in range(0, len(normalized), size)]


def resample_frame(frame):
    """环形线性重采样到硬件 1024 点；不改变音色帧的选择。"""
    samples = []
    for i in range(TABLE_SIZE):
        position = i * len(frame) / TABLE_SIZE
        index = int(position)
        fraction = position - index
        value = frame[index] * (1 - fraction) + frame[(index + 1) % len(frame)] * fraction
        samples.append(max(-32768, min(32767, round(value * 32768))))
    return validate_samples(samples)


def load_table(path, frame_index=0):
    path = Path(path)
    if path.suffix.lower() in ('.wt', '.wav'):
        frames = load_surge_frames(path)
        if type(frame_index) is not int or not 0 <= frame_index < len(frames):
            raise ValueError('请选择有效的 Surge 波表帧。')
        return resample_frame(frames[frame_index])
    if path.stat().st_size > 1024*1024:
        raise ValueError('波表文件过大（上限 1 MiB）。')
    if path.suffix.lower() == '.json':
        value = json.loads(path.read_text(encoding='utf-8-sig'))
        return validate_samples(value.get('samples') if isinstance(value, dict) else value)
    if path.suffix.lower() in ('.csv', '.txt'):
        text = path.read_text(encoding='utf-8-sig').replace(',', ' ')
        return validate_samples([int(x) for x in text.split()])
    raise ValueError('支持 Surge WT、JSON 数组或包含 1024 个整数的 CSV/TXT 单周期波表。')

def table_crc(samples):
    data = b''.join(x.to_bytes(2, 'little', signed=True) for x in samples)
    return binascii.crc_hqx(data, 0xffff)

def harmonic_piano_table():
    # Static harmonic recipe, not a full piano recording or a time-varying model.
    values = [sum(a*math.sin(2*math.pi*h*i/TABLE_SIZE) for h,a in
                  ((1,1.0),(2,.32),(3,.18),(4,.09),(5,.045),(6,.02))) for i in range(TABLE_SIZE)]
    peak = max(abs(x) for x in values)
    return [round(30000*x/peak) for x in values]

class TableTransfer:
    total_size = TABLE_SIZE
    begin_op, data_op, commit_op, abort_op = 0x10, 0x11, 0x12, 0x13
    require_pair = False
    def validate_data(self, samples):
        return validate_samples(list(samples))

    def __init__(self, samples, now, token=None):
        self.samples = tuple(self.validate_data(samples))
        self.crc = table_crc(self.samples)
        self.token = token or secrets.randbelow(65535)+1
        self.state = 'probe'
        self.count = 0
        self.expected = 0
        self.generation = None
        self.deadline = now + 3
        self.query_at = 0
        self.done = False
        self.error = None

    def advance(self, now, status=None):
        if self.done or self.error:
            return []
        if now > self.deadline:
            self.error = ('波表应答超时；请确认已烧录支持上传的新程序。' if self.state == 'probe'
                          else ('提交结果未确认；请重新上传以确认最终波表。' if self.state=='commit' else '波表上传超时，旧表保留；请重试。'))
            return [] if self.state == 'probe' else [packet(self.abort_op)]
        if status is not None:
            if self.state == 'probe':
                if self.require_pair and not status.get('pair_capable', False):
                    self.error='当前固件不支持双帧波表，请烧录 pair 版本；尚未发送资源数据。'
                    return []
                self.generation = status['generation']
                self.state = 'begin'; self.deadline = now+3; self.query_at=now+.2
                return [packet(self.begin_op,value=self.token),packet(0x16)]
            if status['token'] != self.token:
                return []
            if status['result'] == 4:
                self.error='FPGA 拒绝波表（顺序、长度或 CRC 错误），旧表保留。'
                return [packet(self.abort_op)]
            if self.state in ('begin','block') and status['result']==1 and status['count']==self.expected:
                if status['crc'] != table_crc(self.samples[:self.expected]):
                    self.error='FPGA 波表 CRC 与电脑不一致，旧表保留。'
                    return [packet(self.abort_op)]
                self.count=self.expected
                self.deadline=now+3;self.query_at=now+.2
                if self.count==self.total_size:
                    self.state='commit'
                    return [packet(self.commit_op,self.token&255,self.token>>8,value=self.crc),packet(0x16)]
                end=min(self.count+32,self.total_size)
                frames=[packet(self.data_op,i&255,i>>8,value=self.samples[i]&65535) for i in range(self.count,end)]
                self.expected=end;self.state='block'
                return frames+[packet(0x16)]
            if self.state=='commit' and status['result']==3 and status['available'] and status['crc']==self.crc and status['count']==self.total_size and status['generation']==((self.generation+1)&65535) and (not self.require_pair or status.get('two_frames',False)):
                self.done=True;return []
        if now>=self.query_at:
            self.query_at=now+.2
            return [packet(0x16)]
        return []


class PairTransfer(TableTransfer):
    """两个1024点周期；能力探测后才发送新命令，保留分块CRC和提交确认。"""
    total_size = 2 * TABLE_SIZE
    begin_op, data_op, commit_op, abort_op = 0x40, 0x41, 0x42, 0x43
    require_pair = True

    def __init__(self, frames, now, token=None):
        if len(frames) != 2:
            raise ValueError('双帧工作集必须恰好包含两个周期。')
        values=[validate_samples(list(frame)) for frame in frames]
        super().__init__(values[0] + values[1], now, token)

    def validate_data(self, samples):
        if len(samples) != 2 * TABLE_SIZE:
            raise ValueError('双帧必须包含2048个样点。')
        return validate_samples(list(samples[:TABLE_SIZE])) + validate_samples(list(samples[TABLE_SIZE:]))


class PositionTransfer:
    """逐键位置写入并回读；旧固件仅允许缺省零位置。"""
    def __init__(self, positions, now):
        self.positions=list(positions)
        if not self.positions or any(type(k) is not int or not 32<=k<64 or type(v) is not int or not 0<=v<=65535 for k,v in self.positions):
            raise ValueError('帧位置必须使用有效音键和0..65535整数。')
        self.count=0;self.state='probe';self.deadline=now+3;self.query_at=0
        self.done=False;self.error=None

    def advance(self, now, status=None):
        if self.done or self.error:return []
        if now>self.deadline:
            self.error='逐键参数已上传，但帧位置回读超时；位置未确认，请重新上传。'
            return []
        key,value=self.positions[self.count]
        if status is not None:
            if self.state=='probe':
                if not status.get('pair_capable',False):
                    if all(v==0 for _,v in self.positions):self.done=True
                    else:self.error='逐键参数已上传，但当前固件不支持帧位置；请烧录 pair 版本。'
                    return []
                self.state='write';self.deadline=now+3;self.query_at=now+.2
                return [packet(0x44,key,value=value),packet(0x46,key)]
            if status.get('query_key')==key and status.get('frame_position')==value:
                self.count+=1
                if self.count==len(self.positions):self.done=True;return []
                key,value=self.positions[self.count];self.deadline=now+3;self.query_at=now+.2
                return [packet(0x44,key,value=value),packet(0x46,key)]
        if now>=self.query_at:
            self.query_at=now+.2
            return [packet(0x16) if self.state=='probe' else packet(0x46,key)]
        return []
