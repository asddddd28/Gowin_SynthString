"""带头/目录/逐帧 CRC 的波表库；资源文件使用 FAT 8.3 名称。"""
import binascii
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import struct

from wavetable_bank import MAX_BYTES, validate_bank, read_frame, select_pair

INDEX_HEADER = struct.Struct('<4sHHIIIIII')
ENTRY = struct.Struct('<IIIIII11sBIIIIIII')
MAX_RESOURCES = 32
MAX_INDEX_BYTES = 32 + MAX_RESOURCES * (64 + 512 * 4)


def crc32(data):
    return binascii.crc32(data) & 0xffffffff


def resource_filename(resource_id):
    if type(resource_id) is not int or not 1 <= resource_id <= 0xffffffff:
        raise ValueError('资源 ID 必须是 1..ffffffff 的整数')
    return f'{resource_id:08X}.BIN'


@dataclass(frozen=True)
class Resource:
    resource_id: int
    revision: int
    title: str
    data: bytes
    frame_crcs: tuple

    @property
    def frame_count(self):
        return len(self.frame_crcs)

    def pair(self, percent):
        first, second, fraction = select_pair(self.frame_count, percent)
        return [read_frame(self.data, first), read_frame(self.data, second)], self.job(percent)

    def job(self, percent, payload_base=0):
        """预取合同使用外部内存中载荷首地址，不包含 TSWT 的 32 字节头。"""
        if type(payload_base) is not int or payload_base < 0 or payload_base & 1 or payload_base + self.frame_count * 2048 > 2**32:
            raise ValueError('载荷地址未对齐或越过32位地址范围')
        first, second, fraction = select_pair(self.frame_count, percent)
        return dict(resource_id=self.resource_id, revision=self.revision, frame_count=self.frame_count,
                    first=first, second=second, fraction=fraction, payload_base=payload_base,
                    first_address=payload_base + first * 2048, second_address=payload_base + second * 2048,
                    first_crc=self.frame_crcs[first], second_crc=self.frame_crcs[second], frame_bytes=2048)


def make_resource(resource_id, revision, title, data):
    resource_filename(resource_id)
    if type(revision) is not int or not 1 <= revision <= 0xffffffff:
        raise ValueError('资源版本必须是非零 uint32')
    if not isinstance(title, str) or not 1 <= len(title) <= 80 or any(ord(c) < 32 for c in title):
        raise ValueError('资源名称需为1..80个可显示字符')
    data = bytes(data)
    count, _ = validate_bank(data)
    crcs = tuple(crc32(data[32 + i * 2048:32 + (i + 1) * 2048]) for i in range(count))
    return Resource(resource_id, revision, title, data, crcs)


def encode_index(resources):
    if not 1 <= len(resources) <= MAX_RESOURCES or len({r.resource_id for r in resources}) != len(resources):
        raise ValueError('资源库需包含1..32个不同资源 ID')
    entries, checksums = bytearray(), bytearray()
    for resource in resources:
        validated = make_resource(resource.resource_id, resource.revision, resource.title, resource.data)
        if validated.frame_crcs != resource.frame_crcs:
            raise ValueError('逐帧 CRC 与资源不匹配')
        filename = resource_filename(resource.resource_id).replace('.', '').encode('ascii')
        offset = 32 + len(resources) * 64 + len(checksums)
        _, payload_crc = validate_bank(resource.data)
        entry = ENTRY.pack(resource.resource_id, resource.revision, resource.frame_count, payload_crc,
                           len(resource.data), offset, filename, 0, 0, 0, 0, 0, 0, 0, 0)
        entry = entry[:36] + struct.pack('<I', crc32(entry[:36] + entry[40:])) + entry[40:]
        entries.extend(entry)
        checksums.extend(struct.pack('<' + str(resource.frame_count) + 'I', *resource.frame_crcs))
    body = bytes(entries + checksums)
    header = INDEX_HEADER.pack(b'TSLB', 1, 32, 64, len(resources), len(body), crc32(body), 0, 0)
    return header[:28] + struct.pack('<I', crc32(header[:28])) + body


