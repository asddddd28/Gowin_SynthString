"""音序归档参考实现；只处理字节和块回调，不打开串口或物理磁盘。

事件保持 FPGA 的 90 位格式。A/B 文件必须事先在 exFAT 分配完成，
此层只在文件自身的 65 个扇区内写入，永不更新目录、FAT 或位图。
"""
from dataclasses import dataclass
import struct
import zlib

SECTOR = 512
BODY_SECTORS = 64
FILE_SECTORS = BODY_SECTORS + 1
FILE_BYTES = FILE_SECTORS * SECTOR
MAGIC = b"SYSEQAB\0"
VERSION = 1
PPQ = 960
BAR = PPQ * 4
MAX_EVENTS = 1024
PATCH_BYTES = 512
EVENT_OFFSET = 9 * SECTOR
WAVE_OFFSET = 33 * SECTOR
Q_UNITY = 1 << 26


def crc(data):
    return zlib.crc32(data) & 0xffffffff


@dataclass(frozen=True)
class Snapshot:
    bpm: int
    loop_ticks: int
    events: tuple[int, ...]
    patches: tuple[bytes, ...]
    wave: tuple[int, ...]
    controls: bytes = bytes(SECTOR)

    @property
    def slots(self):
        mask = 0
        for event in self.events:
            if event >> 78 & 1:
                mask |= 1 << (event >> 76 & 3)
        return mask

    def validate(self):
        if not 20 <= self.bpm <= 300:
            raise ValueError("BPM 超出 20..300")
        if not 0 <= self.loop_ticks < 1 << 20 or self.loop_ticks % BAR:
            raise ValueError("循环长度必须是有效的完整四拍小节")
        if len(self.events) > MAX_EVENTS or (not self.loop_ticks and self.events):
            raise ValueError("事件数/循环长度无效")
        if len(self.patches) != 4 or any(len(p) != PATCH_BYTES for p in self.patches):
            raise ValueError("必须含四个完整音色页")
        if len(self.wave) != 2048 or any(not -Q_UNITY <= x <= Q_UNITY for x in self.wave):
            raise ValueError("必须含完整 Q26 双帧波表")
        if len(self.controls) != SECTOR:
            raise ValueError("全局控制页长度错误")
        for index, event in enumerate(self.events):
            if not 0 <= event < 1 << 85:
                raise ValueError("事件保留位必须为零")
            tick = event & 0xfffff
            anchor = event >> 20 & 1023
            on = event >> 78 & 1
            if tick >= self.loop_ticks:
                raise ValueError("事件不在循环内")
            if on:
                if anchor != index:
                    raise ValueError("Note-On 配对索引不等于自身事件号")
                slot = event >> 76 & 3
                if struct.unpack_from('<I', self.patches[slot])[0] != 1:
                    raise ValueError("录音使用的音色页未提供")
            elif anchor >= index or not (self.events[anchor] >> 78 & 1):
                raise ValueError("Note-Off 没有对应的 Note-On")
        for patch in self.patches:
            valid = struct.unpack_from('<I', patch)[0]
            if valid not in (0, 1) or patch[4:16] != bytes(12) or patch[504:] != bytes(8):
                raise ValueError("音色页标志/保留位错误")
            if not valid and any(patch):
                raise ValueError("无效音色页必须全零")
            # Names are UTF-8, padded with zero; DSP parameters remain binary.
            patch[456:504].rstrip(b'\0').decode('utf-8')


def pack(snapshot, generation):
    snapshot.validate()
    if not 1 <= generation < 1 << 64:
        raise ValueError("存档代数无效，禁止回绕")
    body = bytearray(BODY_SECTORS * SECTOR)
    body[:SECTOR] = snapshot.controls
    for index, patch in enumerate(snapshot.patches):
        body[(index + 1)*SECTOR:(index + 2)*SECTOR] = patch
    for index, event in enumerate(snapshot.events):
        offset = EVENT_OFFSET + index * 12
        body[offset:offset+12] = event.to_bytes(12, 'little')
    struct.pack_into('<2048i', body, WAVE_OFFSET, *snapshot.wave)
    header = bytearray(SECTOR)
    struct.pack_into('<8sIIQIIIIIIII', header, 0, MAGIC, VERSION, FILE_BYTES,
                     generation, len(body), crc(body), snapshot.bpm,
                     snapshot.loop_ticks, len(snapshot.events), snapshot.slots, PPQ, 0x10007)
    struct.pack_into('<I', header, 508, crc(header[:508]))
    return bytes(header + body)


