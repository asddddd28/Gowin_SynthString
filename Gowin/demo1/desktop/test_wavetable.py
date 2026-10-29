import unittest
from wavetable import TableTransfer,table_crc,validate_samples,harmonic_piano_table
from protocol import StatusParser,packet
class TableTests(unittest.TestCase):
    def status(self,t,result=1,count=0,crc=None,generation=7):
        return dict(result=result,count=count,crc=table_crc(t.samples[:count]) if crc is None else crc,
                    token=t.token,generation=generation,available=True)
    def test_complete_transaction(self):
        samples=harmonic_piano_table(); t=TableTransfer(samples,0,token=0x1234)
        self.assertEqual(t.advance(0),[packet(0x16)])
        frames=t.advance(.01,self.status(t,result=0))
        self.assertEqual(frames[0],packet(0x10,value=0x1234))
        total=[]
        for count in range(0,1025,32):
            frames=t.advance(.02+count/1000,self.status(t,count=count))
            total.extend(f for f in frames if f[1]==0x11)
        self.assertEqual(len(total),1024)
        self.assertEqual([f[2]+256*f[3] for f in total],list(range(1024)))
        self.assertEqual([int.from_bytes(f[5:7],'little',signed=True) for f in total],samples)
        self.assertEqual(t.state,'commit');self.assertFalse(t.done)
        t.advance(1.2,self.status(t,result=3,count=1024,generation=7));self.assertFalse(t.done)
        t.advance(1.3,self.status(t,result=3,count=1024,generation=8));self.assertTrue(t.done)
    def test_errors_and_stale_ack(self):
        t=TableTransfer([0]*1024,0,token=1);t.advance(.1,self.status(t,result=0))
        stale=self.status(t);stale['token']=2
        self.assertEqual(t.advance(.2,stale),[]);self.assertEqual(t.state,'begin')
        self.assertEqual(t.advance(.3,self.status(t,crc=123)),[packet(0x13)])
        self.assertIsNotNone(t.error)
        t=TableTransfer([0]*1024,0);self.assertEqual(t.advance(4),[]);self.assertIsNotNone(t.error)
    def test_input_and_crc(self):
        self.assertEqual(table_crc([0]*1024),0xc584)
        for samples in ([0]*1023,[32768]*1024,[True]*1024):
            with self.assertRaises(ValueError):validate_samples(samples)
    def test_ack_parser(self):
        raw=bytes([0xa5,0x86,3,1,0,4,0x34,0x12,0x78,0x56,2,0,0,0,0]);check=0
        for b in raw:check^=b
        parser=StatusParser();self.assertEqual(parser.feed(raw[:5]),[])
        decoded=parser.feed(raw[5:]+bytes([check]))[0]
        self.assertEqual((decoded['count'],decoded['crc'],decoded['token'],decoded['generation']),(1024,0x1234,0x5678,2))
if __name__=='__main__':unittest.main()
