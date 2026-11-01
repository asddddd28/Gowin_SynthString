import argparse
from array import array
import tempfile
import time
from pathlib import Path
import tkinter as tk
import unittest
from unittest.mock import patch
from app import KeyboardApp
from guitar_audio import GuitarMixer, plucked_string
from guitar_core import StrumDetector, display_point
from touchpad_core import TouchpadMapping
from test_encoders import FakeReader
from test_touchpad import wire


class CrossingTests(unittest.TestCase):
    def test_landing_holding_vertical_and_lift_do_not_pluck(self):
        d=StrumDetector()
        for seq,point in enumerate([(.50,.3),(.50,.5),(.52,.7),(.49,.6),None,(.90,.4)]):
            self.assertEqual(d.update(0,point,seq,1+seq*.08),[])
        self.assertEqual(sum(d.counts),0)

    def test_sweep_crosses_each_string_in_order_and_reverse(self):
        d=StrumDetector();d.update(0,(.1,.5),1,1)
        events=d.update(0,(.9,.5),2,1.08)
        self.assertEqual([e.string for e in events],[0,1,2])
        self.assertEqual([e.direction for e in events],[1,1,1])
        self.assertTrue(events[0].delay < events[1].delay < events[2].delay)
        events=d.update(0,(.1,.5),3,1.18)
        self.assertEqual([e.string for e in events],[2,1,0])
        self.assertEqual(d.counts,[2,2,2,0,0,0])

    def test_hysteresis_duplicate_gap_timeout_and_wrap(self):
        d=StrumDetector();d.update(0,(.4,.5),65535,1)
        for seq,x in enumerate([.49,.51,.48,.52]):
            self.assertEqual(d.update(0,(x,.5),seq,1.05+seq*.05),[])
        self.assertEqual([e.string for e in d.update(0,(.6,.5),4,1.25)],[1])
        self.assertEqual(d.update(0,(.1,.5),4,1.30),[])
        self.assertEqual(d.update(0,(.1,.5),7,1.35),[])
        self.assertEqual(d.update(0,(.9,.5),8,2),[])
        d.reset();d.update(0,(.1,.5),65535,3)
        self.assertEqual(len(d.update(0,(.9,.5),0,3.08)),3)

    def test_two_boards_do_not_bridge_contact_and_mapping_matches_draw(self):
        d=StrumDetector();d.update(0,(.9,.5),1,1)
        self.assertEqual(d.update(1,(.1,.5),1,1.05),[])
        self.assertEqual([e.string for e in d.update(1,(.9,.5),2,1.13)],[3,4,5])
        d.reset();d.update(0,(.1,.5),1,2,True)
        self.assertEqual([e.string for e in d.update(0,(.9,.5),2,2.08,True)],[3,4,5])
        self.assertEqual(display_point((0,1),TouchpadMapping()),(.9,.5/7))


class AudioTests(unittest.TestCase):
    def test_silence_polyphony_delayed_onset_and_panic(self):
        m=GuitarMixer([array('h',[1000]*50)]*6,1000);m.volume=1
        self.assertEqual(m.render(10),bytes(40))
        m.pluck(0);m.pluck(1,.005)
        block=array('h');block.frombytes(m.render(10,1))
        self.assertEqual(list(block),[1000]*5+[2000]*5)
        m.silence();self.assertEqual(m.render(10),bytes(40))

    def test_plucked_wave_has_attack_tail_and_bounded_pcm(self):
        sample=plucked_string(110,22050,duration=1)
        self.assertEqual(len(sample),22050)
        self.assertEqual(sample[0],0);self.assertEqual(sample[-1],0)
        self.assertGreater(max(sample),100)
        self.assertLessEqual(max(abs(v) for v in sample),9500)
        self.assertLess(sum(v*v for v in sample[-2205:]),sum(v*v for v in sample[2205:4410]))


class GuitarAppTests(unittest.TestCase):
    @patch('app.GuitarAudio.start')
    @patch('app.GuitarAudio.pluck')
    def test_raw_touch_frames_never_trigger_host_crossing(self, pluck, _start):
        with tempfile.TemporaryDirectory() as folder:
            root=tk.Tk();root.attributes('-alpha',0)
            args=argparse.Namespace(state_dir=Path(folder),profile=None,port=None,replay=None,diagnostics=None,quit_after=None)
            app=KeyboardApp(root,args);reader=FakeReader();app._start_reader(reader,'live','test')
            try:
                # Default transpose makes E0/E4 the left/right extremes; E8 sets middle Y.
                now=time.monotonic()
                reader.data.put((now,wire(seq=1,mask=(1<<0)|(1<<8))))
                app._poll();app.guitar_audio.ready=True
                reader.data.put((now+.01,wire(seq=2,mask=(1<<0)|(1<<8))))
                app._poll()
                self.assertEqual(pluck.call_count,0)
                reader.data.put((now+.09,wire(seq=3,mask=(1<<4)|(1<<8))))
                app._poll();self.assertEqual(pluck.call_count,0)
                app.input_kind='replay'
                reader.data.put((now+.17,wire(seq=4,mask=(1<<0)|(1<<8))))
                app._poll();self.assertEqual(pluck.call_count,0)
                app.input_kind='live';app.set_guitar(False,.3)
                reader.data.put((now+.25,wire(seq=5,mask=(1<<4)|(1<<8))))
                app._poll();self.assertEqual(pluck.call_count,0)
            finally:app.close()
