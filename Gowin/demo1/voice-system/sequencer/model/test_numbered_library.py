"""64GiB稀疏卡：子目录编号、断写保留旧录音、删除跳号、预设独立波表。"""
from dataclasses import replace
from pathlib import Path
import struct
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/'scripts'))
from test_exfat_reference import SparseCard,file_entry,checksum
from numbered_library import NumberedLibrary,FILE_BYTES,PRESET_BYTES,SEQUENCE_DIR,unpack_preset
from test_archive_model import fixture


def folder_entry(name,cluster,length):
    entry = file_entry(name,cluster,length)
    struct.pack_into('<H',entry,4,0x10)
    struct.pack_into('<H',entry,2,checksum(entry,16,(2,3)))
    return entry


def prepared_card():
    card = SparseCard()
    for name,cluster,extension,size in [('SEQUENCES',40000,'SSQ',FILE_BYTES),('PRESETS',40001,'SSP',PRESET_BYTES)]:
        entries = bytearray()
        for number in range(1,5):
            first = 40010+number+(10 if extension == 'SSP' else 0)
            card.used.add(first)
            card.write(card.cluster(first),bytes(size))
            entries.extend(file_entry(f'{number:08}.{extension}',first,size))
        card.used.add(cluster)
        card.write(card.cluster(cluster),entries+bytes(32))
        card.entries.extend(folder_entry(name,cluster,card.cluster_bytes))
    card.finish()
    card.add('KEEP.TXT',b'user data',first=40050)
    return card


class LibraryTests(unittest.TestCase):
    def library(self,card):
        return NumberedLibrary(card.volume(),lambda lba,data:card.write(lba*512,data))

    def test_numbered_save_latest_browse_delete_and_metadata_unchanged(self):
        card = prepared_card()
        before = {lba:bytes(data) for lba,data in card.blocks.items()}
        lib = self.library(card)
        self.assertIsNone(lib.select())
        first = fixture(); second = replace(first,bpm=87)
        self.assertEqual(lib.save(first),1)
        self.assertEqual(lib.save(second),2)
        self.assertEqual(lib.select(),2)
        self.assertEqual(lib.select(2,-1),1)
        self.assertEqual(lib.select(1,-1),1)
        self.assertEqual(lib.load(1),first)
        self.assertEqual(lib.load(2),second)
        lib.delete(1)
        self.assertEqual(lib.select(2,-1),2)
        self.assertEqual(lib.save(first),3)
        allowed = {lba for (folder,_),addresses in lib.targets.items() if folder == SEQUENCE_DIR for lba in addresses}
        for lba,data in before.items():
            if lba not in allowed:
                self.assertEqual(card.read(lba),data)
        self.assertEqual(card.volume().read_file('KEEP.TXT',32),b'user data')
        self.assertEqual(self.library(card).select(),3)

    def test_interrupted_new_file_never_overwrites_previous(self):
        card = prepared_card(); lib = self.library(card); lib.save(fixture())
        previous = lib._read(SEQUENCE_DIR,1)
        calls = [0]
        def fail(lba,data):
            calls[0] += 1
            if calls[0] == 10:
                card.write(lba*512,data[:71]); raise IOError('power interrupted')
            card.write(lba*512,data)
        lib.write_sector = fail
        with self.assertRaises(IOError):lib.save(replace(fixture(),bpm=90))
        lib = self.library(card)
        self.assertEqual(lib.select(),1)
        self.assertEqual(lib._read(SEQUENCE_DIR,1),previous)
        self.assertEqual(lib.save(fixture()),3, 'damaged file number must remain reserved')

    def test_preset_roundtrip_contains_its_own_wave_and_refuses_overwrite(self):
        card = prepared_card(); lib = self.library(card); snapshot = fixture()
        patch = next(p for p in snapshot.patches if p[:4] == b'\1\0\0\0')
        lib.upload_preset(1,'暖音电钢琴',patch,snapshot.wave)
        self.assertEqual(lib.presets(),[(1,'暖音电钢琴')])
        self.assertEqual(lib.load_preset(1),('暖音电钢琴',patch,snapshot.wave))
        with self.assertRaises(ValueError):lib.upload_preset(1,'new',patch,snapshot.wave)
        image = bytearray(lib._read('PRESETS',1));image[9000] ^= 1
        with self.assertRaises(ValueError):unpack_preset(bytes(image))

    def test_cross_allocation_in_other_directory_refuses_all_writes(self):
        card = prepared_card()
        card.write(card.cluster(40001),file_entry('ALIAS.BIN',40011,12)+bytes(32))
        with self.assertRaises(ValueError):self.library(card)

    def test_library_controls_cannot_save_an_empty_workspace(self):
        lib = self.library(prepared_card())
        with self.assertRaises(ValueError):lib.save(replace(fixture(),events=(),loop_ticks=0))
        with self.assertRaises(ValueError):lib._write(SEQUENCE_DIR,1,65,bytes(512))


if __name__ == '__main__':unittest.main(verbosity=2)