def unpack(data):
    if len(data) != FILE_BYTES:
        raise ValueError("音序文件长度错误")
    header, body = data[:SECTOR], data[SECTOR:]
    fields = struct.unpack_from('<8sIIQIIIIIIII', header)
    magic, version, size, generation, body_len, checksum, bpm, length, count, slots, ppq, abi = fields
    if magic != MAGIC or version != VERSION or size != FILE_BYTES or not generation:
        raise ValueError("音序文件头或版本错误")
    if any(header[56:508]) or crc(header[:508]) != struct.unpack_from('<I', header, 508)[0]:
        raise ValueError("提交头校验失败")
    if body_len != len(body) or checksum != crc(body):
        raise ValueError("音序数据 CRC 不一致")
    if count > MAX_EVENTS or ppq != PPQ or abi != 0x10007 or slots & ~15:
        raise ValueError("音序能力不兼容")
    # Undefined regions are canonical zero, including unused events.
    if any(body[5*SECTOR:EVENT_OFFSET]) or any(body[EVENT_OFFSET+count*12:WAVE_OFFSET]) or any(body[WAVE_OFFSET+8192:]):
        raise ValueError("音序保留区包含未知数据")
    snapshot = Snapshot(bpm, length,
        tuple(int.from_bytes(body[EVENT_OFFSET+i*12:EVENT_OFFSET+(i+1)*12], 'little') for i in range(count)),
        tuple(body[(i+1)*SECTOR:(i+2)*SECTOR] for i in range(4)),
        struct.unpack_from('<2048i', body, WAVE_OFFSET), body[:SECTOR])
    snapshot.validate()
    if snapshot.slots != slots:
        raise ValueError("音色槽掩码与事件不符")
    return generation, snapshot


def choose(files):
    """CRC 和语义均有效后才参与选择；同代不同内容拒绝猜测。"""
    valid = []
    for bank, data in enumerate(files):
        try:
            generation, snapshot = unpack(data)
            valid.append((generation, bank, snapshot, data))
        except (ValueError, UnicodeError, struct.error):
            pass
    if not valid:
        return None
    valid.sort(key=lambda item: item[:2])
    if len(valid) == 2 and valid[0][0] == valid[1][0] and valid[0][3] != valid[1][3]:
        raise ValueError("两份存档同代但内容不同，需人工选择")
    generation, bank, snapshot, _ = valid[-1]
    return bank, generation, snapshot


def commit(read_sector, write_sector, snapshot):
    """每次写后读回；先清备用提交头、后数据、最后新提交头。

    回调仅接受 (bank, relative_sector)；文件定位和边界验证必须由下层完成。
    任意一次失败立即退出，不把写入失败自动重试为新代数。
    """
    files = [b''.join(read_sector(bank, sector) for sector in range(FILE_SECTORS)) for bank in range(2)]
    current = choose(files)
    bank, generation = (0, 1) if current is None else (1-current[0], current[1]+1)
    image = pack(snapshot, generation)

    def verified_write(sector, data):
        write_sector(bank, sector, data)
        if read_sector(bank, sector) != data:
            raise IOError(f"音序文件 {bank} 相对扇区 {sector} 写入校验失败")

    verified_write(0, bytes(SECTOR))
    for sector in range(1, FILE_SECTORS):
        verified_write(sector, image[sector*SECTOR:(sector+1)*SECTOR])
    # Validate the complete read-back body before making it discoverable.
    readback = image[:SECTOR] + b''.join(read_sector(bank, sector) for sector in range(1, FILE_SECTORS))
    if unpack(readback) != (generation, snapshot):
        raise IOError("提交前完整数据验证失败")
    verified_write(0, image[:SECTOR])
    return bank, generation
