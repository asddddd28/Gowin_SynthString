"""双帧协议的独立字节检查、状态机边界和逐键回读确认。"""
import copy
from functools import reduce
from operator import xor
import unittest
from protocol import StatusParser
from wavetable import PairTransfer, PositionTransfer, table_crc
from profiles import ProfileTransfer, preset, words, crc_words, validate_profile


class PairTests(unittest.TestCase):
    def test_capability_checked_before_payload(self):
        transfer=PairTransfer([[0]*1024,[1]*1024],0,token=7)
        self.assertEqual(transfer.advance(0)[0][1],0x16)
        self.assertEqual(transfer.advance(.1,dict(pair_capable=False)),[])
        self.assertIn('不支持',transfer.error)

    def test_pair_packet_addresses_prefix_crc_and_commit(self):
        a=list(range(-512,512));b=[32767 if i%2 else -32768 for i in range(1024)]
        transfer=PairTransfer([a,b],0,token=99)
        ack=dict(pair_capable=True,generation=65535,token=0,result=0,count=0,crc=65535,available=False,two_frames=False)
        self.assertEqual(transfer.advance(.1,ack)[0][1],0x40)
        ack.update(token=99,result=1)
        sent=[];now=.2
        while transfer.state!='commit':
            frames=transfer.advance(now,ack)
            sent += [f for f in frames if f[1]==0x41]
            now+=.02
            ack.update(count=transfer.expected,crc=table_crc(transfer.samples[:transfer.expected]))
        self.assertEqual(len(sent),2048)
        self.assertEqual(sent[1023][2:4],bytes((255,3)))
        self.assertEqual(sent[1024][2:4],bytes((0,4)))
        self.assertEqual(sent[-1][2:4],bytes((255,7)))
        self.assertEqual(sent[1024][5:7],b'\x00\x80')
        self.assertTrue(all(reduce(xor,f)==0 for f in sent))
        self.assertEqual(frames[0][1],0x42)
        ack.update(result=3,available=True,two_frames=True,generation=0)
        transfer.advance(now,dict(ack,token=100));self.assertFalse(transfer.done)
        transfer.advance(now,dict(ack,two_frames=False));self.assertFalse(transfer.done)
        transfer.advance(now,ack);self.assertTrue(transfer.done)

    def test_bounds_corruption_and_timeout(self):
        for frames in ([[0]*1024],[[0]*512,[0]*1536],[[0]*1024,[True]*1024]):
            with self.assertRaises(ValueError):PairTransfer(frames,0)
        t=PairTransfer([[0]*1024,[1]*1024],0,token=7)
        t.advance(.1,dict(pair_capable=True,generation=0))
        frames=t.advance(.2,dict(token=7,result=1,count=0,crc=0))
        self.assertEqual(frames[0][1],0x43);self.assertIsNotNone(t.error)
        t=PairTransfer([[0]*1024,[1]*1024],0,token=7)
        t.advance(.1,dict(pair_capable=True,generation=0))
        self.assertEqual(t.advance(4)[0][1],0x43)

    def test_extended_status_fragments_and_crc(self):
        payload=bytes((3,3,0,8,0x34,0x12,7,0,9,0,0x9f,0xfe,0xff))
        body=bytes((0xa5,0x86))+payload
        raw=body+bytes((reduce(xor,body),))
        p=StatusParser();self.assertEqual(p.feed(raw[:7]),[])
        s=p.feed(raw[7:])[0]
        self.assertTrue(s['two_frames'] and s['pair_capable']);self.assertEqual(s['query_key'],63)
        self.assertEqual(s['frame_position'],65534)
        corrupt=bytearray(raw);corrupt[13]^=1
        self.assertEqual(StatusParser().feed(corrupt),[])

    def test_position_requires_matching_key_and_value(self):
        t=PositionTransfer([(32,123),(63,65535)],0)
        self.assertEqual(t.advance(0)[0][1],0x16)
        self.assertEqual([f[1] for f in t.advance(.1,dict(pair_capable=True))],[0x44,0x46])
        t.advance(.2,dict(query_key=63,frame_position=123));self.assertEqual(t.count,0)
        t.advance(.2,dict(query_key=32,frame_position=122));self.assertEqual(t.count,0)
        self.assertEqual(t.advance(.3,dict(query_key=32,frame_position=123))[0][2],63)
        t.advance(.4,dict(query_key=63,frame_position=65535));self.assertTrue(t.done)
        for positions,expected in ([[(32,0)],True],[[(32,1)],False]):
            t=PositionTransfer(positions,0);t.advance(.1,dict(pair_capable=False))
            self.assertEqual(t.done,expected);self.assertEqual(t.error is None,expected)

    def test_profile_waits_for_position_confirmation(self):
        p=preset('正弦');p['frame_position']=50
        t=ProfileTransfer([(32,p)],0)
        ack=dict(profile_version=2,generation=0,key=32,token=0,result=0,count=0,crc=0)
        t.advance(.1,ack);ack.update(token=t.token,result=1)
        t.advance(.2,ack);ack.update(result=3,count=18,crc=crc_words(words(p)),generation=1)
        self.assertEqual(t.advance(.3,ack)[0][1],0x16);self.assertFalse(t.done)
        t.advance(.4,dict(pair_capable=True));t.advance(.5,dict(query_key=32,frame_position=32768))
        self.assertTrue(t.done)
        for value in (True,-1,101,float('nan')):
            p=copy.deepcopy(p);p['frame_position']=value
            with self.assertRaises(ValueError):validate_profile(p)


if __name__=='__main__':unittest.main()
