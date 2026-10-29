"""原生 WT、实际 Surge WAV 导出布局及环形重采样边界。"""
import math
from pathlib import Path
import struct
import tempfile
import unittest

from wavetable import load_surge_frames, load_table, resample_frame


class SurgeWavetableTests(unittest.TestCase):
    def load(self, raw, extension='.wt', frame=0):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ('test' + extension)
            path.write_bytes(raw)
            return load_table(path, frame)

    def test_float_wt_multiple_frames_and_periodic_interpolation(self):
        cycle = [0., 1., 0., -1.] * 4
        raw = struct.pack('<4sIHH', b'vawt', 16, 2, 0) + struct.pack('<32f', *([0.]*16 + cycle))
        self.assertEqual(self.load(raw), [0]*1024)
        samples = self.load(raw, frame=1)
        self.assertEqual([samples[i] for i in (0,16,64,192,1023)], [0,8192,32767,-32768,-512])
        with self.assertRaises(ValueError):
            self.load(raw, frame=2)

    def test_both_integer_scalings(self):
        for flags, value, expected in ((4,8192,16384), (12,8192,8192)):
            raw = struct.pack('<4sIHH', b'vawt', 16, 1, flags) + struct.pack('<16h', *([value]*16))
            self.assertEqual(self.load(raw), [expected]*1024)

    def test_actual_surge_wav_export_with_riff_length_quirk(self):
        # 独立复现固定源码 WAVFileSupport.cpp 的导出字节布局。
        fmt = struct.pack('<HHIIHH', 3,1,44100,44100*32,32,32)
        data = struct.pack('<32f', *([.25]*16+[-.5]*16))
        chunks = b'fmt '+struct.pack('<I',16)+fmt+b'srge'+struct.pack('<III',8,1,16)+b'data'+struct.pack('<I',len(data))+data
        raw = b'RIFF'+struct.pack('<I',len(chunks)+6)+b'WAVE'+chunks
        self.assertEqual(self.load(raw,'.wav',1), [-16384]*1024)
        for invalid in (raw[:-4], raw.replace(b'srge', b'srgo'), raw.replace(b'srge', b'JUNK')):
            with self.assertRaises(ValueError):
                self.load(invalid, '.wav')

    def test_reject_unknown_flags_sample_mode_truncation_and_nan(self):
        payload = struct.pack('<16f', *([0.]*16))
        for flags in (1,2,8,16):
            with self.assertRaises(ValueError):
                self.load(struct.pack('<4sIHH',b'vawt',16,1,flags)+payload)
        for payload in (payload[:-1], payload+b'\0', struct.pack('<16f',math.nan,*([0.]*15)), struct.pack('<16f',1.1,*([0.]*15))):
            with self.assertRaises(ValueError):
                self.load(struct.pack('<4sIHH',b'vawt',16,1,0)+payload)


if __name__ == '__main__':
    unittest.main()
