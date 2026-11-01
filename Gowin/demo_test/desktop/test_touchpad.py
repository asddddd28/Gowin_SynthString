import argparse
from pathlib import Path
import tempfile
import time
import tkinter as tk
import unittest
from unittest.mock import patch
from app import KeyboardApp
from keyboard_core import StreamParser
from touchpad_core import decode_touchpad, TouchpadState, crc8
from test_encoders import FakeReader


def wire(board=1, seq=1, error=0, mask=0x21):
    raw=bytearray(42)
    raw[:2]=mask.to_bytes(2,'little')
    for i in range(12):
        raw[4+2*i:6+2*i]=(700).to_bytes(2,'little')
        raw[30+i]=180
    body=f'T{board}{seq:04X}5A{error:02X}7'.encode()+raw.hex().upper().encode()
    return body+f'*{crc8(body):02X}\r\n'.encode()


class TouchpadTests(unittest.TestCase):
    def test_all_splits_crc_and_resync(self):
        data=wire()+wire(2)
        for split in range(len(data)+1):
            p=StreamParser();p.feed(data[:split]);p.feed(data[split:])
            self.assertEqual(p.touchpad_records,2)
        bad=bytearray(wire());bad[30]^=1
        p=StreamParser();p.feed(bytes(bad)+wire(2))
        self.assertEqual(p.touchpad_records,1)
        self.assertGreater(p.touchpad_errors,0)
        with self.assertRaises(ValueError):decode_touchpad(bytes(bad))
        self.assertEqual(crc8(b'123456789'),0xf4)

    def test_stale_independence_and_counter_stall(self):
        s=TouchpadState();s.update(decode_touchpad(wire()),1)
        self.assertTrue(s.fresh(0,1));self.assertFalse(s.fresh(1,1))
        self.assertEqual(s.position(0,1),(0,0))
        s.update(decode_touchpad(wire()),2)
        self.assertFalse(s.fresh(0,2))
        s.update(decode_touchpad(wire(seq=2)),2)
        self.assertTrue(s.fresh(0,2))
        s.update(decode_touchpad(wire(error=5,seq=3)),2.1)
        self.assertIsNone(s.position(0,2.1))
        s.update(decode_touchpad(wire(seq=4,mask=0x25)),2.2)
        self.assertIsNone(s.position(0,2.2))
        s.invalidate();self.assertFalse(s.fresh(0,2.2))

    @patch('app.GuitarAudio.start')
    def test_app_passive_and_csv(self, _audio_start):
        with tempfile.TemporaryDirectory() as folder:
            root=tk.Tk();root.attributes('-alpha',0)
            args=argparse.Namespace(state_dir=Path(folder),profile=None,port=None,replay=None,diagnostics=None,quit_after=None)
            app=KeyboardApp(root,args);reader=FakeReader();app._start_reader(reader,'live','test')
            try:
                reader.data.put((time.monotonic(),wire()+wire(2)));app._poll();app.tick()
                self.assertEqual(app.protocol,'touchpad')
                self.assertEqual(app.notebook.select(),str(app.touchpad_page))
                self.assertEqual(reader.sent,[])
                file=Path(folder)/'touchpad.csv'
                with patch('app.filedialog.asksaveasfilename',return_value=str(file)):app.toggle_recording()
                reader.data.put((time.monotonic(),wire(seq=2)));app._poll();app.stop_recording()
                self.assertIn('raw_hex',file.read_text(encoding='utf-8-sig'))
                self.assertEqual(len(file.read_text(encoding='utf-8-sig').splitlines()),2)
                app.disconnect();self.assertFalse(app.touchpad.fresh(0,time.monotonic()))
            finally:app.close()
