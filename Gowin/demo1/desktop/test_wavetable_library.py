"""独立拼装库目录与帧坐标，覆盖损坏、边界、版本和完整帧保留。"""
import binascii
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from prepare_wavetable_library import prepare_library
from wavetable_bank import encode_bank, decode_bank, select_pair
from wavetable_library import make_resource, encode_index, decode_index, load_library


class LibraryTests(unittest.TestCase):
    def resource(self, rid=1):
        return make_resource(rid, 7, '渐变', encode_bank([[-32768]*1024, [0]*1024, [32767]*1024]))

    def test_directory_bytes_independently(self):
        r = self.resource()
        crcs = [binascii.crc32(struct.pack('<1024h', *frame)) & 0xffffffff for frame in
                ([-32768]*1024,[0]*1024,[32767]*1024)]
        payload_crc = binascii.crc32(r.data[32:]) & 0xffffffff
        entry = struct.pack('<6I11sB7I',1,7,3,payload_crc,6176,96,b'00000001BIN',0,*([0]*7))
        entry = entry[:36]+struct.pack('<I',binascii.crc32(entry[:36]+entry[40:]) & 0xffffffff)+entry[40:]
        body = entry+struct.pack('<3I',*crcs)
        head = struct.pack('<4sHH6I',b'TSLB',1,32,64,1,76,binascii.crc32(body) & 0xffffffff,0,0)
        expected = head[:28]+struct.pack('<I',binascii.crc32(head[:28]) & 0xffffffff)+body
        self.assertEqual(encode_index([r]),expected)
        desc = decode_index(expected)[0]
        self.assertEqual(desc['frame_crcs'],tuple(crcs));self.assertEqual(desc['filename'],'00000001.BIN')

    def test_position_quantization_endpoints_and_last(self):
        self.assertEqual(select_pair(3,25),(0,1,32768))
        self.assertEqual(select_pair(3,50),(1,2,0))
        self.assertEqual(select_pair(3,100),(2,2,0))
        self.assertEqual(select_pair(1,99.9),(0,0,0))
        self.assertEqual(select_pair(512,100),(511,511,0))
        for value in (True,float('nan'),float('inf'),-1,100.01):
            with self.assertRaises(ValueError):select_pair(3,value)
        r = self.resource();frames,job=r.pair(25)
        self.assertEqual(frames,[[-32768]*1024,[0]*1024])
        self.assertEqual(job['fraction'],32768)
        self.assertEqual(r.job(100,0x1000)['second_address'],0x2000)
        self.assertEqual(r.job(25,2**32-6144)['second_address'],2**32-4096)
        for base in (True,1,-2,2**32-4096):
            with self.assertRaises(ValueError):r.job(25,base)

    def test_crc_layers_and_descriptor_corruption(self):
        good=encode_index([self.resource()])
        for byte in (4,12,28,32,68,len(good)-1):
            bad=bytearray(good);bad[byte]^=1
            with self.assertRaises(ValueError):decode_index(bad)
        for bad in (good[:-1],good+b'\0'):
            with self.assertRaises(ValueError):decode_index(bad)
        # 外层CRC重新签算，内层描述符CRC仍必须独立拒绝。
        bad=bytearray(good);bad[32+4]^=1
        struct.pack_into('<I',bad,20,binascii.crc32(bad[32:]) & 0xffffffff)
        struct.pack_into('<I',bad,28,binascii.crc32(bad[:28]) & 0xffffffff)
        with self.assertRaises(ValueError):decode_index(bad)

    def test_directory_structure_after_valid_crc(self):
        def resign(raw):
            struct.pack_into('<I',raw,68,binascii.crc32(raw[32:68]+raw[72:96]) & 0xffffffff)
            struct.pack_into('<I',raw,20,binascii.crc32(raw[32:]) & 0xffffffff)
            struct.pack_into('<I',raw,28,binascii.crc32(raw[:28]) & 0xffffffff)
            return raw
        good=encode_index([self.resource()])
        for offset in (32+20,32+24,32+35,32+40):
            bad=bytearray(good);bad[offset]^=1
            with self.assertRaises(ValueError):decode_index(resign(bad))
        with self.assertRaises(ValueError):encode_index([self.resource(),self.resource()])
        for rid in (0,True,2**32):
            with self.assertRaises(ValueError):self.resource(rid)

    def test_library_atomic_build_readback_and_preserve_existing(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'source.tswt';source.write_bytes(self.resource().data)
            items=[dict(resource_id=1,revision=7,title='渐变',source=str(source))]
            out=root/'library';report=prepare_library(items,out)
            resources=load_library(out/'TSLIB.JSN')
            self.assertEqual(resources[0].frame_count,3)
            self.assertEqual(decode_bank(resources[0].data),[[-32768]*1024,[0]*1024,[32767]*1024])
            self.assertEqual(prepare_library(items,out)['files'],report['files'])
            (out/'00000001.BIN').write_bytes(b'existing')
            with self.assertRaises(ValueError):prepare_library(items,out)
            self.assertEqual((out/'00000001.BIN').read_bytes(),b'existing')
            with self.assertRaises(ValueError):prepare_library([dict(items[0],resource_id=0)],root/'bad')
            self.assertFalse((root/'bad').exists())

    def test_library_metadata_content_and_frame_crc_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'source.tswt';source.write_bytes(self.resource().data)
            out=root/'library';prepare_library([dict(resource_id=1,title='渐变',source=str(source))],out)
            manifest=out/'TSLIB.JSN';original=manifest.read_bytes()
            data=json.loads(original);data['resources'][0]['filename']='../escape.BIN'
            manifest.write_text(json.dumps(data))
            with self.assertRaises(ValueError):load_library(out)
            manifest.write_bytes(original)
            resource_file=out/'00000001.BIN';raw=bytearray(resource_file.read_bytes());raw[-1]^=1;resource_file.write_bytes(raw)
            with self.assertRaises(ValueError):load_library(out)
            resource_file.write_bytes(source.read_bytes())
            index=out/'TSINDEX.BIN';bad=bytearray(index.read_bytes());bad[-1]^=1
            struct.pack_into('<I',bad,20,binascii.crc32(bad[32:]) & 0xffffffff)
            struct.pack_into('<I',bad,28,binascii.crc32(bad[:28]) & 0xffffffff);index.write_bytes(bad)
            with self.assertRaises(ValueError):load_library(out)


if __name__=='__main__':unittest.main()