def decode_index(data):
    if not 32 <= len(data) <= MAX_INDEX_BYTES:
        raise ValueError('目录长度不合法')
    magic, version, head, entry_size, count, length, checksum, reserved, head_crc = INDEX_HEADER.unpack_from(data)
    if (magic, version, head, entry_size, reserved) != (b'TSLB', 1, 32, 64, 0) or not 1 <= count <= MAX_RESOURCES:
        raise ValueError('目录头、版本或数量不合法')
    if crc32(data[:28]) != head_crc or len(data) != head + length or length < count * 64 or crc32(data[32:]) != checksum:
        raise ValueError('目录 CRC 或边界错误')
    cursor = 32 + count * 64
    result, used = [], set()
    for i in range(count):
        raw = data[32 + i * 64:32 + (i + 1) * 64]
        rid, rev, frames, payload_crc, size, offset, filename, flags, entry_crc, *reserved_fields = ENTRY.unpack(raw)
        if (rid in used or rev == 0 or not 1 <= frames <= 512 or size != 32 + frames * 2048
                or offset != cursor or cursor + frames * 4 > len(data) or flags or any(reserved_fields)
                or crc32(raw[:36] + raw[40:]) != entry_crc):
            raise ValueError('资源描述符 CRC、ID 或边界不合法')
        canonical = resource_filename(rid)
        if filename != canonical.replace('.', '').encode('ascii'):
            raise ValueError('资源文件名不匹配；只允许规范8.3名称')
        crcs = struct.unpack_from('<' + str(frames) + 'I', data, cursor)
        result.append(dict(resource_id=rid, revision=rev, frame_count=frames, payload_crc=payload_crc,
                           size=size, filename=canonical, frame_crcs=crcs))
        used.add(rid)
        cursor += frames * 4
    if cursor != len(data):
        raise ValueError('目录含额外数据')
    return result


def load_library(path):
    path = Path(path)
    folder = path if path.is_dir() else path.parent
    index = folder / 'TSINDEX.BIN'
    manifest = folder / 'TSLIB.JSN'
    if index.stat().st_size > MAX_INDEX_BYTES or manifest.stat().st_size > 1024 * 1024:
        raise ValueError('资源目录过大')
    descriptors = decode_index(index.read_bytes())
    def read_resource(name, max_bytes):
        source = folder / name
        if source.is_symlink() or source.stat().st_size > max_bytes:
            raise ValueError('资源文件无效或过大')
        return source.read_bytes()
    return decode_library(index.read_bytes(), manifest.read_bytes(), read_resource)


def decode_library(index_data, metadata_data, read_resource):
    """共享目录/资源校验；本地路径和 exFAT 块参考模型使用相同入口。"""
    if len(metadata_data) > 1024 * 1024:
        raise ValueError('资源库元数据过大')
    descriptors = decode_index(index_data)
    metadata = json.loads(metadata_data)
    if (not isinstance(metadata, dict) or type(metadata.get('version')) is not int
            or metadata['version'] != 1 or not isinstance(metadata.get('resources'), list)):
        raise ValueError('资源库元数据版本不支持')
    rows = metadata['resources']
    if len(rows) != len(descriptors) or any(not isinstance(row, dict) for row in rows):
        raise ValueError('资源库元数据数量不匹配')
    resources = []
    for desc, row in zip(descriptors, rows):
        if (type(row.get('resource_id')) is not int or type(row.get('revision')) is not int
                or (row.get('resource_id'), row.get('revision'), row.get('filename')) !=
                (desc['resource_id'], desc['revision'], desc['filename'])):
            raise ValueError('资源库元数据与二进制目录不匹配')
        raw = read_resource(desc['filename'], MAX_BYTES)
        resource = make_resource(desc['resource_id'], desc['revision'], row.get('title'), raw)
        if (len(raw) != desc['size'] or resource.frame_count != desc['frame_count']
                or validate_bank(raw)[1] != desc['payload_crc'] or resource.frame_crcs != desc['frame_crcs']
                or hashlib.sha256(raw).hexdigest() != row.get('sha256')):
            raise ValueError('目录与资源内容/逐帧 CRC 不匹配')
        resources.append(resource)
    return resources
