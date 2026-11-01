import unittest
from unittest.mock import Mock
from fpga_guitar import GuitarStream,FpgaGuitarState,decode_guitar
from touchpad_core import crc8,TouchpadMapping
from keyboard_core import StreamParser
from test_touchpad import wire as touch_wire

def wire(board=1,packet=1,sample=1,tick=0,flags=3,mask=0,x=102,y=512,dropped=0):
    body=f'G1{board}{packet:04X}{sample:04X}{tick:08X}{flags:X}{mask:02X}{x:03X}{y:03X}{dropped:04X}'.encode()
    return body+f'*{crc8(body):02X}\r\n'.encode()

class ProtocolTests(unittest.TestCase):
    def test_crc_fragmentation_and_mixed_old_frames(self):
        records=[];fast=GuitarStream(lambda r,t:records.append(r));ui=StreamParser()
        source=touch_wire()+wire()+wire(packet=2,tick=4,mask=7,flags=7)+touch_wire(seq=2)
        for byte in source:
            fast.feed(bytes([byte]),1);ui.feed(bytes([byte]))
        self.assertEqual(len(records),2);self.assertEqual(len(ui.guitar_samples),2)
        self.assertEqual(ui.touchpad_records,2);self.assertEqual(ui.guitar_errors,0)
        corrupt=bytearray(wire());corrupt[12]^=1
        fast.feed(corrupt,1);self.assertEqual(fast.errors,1)
        self.assertEqual(len(wire()),37)
        with self.assertRaises(ValueError):decode_guitar(wire(mask=64))
        with self.assertRaises(ValueError):decode_guitar(wire(flags=0,mask=7))

class HardwareEventTests(unittest.TestCase):
    def setUp(self):
        self.audio=Mock();self.audio.ready=True
        self.state=FpgaGuitarState(self.audio)
        self.state.configure(True,TouchpadMapping())
    def send(self,now,**fields):self.state.receive(decode_guitar(wire(**fields)),now)
    def test_direct_event_path_no_gui_poll_and_multiple_strings(self):
        self.send(1)
        self.send(1.004,packet=2,sample=2,tick=4,mask=7,flags=7)
        self.assertEqual([c.args[0].string for c in self.audio.pluck.call_args_list],[0,1,2])
        self.send(1.004,packet=2,sample=2,tick=4,mask=7,flags=7)
        self.send(1.020,packet=3,sample=3,tick=20,mask=0)
        self.assertEqual(self.audio.pluck.call_count,3)
        self.send(1.024,packet=4,sample=4,tick=24,mask=7)
        self.assertEqual([c.args[0].string for c in self.audio.pluck.call_args_list][-3:],[2,1,0])
    def test_mapping_uses_hardware_other_axis_and_reverses_string_order(self):
        self.state.configure(True,TouchpadMapping(swap_boards=True,transpose=False,flip_x=True))
        self.send(1)
        self.send(1.004,packet=2,tick=4,mask=7,flags=7)
        self.assertEqual(self.audio.pluck.call_count,0)
        self.send(1.020,packet=3,tick=20,mask=0x28,flags=11)
        self.assertEqual([c.args[0].string for c in self.audio.pluck.call_args_list],[5,3])
    def test_muted_stale_first_contact_and_clock_wrap(self):
        self.send(1,tick=0xfffffffe,mask=7,flags=7,packet=65535)
        self.assertEqual(self.audio.pluck.call_count,0)
        self.send(1.004,tick=2,packet=0,mask=7,flags=7)
        self.assertEqual(self.audio.pluck.call_count,3)
        self.state.configure(False,TouchpadMapping())
        self.send(1.020,tick=18,packet=1,mask=7)
        self.assertEqual(self.audio.pluck.call_count,3)
        self.state.configure(True,TouchpadMapping())
        self.send(2,tick=30,packet=2,mask=7)
        self.assertEqual(self.audio.pluck.call_count,3)
        self.assertEqual(self.state.stale,1)
        self.assertEqual(self.state.packet_gaps,0)
    def test_each_pad_anchors_separately_and_overflow_visible(self):
        self.send(1);self.send(1.001,board=2)
        self.send(1.005,board=2,packet=2,sample=2,tick=4,mask=7,flags=7,dropped=2)
        self.assertEqual(self.state.counts,[0,0,0,1,1,1])
        self.assertEqual(self.state.snapshot()['boards'][1]['dropped'],2)

if __name__=='__main__':unittest.main()
