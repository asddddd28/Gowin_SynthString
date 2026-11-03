"""Prepare exFAT in a bounded RAM image. This module never opens hardware.

FATtools supplies the formatter/file writer. The independent existing exFAT
reader verifies geometry, both boot checksums, directory checksums and files.
The standard exfatprogs up-case table avoids locale-dependent formatting.
"""
from pathlib import Path
import hashlib,json,sys,zipfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'reports/sequencer/sd-format-20261103'
DIAG=ROOT.parents[1]/'demo_test/diagnostics/sd_card'
sys.path.insert(0,str(DIAG/'.venv/Lib/site-packages'))
sys.path.insert(0,str(ROOT.parent/'model'))
from FATtools import mkfat,Volume
from exfat_reference import ExfatVolume,rolling

BASE=2048
SECTORS=122503168
CAPACITY=122507264


class MemoryVolume:
    mode='r+b'
    name='bounded-exfat-plan'
    mbr=None
    def __init__(self,blocks=None):
        self.size=SECTORS*512
        self.pos=0
        self.blocks={} if blocks is None else dict(blocks)
        self.closed=False
    def seek(self,offset,whence=0):
        pos=offset+(0 if whence==0 else self.pos if whence==1 else self.size)
        if whence not in (0,1,2) or not 0<=pos<=self.size:raise ValueError('Out of volume seek')
        self.pos=pos
        return pos
    def tell(self):return self.pos
    def read(self,size=-1):
        if size<0 or size>16*1024*1024 or self.pos+size>self.size:raise ValueError('Unbounded read')
        result=bytearray()
        while size:
            lba,offset=divmod(self.pos,512);take=min(size,512-offset)
            result+=self.blocks.get(lba,bytes(512))[offset:offset+take]
            self.pos+=take;size-=take
        return result
    def write(self,data):
        size=len(data)
        if self.pos+size>self.size:raise ValueError('Out of volume write')
        source=memoryview(data);done=0
        while done<size:
            lba,offset=divmod(self.pos,512);take=min(size-done,512-offset)
            block=bytearray(self.blocks.get(lba,bytes(512)))
            block[offset:offset+take]=source[done:done+take]
            self.blocks[lba]=bytes(block);self.pos+=take;done+=take
        return size
    def flush(self):pass
    def close(self):self.closed=True


def reader(volume):
    return ExfatVolume(lambda lba:volume.blocks.get(lba-BASE,bytes(512)),CAPACITY,BASE)


def test_files(volume):
    root=Volume.openvolume(volume)
    assert root!='EINV'
    content={
        'SDTEST.BIN':bytes((i*73+(i>>3)+19)&255 for i in range(4096)),
        'README.TXT':b'SynthString SD card: exFAT, 128 KiB clusters.\r\n'
            b'SDTEST.BIN is a verified 4096-byte file read/write test.\r\n'
            b'FPGA sequencer persistence is not enabled yet.\r\n',
    }
    for name,data in content.items():
        handle=root.create(name);assert handle.IsValid,name
        handle.write(data);handle.close()
    root.flush()
    check=reader(volume)
    for name,data in content.items():assert check.read_file(name,8192)==data,name
    return content


def prepare():
    table=(OUT/'upcase.bin').read_bytes()
    assert len(table)==5836 and rolling(table,32)==0xe619d30d
    mkfat.gen_upcase_compressed=lambda:bytearray(table)
    volume=MemoryVolume()
    assert mkfat.exfat_mkfs(volume,volume.size,512,dict(wanted_cluster=131072))==0
    check=reader(volume)
    assert check.base==BASE and check.cluster_bytes==131072 and not check.files
    # Validate both boot copies, not just a successful fallback mount.
    check._boot(0,9);check._boot(12,9)
    full=dict(volume.blocks)
    # The bitmap is authoritative for allocation. Only allocated clusters have
    # meaningful FAT links; unused FAT entries are not followed or modified.
    # Keep the entire root directory initialized (all trailing entries are EOD),
    # but omit undefined padding past bitmap/up-case DataLength.
    required=set(range(24))
    required.update(range(check.fat_offset,check.fat_offset+(check.root_cluster+3)*4//512+1))
    for file in (check.bitmap,check.upcase):
        first=check.heap_offset+(file.first-2)*(check.cluster_bytes//512)
        required.update(range(first,first+(file.length+511)//512))
    root_first=check.heap_offset+(check.root_cluster-2)*(check.cluster_bytes//512)
    required.update(range(root_first,root_first+check.cluster_bytes//512))
    baseline={lba:full[lba] for lba in sorted(required)}
    files=test_files(volume)
    changes={k:v for k,v in volume.blocks.items() if full.get(k)!=v}
    # Exercise stale unused FAT contents explicitly: allocation/file creation
    # must use the bitmap, not assume the skipped entries contain zero.
    dirty=MemoryVolume(baseline)
    for lba in range(check.fat_offset+1,check.fat_offset+check.fat_length):dirty.blocks[lba]=b'\xa5'*512
    assert not reader(dirty).files
    occupied=Volume.openvolume(dirty)
    for index in range(126):
        handle=occupied.create(f'F{index:03}.BIN');handle.write(b'x');handle.close()
    occupied.flush()
    assert test_files(dirty)==files
    assert reader(dirty).files['SDTEST.BIN'].first>=128
    # Store exact, reviewed bytes rather than regenerating timestamps on-board.
    for name,blocks in [('format',baseline),('file-test',changes)]:
        with zipfile.ZipFile(OUT/(name+'.zip'),'w',zipfile.ZIP_DEFLATED) as archive:
            for lba,data in sorted(blocks.items()):archive.writestr(f'{BASE+lba}.bin',data)
    report={'mode':'offline-only','partition_start':BASE,'partition_sectors':SECTORS,
        'cluster_bytes':check.cluster_bytes,'cluster_count':check.cluster_count,
        'fat_offset':check.fat_offset,'fat_sectors':check.fat_length,
        'heap_offset':check.heap_offset,'root_cluster':check.root_cluster,
        'format_sectors':len(baseline),'file_test_sectors':len(changes),
        'files':{name:{'length':len(data),'sha256':hashlib.sha256(data).hexdigest()} for name,data in files.items()},
        'range_min':BASE+min(volume.blocks),'range_max':BASE+max(volume.blocks),
        'main_boot_verified':True,'backup_boot_verified':True,'independent_reader_verified':True,
        'format_mode':'quick; unallocated FAT entries and data padding retained',
        'stale_free_fat_allocation_test':True}
    (OUT/'plan.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))


if __name__=='__main__':prepare()
