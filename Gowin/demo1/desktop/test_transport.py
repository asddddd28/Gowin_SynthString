"""线程级串口替身：真实协议返回、断线、退出及队列保护。"""
import time
import unittest
from functools import reduce
from operator import xor
from protocol import packet
from wavetable import table_crc, harmonic_piano_table
from transport import SerialLink


class FakeSerial:
    def __init__(self, **kwargs):
        self.is_open = False
        self.input = bytearray()
        self.sent = []
        self.fail = False

    def open(self):
        self.is_open = True

    def close(self):
        self.is_open = False

    def reset_input_buffer(self):
        self.input.clear()

    @property
    def in_waiting(self):
        return len(self.input)

    def write(self, frame):
        if self.fail:
            raise OSError('模拟 USB 断开')
        self.sent.append(frame)
        if frame == packet(5):
            body = bytes([0xA5, 0x85, 0, 0, 0, 7, 1]) + bytes(8)
            self.input.extend(body + bytes([reduce(xor, body)]))
        return len(frame)

    def read(self, count):
        time.sleep(0.002)
        result = self.input[:min(count, 3)]
        del self.input[:len(result)]
        return result


class TableSerial(FakeSerial):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.samples=[];self.token=0;self.result=0;self.generation=0
    def write(self, frame):
        super().write(frame)
        op=frame[1];value=int.from_bytes(frame[5:7],'little')
        if op==0x10:
            self.samples=[];self.token=value;self.result=1
        elif op==0x11:
            address=frame[2]+256*frame[3]
            if self.result!=1 or address!=len(self.samples):self.result=4
            else:self.samples.append(int.from_bytes(frame[5:7],'little',signed=True))
        elif op==0x12:
            if len(self.samples)==1024 and value==table_crc(self.samples) and frame[2]+256*frame[3]==self.token:
                self.result=3;self.generation+=1
            else:self.result=4
        elif op==0x13:self.result=0
        elif op==0x16:
            body=bytes([0xa5,0x86,self.result,int(self.generation>0)])
            body+=len(self.samples).to_bytes(2,'little')+table_crc(self.samples).to_bytes(2,'little')
            body+=self.token.to_bytes(2,'little')+self.generation.to_bytes(2,'little')+bytes(3)
            self.input.extend(body+bytes([reduce(xor,body)]))
        return len(frame)


class TransportTests(unittest.TestCase):
    def test_thread_upload_and_heartbeat(self):
        fake=TableSerial();link=SerialLink('FAKE',factory=lambda **kwargs:fake)
        link.start();samples=harmonic_piano_table()
        try:
            self.assertTrue(link.upload(samples))
            self.assertFalse(link.upload(samples))
            deadline=time.monotonic()+5;seen=[]
            while time.monotonic()<deadline:
                kind,data=link.events.get(timeout=3);seen.append(kind)
                self.assertNotIn(kind,('upload_error','error'))
                if kind=='upload_done':break
            self.assertIn('upload_done',seen)
            self.assertIn('status',seen)
            self.assertEqual(fake.samples,samples)
        finally:link.close()

    def test_status_send_close(self):
        fake = FakeSerial()
        link = SerialLink('FAKE', factory=lambda **kwargs: fake)
        link.start()
        seen = []
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            kind, data = link.events.get(timeout=2)
            seen.append(kind)
            if kind == 'status':
                self.assertEqual(data['cycles'], 263)
                break
        self.assertIn('status', seen)
        link.send([packet(1, 32, 60, 96), packet(2, 32)])
        time.sleep(0.05)
        link.close()
        self.assertFalse(link.thread.is_alive())
        self.assertFalse(fake.is_open)
        self.assertIn(packet(2, 32), fake.sent)
        self.assertEqual(fake.sent[-1], packet(4))

    def test_queue_overflow_panic(self):
        link = SerialLink('FAKE')
        self.assertFalse(link.send([packet(1)]*257))
        self.assertEqual(list(link.pending), [packet(4)])
        self.assertEqual(link.events.get_nowait()[0], 'overflow')

    def test_device_error(self):
        fake = FakeSerial(); fake.fail = True
        link = SerialLink('FAKE', factory=lambda **kwargs: fake)
        link.start(); link.thread.join(2)
        self.assertFalse(link.thread.is_alive())
        self.assertTrue(link.stop.is_set())
        events = []
        while not link.events.empty():
            events.append(link.events.get()[0])
        self.assertIn('error', events)
        self.assertIn('closed', events)


if __name__ == '__main__':
    unittest.main()
