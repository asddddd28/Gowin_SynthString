"""把已验证的 exFAT 文件映射为受边界约束的 A/B 扇区接口。

当前受限配置：512 字节逻辑扇区、每个音序文件恰好占一个连续簇、
根目录只有普通文件。遇到未知目录、跨簇/碎片布局时拒绝写入。
这是存储控制器的参考模型，不是已经综合进 FPGA 的文件系统。
"""
from archive_model import FILE_BYTES, FILE_SECTORS, SECTOR

NAMES = ('LOOPA.SEQ', 'LOOPB.SEQ')


class ArchiveFiles:
    def __init__(self, volume, write_sector):
        self.volume = volume
        self.write_sector = write_sector
        if volume.sector_bytes != SECTOR or volume.cluster_bytes < FILE_BYTES:
            raise ValueError('需要 512 字节扇区及足够大的单簇音序文件')
        targets = []
        for name in NAMES:
            file = volume.files.get(name)
            if file is None or file.directory or not file.contiguous or file.length != FILE_BYTES or file.valid != FILE_BYTES:
                raise ValueError('音序文件必须事先完整初始化且连续分配：'+name)
            clusters = volume._file_clusters(file)
            if len(clusters) != 1:
                raise ValueError('当前硬件文件配置仅接受单簇')
            targets.append(file.first)
        if targets[0] == targets[1]:
            raise ValueError('A/B 文件共享同一个簇')
        system = set(volume._chain(volume.root_cluster, None, 4*1024*1024//volume.cluster_bytes))
        system.update(volume.bitmap_clusters)
        system.update(volume._file_clusters(volume.upcase))
        if any(cluster in system for cluster in targets):
            raise ValueError('音序文件覆盖文件系统元数据')
        for name, file in volume.files.items():
            if name in NAMES:
                continue
            if file.directory:
                raise ValueError('当前受限文件定位器不能验证子目录中的交叉分配')
            if not file.contiguous:
                raise ValueError('当前受限文件定位器不能验证其他碎片文件')
            count = (file.length+volume.cluster_bytes-1)//volume.cluster_bytes
            if any(file.first <= cluster < file.first+count for cluster in targets):
                raise ValueError('音序文件与其他文件交叉分配')
        self.starts = tuple(volume._cluster_byte(cluster)//SECTOR for cluster in targets)
        end = volume.base + volume.volume_sectors
        if any(start < volume.base or start+FILE_SECTORS > end for start in self.starts):
            raise ValueError('音序文件超出分区')

    def address(self, bank, sector):
        if type(bank) is not int or bank not in (0, 1) or type(sector) is not int or not 0 <= sector < FILE_SECTORS:
            raise ValueError('音序文件相对地址越界')
        return self.starts[bank]+sector

    def read(self, bank, sector):
        return self.volume._block(self.address(bank, sector))

    def write(self, bank, sector, data):
        address = self.address(bank, sector)
        if not isinstance(data, bytes) or len(data) != SECTOR:
            raise ValueError('只允许完整的 512 字节音序文件扇区')
        self.write_sector(address, data)
