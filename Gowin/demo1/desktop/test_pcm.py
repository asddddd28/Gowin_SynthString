import copy,time,unittest
from functools import reduce
from operator import xor
from pcm import validate_image,metadata,crc_words,PcmTransfer
from protocol import packet,StatusParser
from transport import SerialLink
from test_transport import FakeSerial

def fixture(n=1024):return dict(format='tang-pcm-v1',sample_rate=24000,root_note=60,loop_start=128,loop_end=n,samples=[i%60000-30000 for i in range(n)])

class PcmSerial(FakeSerial):
    def __init__(self,**kw):
        super().__init__(**kw);self.meta=[];self.samples=[];self.result=0;self.token=0;self.generation=0;self.available=False
    def write(self,f):
        super().write(f);op=f[1];value=int.from_bytes(f[5:7],'little')
        if op==0x30:self.meta=[];self.samples=[];self.token=value;self.result=1;self.available=False
        elif op==0x34:
            if f[2]!=len(self.meta):self.result=4
            else:self.meta.append(value)
        elif op==0x31:
            if f[2]+256*f[3]!=len(self.samples) or len(self.meta)!=4:self.result=4
            else:self.samples.append(value)
        elif op==0x32:
            if len(self.samples)==self.meta[0] and value==crc_words(self.meta+self.samples) and f[2]+256*f[3]==self.token:
                self.result=3;self.available=True;self.generation+=1
            else:self.result=4
        elif op==0x33:self.result=0
        elif op==0x36:
            b=bytes([0xa5,0x88,self.result,int(self.available)])+len(self.samples).to_bytes(2,'little')+crc_words(self.meta+self.samples).to_bytes(2,'little')
            b+=self.token.to_bytes(2,'little')+self.generation.to_bytes(2,'little')+bytes([len(self.meta),0,0])
            self.input.extend(b+bytes([reduce(xor,b)]))
        return len(f)

class PcmTests(unittest.TestCase):
    def test_metadata_and_ranges(self):
        image=fixture();validate_image(image)
        self.assertEqual(metadata(image),[1024,128,1024,60])
        for key,value in [('sample_rate',48000),('root_note',128),('loop_start',800),('loop_end',2048),('samples',[0]*20000)]:
            with self.assertRaises(ValueError):validate_image(dict(image,**{key:value}))
        image['samples'][0]=32768
        with self.assertRaises(ValueError):validate_image(image)

    def test_timeout_and_stale_ack(self):
        t=PcmTransfer(fixture(),0)
        self.assertEqual(t.advance(0)[0][1],0x36)
        t.advance(.1,dict(generation=0));self.assertEqual(t.state,'begin')
        t.advance(.2,dict(token=t.token%65535+1));self.assertEqual(t.state,'begin')
        self.assertEqual(t.advance(6)[0][1],0x33);self.assertFalse(t.done)
        self.assertIn('旧采样失效',t.error)

    def test_full_size_thread_and_single_transfer(self):
        f=PcmSerial();link=SerialLink('FAKE',factory=lambda **kw:f);image=fixture(16384)
        link.start()
        try:
            self.assertTrue(link.upload_pcm(image));self.assertFalse(link.upload([0]*1024));self.assertFalse(link.upload_pcm(image))
            deadline=time.monotonic()+25;seen=[]
            while time.monotonic()<deadline:
                kind,data=link.events.get(timeout=6);seen.append(kind)
                self.assertNotIn(kind,('pcm_error','error'))
                if kind=='pcm_done':break
            self.assertIn('pcm_done',seen);self.assertIn('status',seen)
            self.assertEqual(f.samples,[v&65535 for v in image['samples']]);self.assertEqual(f.meta,metadata(image))
        finally:link.close()

    def test_status_parser(self):
        f=PcmSerial();f.write(packet(0x36));p=StatusParser();data=bytes(f.input)
        self.assertEqual(p.feed(data[:6]),[])
        status=p.feed(data[6:])[0];self.assertTrue(status['pcm']);self.assertFalse(status['available'])
        self.assertEqual(status['metadata'],0)

if __name__=='__main__':unittest.main()
