"""Patch validation/migration, wire ACK identity and real serial-thread transactions."""
import copy
import time
import unittest
from functools import reduce
from operator import xor
from profiles import preset,PRESETS,words,crc_words,ProfileTransfer,validate_profile
from protocol import defaults,validate_config,StatusParser
from transport import SerialLink
from test_transport import FakeSerial

class ProfileSerial(FakeSerial):
    def __init__(self,**kwargs):
        super().__init__(**kwargs)
        self.data=[];self.key=0;self.token=0;self.result=0;self.generation=0;self.committed={}
    def write(self,frame):
        super().write(frame)
        op=frame[1];value=int.from_bytes(frame[5:7],'little')
        if op==0x20:self.data=[];self.key=frame[2];self.token=value;self.result=1
        elif op==0x21:
            if frame[2]!=self.key or frame[3]!=len(self.data):self.result=4
            else:self.data.append(value)
        elif op==0x22:
            if len(self.data)==18 and frame[2]==self.key and frame[3]+256*frame[4]==self.token and value==crc_words(self.data):
                self.result=3;self.generation+=1;self.committed[self.key]=self.data[:]
            else:self.result=4
        elif op==0x23:self.result=0
        elif op==0x27:
            body=bytes([0xa5,0x87,self.result,self.key])+len(self.data).to_bytes(2,'little')+crc_words(self.data).to_bytes(2,'little')
            body+=self.token.to_bytes(2,'little')+self.generation.to_bytes(2,'little')+bytes([2,0,0])
            self.input.extend(body+bytes([reduce(xor,body)]))
        return len(frame)

class ProfileTests(unittest.TestCase):
    def test_v1_migration_independent_patches(self):
        cfg=defaults();cfg['version']=1
        for k in cfg['keys']:del k['synth']
        validate_config(cfg)
        self.assertEqual(cfg['version'],2)
        cfg['keys'][0]['synth']['ratio']=3
        self.assertEqual(cfg['keys'][1]['synth']['ratio'],1)
        validate_config(cfg)

    def test_presets_ranges_and_release(self):
        for name in PRESETS:
            p=preset(name);data=words(p)
            self.assertEqual(len(data),18)
            self.assertTrue(all(0<=w<=65535 for w in data))
            if p['sustain']==0:self.assertGreater(data[8],0)
        for field,value in [('ratio',0),('ratio',9),('depth',3),('sensitivity',128),('attack',float('nan')),('gain_a',True)]:
            p=preset('正弦');p[field]=value
            with self.assertRaises(ValueError):validate_profile(p)
        p=preset('AM 颤音');p['depth']=1.1
        with self.assertRaises(ValueError):words(p)

    def test_ack_identity_crc_generation_and_timeout(self):
        p=preset('FM 钟声');t=ProfileTransfer([(32,p)],0)
        self.assertEqual(t.advance(0)[0][1],0x27)
        ack=dict(profile=True,key=0,token=0,result=0,count=0,crc=0,generation=65535,profile_version=2)
        self.assertEqual(t.advance(.1,ack)[0][1],0x20)
        ack.update(key=32,token=t.token,result=1,count=0)
        frames=t.advance(.2,ack)
        self.assertEqual(len(frames),20)
        self.assertEqual([f[3] for f in frames[:18]],list(range(18)))
        ack.update(result=3,count=18,crc=crc_words(words(p)),generation=0)
        stale=dict(ack,token=t.token%65535+1);t.advance(.3,stale);self.assertFalse(t.done)
        t.advance(.3,dict(ack,crc=ack['crc']^1));self.assertFalse(t.done)
        t.advance(.4,ack);self.assertTrue(t.done)
        t=ProfileTransfer([(32,p)],0);self.assertEqual(t.advance(4)[0][1],0x23);self.assertIsNotNone(t.error)

    def test_old_firmware_is_rejected_before_upload(self):
        transfer=ProfileTransfer([(32,preset('正弦'))],0)
        frames=transfer.advance(.1,dict(profile=True,profile_version=1))
        self.assertEqual([frame[1] for frame in frames],[0x23])
        self.assertIn('precision',transfer.error)

    def test_parser_fragments_and_corruption(self):
        f=ProfileSerial();from protocol import packet
        f.write(packet(0x27));data=bytes(f.input);parser=StatusParser()
        self.assertEqual(parser.feed(data[:5]),[])
        self.assertTrue(parser.feed(data[5:])[0]['profile'])
        bad=bytearray(data);bad[4]^=1
        self.assertEqual(len(parser.feed(b'noise'+bad+data)),1)

    def test_full32_thread_upload_and_mutual_exclusion(self):
        f=ProfileSerial();link=SerialLink('FAKE',factory=lambda **kwargs:f)
        patches=[(32+i,preset(PRESETS[i%len(PRESETS)])) for i in range(32)]
        link.start()
        try:
            self.assertTrue(link.upload_profiles(patches));self.assertFalse(link.upload([0]*1024))
            self.assertFalse(link.upload_profiles(patches))
            seen=[];deadline=time.monotonic()+10
            while time.monotonic()<deadline:
                kind,data=link.events.get(timeout=4);seen.append(kind)
                self.assertNotIn(kind,('profiles_error','error'))
                if kind=='profiles_done':break
            self.assertIn('profiles_done',seen)
            self.assertIn('status',seen)
            self.assertEqual(f.committed,{key:words(p) for key,p in patches})
        finally:link.close()

if __name__=='__main__':unittest.main()
