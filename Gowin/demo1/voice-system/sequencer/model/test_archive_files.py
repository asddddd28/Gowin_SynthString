"""真实 exFAT 目录/位图解析与音序 A/B 提交组合测试；使用稀疏内存卡。"""
from pathlib import Path
import sys
import unittest
from dataclasses import replace
sys.path.insert(0, str(Path(__file__).resolve().parents[3]/'scripts'))
from test_exfat_reference import SparseCard, file_entry
from archive_files import ArchiveFiles
from archive_model import FILE_BYTES, commit, choose
from test_archive_model import fixture


class ArchiveFileTests(unittest.TestCase):
    def card(self):
        card = SparseCard()
        card.add('LOOPA.SEQ', bytes(FILE_BYTES), first=40000)
        card.add('LOOPB.SEQ', bytes(FILE_BYTES), first=40001)
        card.add('KEEP.TXT', b'keep user data', first=40002)
        return card

    def test_two_saves_only_touch_preallocated_file_data(self):
        card = self.card()
        before = {lba:bytes(data) for lba,data in card.blocks.items()}
        writes = []
        def write(lba, data):
            writes.append(lba)
            card.write(lba*512, data)
        files = ArchiveFiles(card.volume(), write)
        self.assertEqual(commit(files.read, files.write, fixture()), (0, 1))
        changed = replace(fixture(), bpm=87)
        self.assertEqual(commit(files.read, files.write, changed), (1, 2))
        latest = choose([b''.join(files.read(bank,sector) for sector in range(65)) for bank in range(2)])
        self.assertEqual(latest, (1, 2, changed))
        allowed = {start+sector for start in files.starts for sector in range(65)}
        self.assertTrue(set(writes) <= allowed)
        for lba,data in before.items():
            if lba not in allowed:
                self.assertEqual(card.read(lba), data)
        self.assertEqual(card.volume().read_file('KEEP.TXT', 100), b'keep user data')
        self.assertGreater(files.starts[0]*512, 0xffffffff, '64GB card addresses must not truncate to byte u32')

    def test_boundaries_and_cross_allocated_files_rejected(self):
        card = self.card()
        files = ArchiveFiles(card.volume(), lambda *args:self.fail('Unexpected write'))
        for bank,sector in ((-1,0),(2,0),(0,-1),(0,65),(True,0)):
            with self.assertRaises(ValueError):
                files.write(bank, sector, bytes(512))
        card.add('OTHER.BIN', b'alias', first=40000)
        with self.assertRaises(ValueError):
            ArchiveFiles(card.volume(), lambda *args:self.fail('Unexpected write'))

    def test_missing_or_uninitialized_target_rejected(self):
        card = SparseCard()
        card.add('LOOPA.SEQ', bytes(FILE_BYTES), first=40000)
        with self.assertRaises(ValueError):
            ArchiveFiles(card.volume(), lambda *args:None)
        card.add('LOOPB.SEQ', bytes(FILE_BYTES), first=40001, valid=512)
        with self.assertRaises(ValueError):
            ArchiveFiles(card.volume(), lambda *args:None)


if __name__ == '__main__':
    unittest.main(verbosity=2)
