import argparse
import tempfile
import time
import tkinter as tk
import unittest
from pathlib import Path
from unittest.mock import patch
from app import KeyboardApp,EFFECTS
from hardware_core import decode_hardware
from keyboard_core import StreamParser
from test_encoders import FakeReader,wire as encoder_wire
from test_touchpad import wire as touch_wire
from test_fpga_guitar import wire as guitar_wire
from touchpad_core import crc8

IDENTITY=b'H1007F0100*66\r\n'
def mixed():
    return IDENTITY+b''.join(f'K{k:02d}:384\r\n'.encode() for k in range(1,33))+b''.join(encoder_wire(k) for k in range(1,6))+b'J0000 R10 F10 P0000\r\n'+touch_wire(board=1)+touch_wire(board=2)+guitar_wire()

class HardwareProtocolTests(unittest.TestCase):
    def test_every_byte_fragment_and_all_families(self):
        p=StreamParser()
        for b in mixed():p.feed(bytes([b]))
        self.assertEqual((p.records,p.encoder_records,p.joystick_records,p.touchpad_records,p.guitar_records,p.hardware_records),(32,5,1,2,1,1))
        self.assertEqual(p.discarded,0)
        self.assertEqual(decode_hardware(IDENTITY).capabilities,127)
    def test_bad_crc_or_new_major_cannot_enable_hub(self):
        with self.assertRaises(ValueError):decode_hardware(IDENTITY.replace(b'*66',b'*67'))
        body=b'H1007F0200'
        with self.assertRaises(ValueError):decode_hardware(body+f'*{crc8(body):02X}\r\n'.encode())

class HardwareAppTests(unittest.TestCase):
    @patch('app.GuitarAudio.start')
    def test_valid_identity_promotes_single_protocol_and_all_pages_update(self,_start):
        with tempfile.TemporaryDirectory() as folder:
            root=tk.Tk();root.attributes('-alpha',0)
            args=argparse.Namespace(state_dir=Path(folder),profile=None,port=None,replay=None,diagnostics=None,quit_after=None)
            app=KeyboardApp(root,args);reader=FakeReader();app._start_reader(reader,'live','test')
            try:
                now=time.monotonic();reader.data.put((now,touch_wire()));app._poll()
                self.assertEqual(app.protocol,'touchpad')
                reader.data.put((now,mixed()));app._poll();root.after_cancel(app.tick_id);app.tick()
                self.assertEqual(app.protocol,'hub')
                self.assertEqual(sum(app.model.fresh(i,now) for i in range(32)),32)
                self.assertEqual(sum(c.fresh(now) for c in app.encoders.channels),5)
                self.assertTrue(app.joystick.fresh(now))
                self.assertTrue(all(app.touchpad.fresh(i,now) for i in range(2)))
                self.assertIn('综合状态 40/40',app.stats_var.get())
                app.navigate_hardware('touchpad');self.assertTrue(app.guitar_allowed())
                app.effect_var.set(EFFECTS[-1]);self.assertEqual(app.selected_effect()[0],6)
                app.navigate_hardware('keyboard');self.assertFalse(app.guitar_allowed())
            finally:app.close()
    @patch('app.GuitarAudio.start')
    def test_mixed_raw_record_and_replay_never_send_commands(self,_start):
        with tempfile.TemporaryDirectory() as folder:
            root=tk.Tk();root.attributes('-alpha',0)
            args=argparse.Namespace(state_dir=Path(folder),profile=None,port=None,replay=None,diagnostics=None,quit_after=None)
            app=KeyboardApp(root,args);reader=FakeReader();app._start_reader(reader,'replay','history')
            try:
                reader.data.put((time.monotonic(),mixed()));app._poll();root.after_cancel(app.tick_id);app.tick()
                self.assertEqual(app.protocol,'hub');self.assertIsNone(app.board)
                self.assertFalse(app.guitar_allowed())
                path=Path(folder)/'mixed.bin'
                with patch('app.filedialog.asksaveasfilename',return_value=str(path)):app.toggle_recording()
                reader.data.put((time.monotonic(),mixed()));app._poll();app.stop_recording()
                self.assertEqual(path.read_bytes(),mixed())
            finally:app.close()

if __name__=='__main__':unittest.main()
