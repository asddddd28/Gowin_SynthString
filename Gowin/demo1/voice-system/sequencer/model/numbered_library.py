"""编号音序/预设目录参考模型；不打开设备，不分配或修改文件系统元数据。

接受预分配、完整初始化的文件，在文件范围内提交。每次保存使用新编号，
旧音序绝不原地覆盖。删除写入校验墓碑，不回收编号。设备块驱动尚需接入。
"""
from dataclasses import dataclass
import re
import struct
from archive_model import SECTOR, FILE_BYTES, FILE_SECTORS, Snapshot, crc, pack, unpack

SEQUENCE_DIR = 'SEQUENCES'
PRESET_DIR = 'PRESETS'
PRESET_BYTES = 18*SECTOR
TOMBSTONE = b'SYDELETE'


def pack_preset(name, patch, wave):
    title = name.encode('utf-8')
    if not title or len(title) > 48 or b'\0' in title or int.from_bytes(patch[:4],'little') != 1:
        raise ValueError('预设名称或音色页无效')
    Snapshot(120,0,(),(patch,bytes(512),bytes(512),bytes(512)),tuple(wave)).validate()
    body = patch+struct.pack('<2048i',*wave)
    header = bytearray(SECTOR)
    struct.pack_into('<8sIIII',header,0,b'SYPRESET',1,PRESET_BYTES,crc(body),0x10007)
    header[32:32+len(title)] = title
    struct.pack_into('<I',header,508,crc(header[:508]))
    return bytes(header)+body


def unpack_preset(image):
    if len(image) != PRESET_BYTES:
        raise ValueError('预设文件长度错误')
    header, body = image[:SECTOR], image[SECTOR:]
    magic,version,size,checksum,abi = struct.unpack_from('<8sIIII',header)
    if (magic,version,size,abi) != (b'SYPRESET',1,PRESET_BYTES,0x10007) or checksum != crc(body):
        raise ValueError('预设文件版本或内容CRC错误')
    if any(header[24:32]) or any(header[80:508]) or crc(header[:508]) != int.from_bytes(header[508:],'little'):
        raise ValueError('预设提交头无效')
    title = header[32:80].rstrip(b'\0').decode('utf-8')
    patch, wave = body[:512], struct.unpack_from('<2048i',body,512)
    if pack_preset(title,patch,wave) != image:
        raise ValueError('预设不是规范编码')
    return title, patch, wave


@dataclass(frozen=True)
class Entry:
    number: int
    name: str
    state: str
    bpm: int = 0
    bars: int = 0
    events: int = 0


