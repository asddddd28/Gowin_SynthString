"""TSWT 周期资源编解码和有界相邻帧选择；文件格式与旧离线工具相同。"""
import binascii
import math
import struct

HEADER = struct.Struct('<4sHHIIIIII')
FRAME_SIZE = 1024
MAX_FRAMES = 512
MAX_BYTES = HEADER.size + FRAME_SIZE * MAX_FRAMES * 2


def encode_bank(frames):
    if not isinstance(frames, list) or not 1 <= len(frames) <= MAX_FRAMES:
        raise ValueError('帧数必须在 1..512')
    values = []
    for frame in frames:
        if not isinstance(frame, list) or len(frame) != FRAME_SIZE:
            raise ValueError('每帧必须有 1024 点')
        if any(type(value) is not int or not -32768 <= value <= 32767 for value in frame):
            raise ValueError('样值必须为 int16 整数')
        values.extend(frame)
    payload = struct.pack('<' + str(len(values)) + 'h', *values)
    return HEADER.pack(b'TSWT', 1, HEADER.size, FRAME_SIZE, len(frames), 1, len(values),
                       len(payload), binascii.crc32(payload) & 0xffffffff) + payload


def validate_bank(data):
    """先验证完整资源，再允许按索引取帧；保留原 TSWT v1 的严格长度规则。"""
    if not HEADER.size <= len(data) <= MAX_BYTES:
        raise ValueError('资源文件长度不合法')
    magic, version, head, size, count, encoding, samples, length, crc = HEADER.unpack_from(data)
    if magic != b'TSWT' or version != 1 or head != HEADER.size or encoding != 1:
        raise ValueError('资源版本或编码不支持')
    if size != FRAME_SIZE or not 1 <= count <= MAX_FRAMES:
        raise ValueError('帧尺寸或帧数不合法')
    if samples != size * count or length != samples * 2 or len(data) != head + length:
        raise ValueError('资源边界不一致')
    if binascii.crc32(data[head:]) & 0xffffffff != crc:
        raise ValueError('资源 CRC 不匹配')
    return count, crc


def decode_bank(data):
    count, _ = validate_bank(data)
    return [read_frame(data, index) for index in range(count)]


def read_frame(data, index):
    """调用者先执行完整 validate_bank；只解包所需的 2048 字节。"""
    if type(index) is not int or index < 0 or HEADER.size + (index + 1) * 2048 > len(data):
        raise ValueError('帧索引越界')
    return list(struct.unpack_from('<1024h', data, HEADER.size + index * 2048))


def select_pair(frame_count, percent):
    """整张表的百分比先量化为帧坐标 Q16；末帧用同一帧作两端，位置零。"""
    if type(frame_count) is not int or not 1 <= frame_count <= MAX_FRAMES:
        raise ValueError('帧数必须在 1..512')
    if type(percent) not in (int, float) or not math.isfinite(percent) or not 0 <= percent <= 100:
        raise ValueError('资源位置必须是 0..100 的有限数值')
    coordinate = round(percent * (frame_count - 1) * 65536 / 100)
    first, fraction = divmod(coordinate, 65536)
    second = min(first + 1, frame_count - 1)
    return first, second, fraction
