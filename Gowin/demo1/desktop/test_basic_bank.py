"""真实AKWF资源与独立WAV向量，验证转换、绑定、试听和重建边界。"""
import copy
import hashlib
import io
import json
import math
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
import wave

from basic_bank import load_basic_bank
from basic_preview import render_preview
from profiles import preset
from single_cycle import convert_cycle
from wavetable import load_surge_frames
from wavetable_library import load_library

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from prepare_basic_bank import build_bank


def pcm_wav(values, channels=1, width=2):
    buffer=io.BytesIO()
    with wave.open(buffer,'wb') as wav:
        wav.setnchannels(channels);wav.setsampwidth(width);wav.setframerate(44100)
        wav.writeframes(struct.pack('<'+str(len(values))+'h',*values))
    return buffer.getvalue()


class BasicBankTests(unittest.TestCase):
    def test_cycle_dc_gain_periodic_interpolation(self):
        # A four-level cycle with DC offset, independently known extrema.
        frame,metrics=convert_cycle(pcm_wav([1000,11000,1000,-9000]*4))
        self.assertEqual(len(frame),1024)
        self.assertEqual(metrics['removed_dc'],1000)
        self.assertFalse(metrics['mip_bandlimited'])
        self.assertLessEqual(abs(frame[64]-round(.9*32767)),1)
        self.assertLessEqual(abs(frame[192]+round(.9*32767)),1)
        self.assertEqual(frame[0],0)
        self.assertLessEqual(abs(frame[-1]-round(-.9*32767/64)),1)
        self.assertLessEqual(abs(sum(frame)),8)

    def test_cycle_rejects_recording_formats_and_corruption(self):
        for raw in (b'not wav',pcm_wav([1]*32),pcm_wav([0,1000]*4),
                    pcm_wav([0,1000]*16,channels=2),pcm_wav([0,1000]*16,width=1),
                    pcm_wav([0,1000]*16)[:-4],b'x'*65537):
            with self.subTest(size=len(raw)):
                with self.assertRaises(ValueError):convert_cycle(raw)
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'single.wav';path.write_bytes(pcm_wav([0,1000]*16))
            with self.assertRaises(ValueError):load_surge_frames(path)

    def test_actual_bank_binding_deep_copy_and_audio(self):
        sounds=load_basic_bank(ROOT/'output/basic_bank_v1')
        self.assertEqual(len(sounds),16)
        self.assertEqual(sum(s.resource_id is not None for s in sounds),8)
        self.assertEqual([s.resource_id for s in sounds[8:]],list(range(257,265)))
        for sound in sounds:
            profile,frames=sound.upload()
            profile['attack']=999
            self.assertNotEqual(sound.profile['attack'],999)
            if frames is not None:
                self.assertEqual(frames[0],frames[1]);self.assertEqual(len(frames[0]),1024)
                frames[0][0]=123456
                self.assertNotEqual(sound.samples[0],123456)
                self.assertEqual(frames[1][0],sound.samples[0])
            with wave.open(str(sound.preview),'rb') as wav:
                self.assertEqual((wav.getnchannels(),wav.getsampwidth(),wav.getframerate()),(1,2,24000))
                payload=wav.readframes(wav.getnframes());values=struct.unpack('<'+str(len(payload)//2)+'h',payload)
                self.assertGreater(max(abs(v) for v in values),100)
                self.assertLess(max(abs(v) for v in values),32767)
                self.assertEqual(values[-2400:],(0,)*2400)

    def test_catalog_rejects_mismatch_traversal_and_corrupt_audio(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)/'bank';shutil.copytree(ROOT/'output/basic_bank_v1',folder)
            path=folder/'BASICS.JSN';original=json.loads(path.read_text(encoding='utf-8'))
            cases=[]
            candidate=copy.deepcopy(original);candidate['timbres'][8]['resource_id']=258;cases.append(candidate)
            candidate=copy.deepcopy(original);candidate['timbres'][0]['preview_file']='../P0000001.WAV';cases.append(candidate)
            candidate=copy.deepcopy(original);candidate['timbres'][0]['profile']['attack']=float('nan');cases.append(candidate)
            candidate=copy.deepcopy(original);candidate['timbres'][0]['requirements']=[];cases.append(candidate)
            candidate=copy.deepcopy(original);candidate['timbres'][1]['timbre_id']=1;cases.append(candidate)
            for candidate in cases:
                path.write_text(json.dumps(candidate),encoding='utf-8')
                with self.assertRaises(ValueError):load_basic_bank(folder)
            path.write_text(json.dumps(original),encoding='utf-8')
            preview=folder/original['timbres'][0]['preview_file'];preview.write_bytes(b'invalid'*20)
            with self.assertRaises(ValueError):load_basic_bank(folder)
            # Even a recomputed digest does not permit malformed WAV content.
            original['timbres'][0]['preview_sha256']=hashlib.sha256(preview.read_bytes()).hexdigest()
            path.write_text(json.dumps(original),encoding='utf-8')
            with self.assertRaises(ValueError):load_basic_bank(folder)

    def test_resource_crc_damage_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)/'bank';shutil.copytree(ROOT/'output/basic_bank_v1',folder)
            path=folder/'00000101.BIN';data=bytearray(path.read_bytes());data[-1]^=1;path.write_bytes(data)
            with self.assertRaises(ValueError):load_basic_bank(folder)

    def test_sine_preview_pitch_and_determinism(self):
        profile=dict(preset('正弦'),attack=0,decay=0,sustain=100,release=100)
        raw=render_preview(profile,notes=(69,))
        self.assertEqual(raw,render_preview(profile,notes=(69,)))
        with wave.open(io.BytesIO(raw),'rb') as wav:
            payload=wav.readframes(wav.getnframes());samples=struct.unpack('<'+str(len(payload)//2)+'h',payload)
            section=samples[2400:12000]
            crossings=sum(a<=0<b for a,b in zip(section,section[1:]))
            self.assertLess(abs(crossings/.4-440),3)
        with self.assertRaises(ValueError):render_preview(dict(profile,wave_a='自定义波表'))
        with self.assertRaises(ValueError):render_preview(profile,notes=(True,))

    def test_rebuild_is_identical_and_refuses_different_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)/'bank';result=build_bank(folder)
            original=ROOT/'output/basic_bank_v1'
            self.assertEqual(set(p.name for p in folder.iterdir()),set(p.name for p in original.iterdir()))
            for file in folder.iterdir():self.assertEqual(file.read_bytes(),(original/file.name).read_bytes(),file.name)
            self.assertEqual(len(load_library(folder)),8)
            self.assertEqual(result['timbres'],16)
            self.assertEqual(build_bank(folder)['files'],result['files'])
            marker=folder/'KEEP.TXT';marker.write_text('preserve me',encoding='utf-8')
            with self.assertRaises(ValueError):build_bank(folder)
            self.assertEqual(marker.read_text(encoding='utf-8'),'preserve me')


if __name__=='__main__':unittest.main()