class NumberedLibrary:
    """先验证整棵目录的分配不交叉，再授予两个目录中的有界写入能力。"""
    def __init__(self, volume, write_sector):
        self.volume = volume
        self.write_sector = write_sector
        if volume.sector_bytes != SECTOR or volume.unsupported_names:
            raise ValueError('音序库需要512字节逻辑扇区和可验证的ASCII目录')
        owners = {}

        def claim(clusters, name):
            for cluster in clusters:
                if cluster in owners:
                    raise ValueError('交叉分配：'+name+' / '+owners[cluster])
                owners[cluster] = name

        claim(volume._chain(volume.root_cluster, None, 4*1024*1024//volume.cluster_bytes), '/')
        claim(volume.bitmap_clusters, '$BITMAP')
        claim(volume._file_clusters(volume.upcase), '$UPCASE')
        self.folders = {}
        budget = [4096]

        def visit(files, parent, depth):
            if depth > 8:
                raise ValueError('目录嵌套过深')
            for name, file in files.items():
                budget[0] -= 1
                if budget[0] < 0:
                    raise ValueError('目录项超出受限扫描容量')
                path = parent+'/'+name
                claim(volume._file_clusters(file), path)
                if file.directory:
                    children = volume.list_directory(file)
                    if parent == '' and name in (SEQUENCE_DIR, PRESET_DIR):
                        self.folders[name] = children
                    visit(children, path, depth+1)
        visit(volume.files, '', 0)
        if set(self.folders) != {SEQUENCE_DIR, PRESET_DIR}:
            raise ValueError('请先准备 SEQUENCES 与 PRESETS 文件夹')
        self.targets = {}
        for folder, extension, size in ((SEQUENCE_DIR,'SSQ',FILE_BYTES),(PRESET_DIR,'SSP',PRESET_BYTES)):
            for name, file in self.folders[folder].items():
                match = re.fullmatch(r'([0-9]{8})\.'+extension, name)
                if not match:
                    continue
                number = int(match[1])
                if number == 0 or file.directory or file.valid != size or file.length != size:
                    raise ValueError('编号文件长度或类型错误：'+name)
                clusters = volume._file_clusters(file)
                # Fragmented files are mapped through their checked cluster list;
                # no 32-bit byte-address truncation and no raw fixed LBA writes.
                addresses = []
                for cluster in clusters:
                    start = volume._cluster_byte(cluster)//SECTOR
                    addresses.extend(range(start, start+volume.cluster_bytes//SECTOR))
                self.targets[(folder,number)] = tuple(addresses[:size//SECTOR])

    def _read(self, folder, number):
        return b''.join(self.volume._block(lba) for lba in self.targets[(folder,number)])

    def _write(self, folder, number, sector, data):
        addresses = self.targets[(folder,number)]
        if type(sector) is not int or not 0 <= sector < len(addresses) or len(data) != SECTOR:
            raise ValueError('文件相对扇区越界')
        lba = addresses[sector]
        self.write_sector(lba, data)
        if self.volume._block(lba) != data:
            raise IOError('SD写入读回校验失败')

    def sequences(self):
        entries = []
        for folder, number in sorted(self.targets):
            if folder != SEQUENCE_DIR:
                continue
            image = self._read(folder, number)
            state = 'damaged'
            if not any(image):
                state = 'empty'
            elif image[:8] == TOMBSTONE and int.from_bytes(image[8:12],'little') == number and crc(image[:508]) == int.from_bytes(image[508:512],'little'):
                state = 'deleted'
            else:
                try:
                    generation, snapshot = unpack(image)
                    if generation != number:
                        raise ValueError('编号与文件不一致')
                    entries.append(Entry(number,f'{number:08}.SSQ','ready',snapshot.bpm,snapshot.loop_ticks//3840,len(snapshot.events)))
                    continue
                except (ValueError,UnicodeError,struct.error):
                    pass
            entries.append(Entry(number,f'{number:08}.SSQ',state))
        return entries

    def save(self, snapshot):
        snapshot.validate()
        if snapshot.loop_ticks == 0:
            raise ValueError('没有完整小节，不能保存')
        entries = self.sequences()
        last = max((e.number for e in entries if e.state != 'empty'), default=0)
        number = last+1
        if number > 99999999 or not any(e.number == number and e.state == 'empty' for e in entries):
            raise ValueError('下一个编号未预分配，请先扩展SD音序目录')
        image = pack(snapshot, number)
        # A nonzero invalid header reserves the new number even if power drops
        # before the first body write. Prior valid files remain untouched.
        staging = b'SYSTAGE!'+number.to_bytes(4,'little')+bytes(500)
        self._write(SEQUENCE_DIR, number, 0, staging)
        for sector in range(1, FILE_SECTORS):
            self._write(SEQUENCE_DIR, number, sector, image[sector*SECTOR:(sector+1)*SECTOR])
        readback = image[:SECTOR]+self._read(SEQUENCE_DIR, number)[SECTOR:]
        if unpack(readback) != (number,snapshot):
            raise IOError('提交前完整音序校验失败')
        self._write(SEQUENCE_DIR, number, 0, image[:SECTOR])
        return number

    def load(self, number):
        generation, snapshot = unpack(self._read(SEQUENCE_DIR,number))
        if generation != number:
            raise ValueError('文件名与内部编号不符')
        return snapshot

    def delete(self, number):
        self.load(number)  # Cannot delete an unrecognized/corrupt file silently.
        header = bytearray(SECTOR)
        header[:8] = TOMBSTONE
        struct.pack_into('<I',header,8,number)
        struct.pack_into('<I',header,508,crc(header[:508]))
        self._write(SEQUENCE_DIR,number,0,bytes(header))

    def select(self, current=None, step=0):
        """默认最新编号；到边界停住，跳过删除/损坏/尚未写入的文件。"""
        available = [e.number for e in self.sequences() if e.state == 'ready']
        if not available:
            return None
        if current not in available:
            return available[-1]
        return available[max(0,min(len(available)-1,available.index(current)+step))]

    def presets(self):
        result = []
        for folder,number in sorted(self.targets):
            if folder == PRESET_DIR:
                try:
                    title,_,_ = unpack_preset(self._read(folder,number))
                    result.append((number,title))
                except (ValueError,UnicodeError,struct.error):
                    pass
        return result

    def upload_preset(self, number, name, patch, wave):
        image = pack_preset(name,patch,wave)
        if any(self._read(PRESET_DIR,number)):
            raise ValueError('目标预设编号已占用，请使用空编号')
        self._write(PRESET_DIR,number,0,b'SYSTAGE!'+bytes(504))
        for sector in range(1,PRESET_BYTES//SECTOR):
            self._write(PRESET_DIR,number,sector,image[sector*SECTOR:(sector+1)*SECTOR])
        if unpack_preset(image[:SECTOR]+self._read(PRESET_DIR,number)[SECTOR:]) != (name,patch,tuple(wave)):
            raise IOError('预设提交前验证失败')
        self._write(PRESET_DIR,number,0,image[:SECTOR])

    def load_preset(self, number):
        return unpack_preset(self._read(PRESET_DIR,number))
