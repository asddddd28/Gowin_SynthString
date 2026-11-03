"""覆盖实际事件格式、满容量、损坏以及每一个 SD 扇区写入的掉电位置。"""
from dataclasses import replace
import struct
import unittest
from archive_model import (Snapshot, SECTOR, FILE_BYTES, BAR, pack, unpack, choose, commit)


def fixture():
    patch = bytearray(512)
    struct.pack_into('<I', patch, 0, 1)
    patch[456:459] = '鼓'.encode()
    events = (20 | 60 << 69 | 100 << 62 | 1 << 78, 180)
    return Snapshot(120, BAR, events, (bytes(patch), bytes(512), bytes(512), bytes(512)), (0,)*2048)


class ArchiveTests(unittest.TestCase):
    def test_roundtrip_and_full_capacity(self):
        source = fixture()
        self.assertEqual(unpack(pack(source, 7)), (7, source))
        events = tuple((i % BAR) | i << 20 | 1 << 78 for i in range(1024))
        full = replace(source, events=events, wave=tuple((-1 if i & 1 else 1)*(1 << 26) for i in range(2048)))
        self.assertEqual(unpack(pack(full, 8)), (8, full))

    def test_reject_invalid_semantics(self):
        original = fixture()
        for source in (replace(original, bpm=301), replace(original, loop_ticks=BAR+1),
                       replace(original, events=(1,)), replace(original, events=(1 << 95,)),
                       replace(original, patches=(bytes(512),)*4), replace(original, wave=(0,)*2047)):
            with self.assertRaises(ValueError):
                pack(source, 1)

    def test_corrupt_every_sector(self):
        original = pack(fixture(), 1)
        for offset in range(0, FILE_BYTES, SECTOR):
            changed = bytearray(original)
            changed[offset] ^= 0x80
            self.assertIsNone(choose([bytes(changed), bytes(FILE_BYTES)]))

    def test_generation_collision_and_exhaustion(self):
        first = pack(fixture(), 3)
        changed = pack(replace(fixture(), bpm=90), 3)
        with self.assertRaises(ValueError):
            choose([first, changed])
        self.assertEqual(choose([first, first])[:2], (1, 3))
        with self.assertRaises(ValueError):
            pack(fixture(), 1 << 64)

    def test_all_write_cut_points_and_torn_sectors(self):
        previous = fixture()
        following = replace(previous, bpm=91)
        # Existing A is newer; B may contain an older valid generation.
        initial = [pack(previous, 8), pack(replace(previous, bpm=80), 7)]
        for cut in range(67):
            for tear in (0, 1, 255, 511):
                files = [bytearray(x) for x in initial]
                writes = 0

                def read(bank, sector):
                    self.assertIn(bank, (0, 1))
                    self.assertTrue(0 <= sector < 65)
                    return bytes(files[bank][sector*SECTOR:(sector+1)*SECTOR])

                def write(bank, sector, data):
                    nonlocal writes
                    self.assertEqual(bank, 1, 'Never overwrite the current valid file')
                    if writes == cut:
                        start = sector*SECTOR
                        files[bank][start:start+tear] = data[:tear]
                        raise OSError('simulated power interruption')
                    files[bank][sector*SECTOR:(sector+1)*SECTOR] = data
                    writes += 1

                try:
                    commit(read, write, following)
                except OSError:
                    pass
                recovered = choose([bytes(x) for x in files])
                self.assertIsNotNone(recovered)
                self.assertIn(recovered[2], (previous, following))
                self.assertEqual(bytes(files[0]), initial[0])
                if cut >= 66:
                    self.assertEqual(recovered[:2], (1, 9))

    def test_readback_failure_stops_before_commit(self):
        files = [bytearray(pack(fixture(), 5)), bytearray(FILE_BYTES)]
        writes = []
        def read(bank, sector):
            return bytes(files[bank][sector*512:(sector+1)*512])
        def write(bank, sector, data):
            writes.append((bank, sector))
            # Faulty device acknowledges without storing data.
        with self.assertRaises(IOError):
            commit(read, write, replace(fixture(), bpm=90))
        self.assertEqual(writes, [(1, 0), (1, 1), (1, 2)])
        self.assertEqual(choose([bytes(x) for x in files])[:2], (0, 5))


if __name__ == '__main__':
    unittest.main(verbosity=2)
