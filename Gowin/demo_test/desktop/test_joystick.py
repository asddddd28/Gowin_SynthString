import argparse
import csv
from pathlib import Path
import tempfile
import time
import tkinter as tk
import unittest
from unittest.mock import patch

from app import KeyboardApp
from joystick_core import decode_joystick, axis_region, JoystickState, JoystickMapping
from keyboard_core import StreamParser
from test_encoders import FakeReader


def wire(seq=0, raw=21, filtered=21, presses=0):
    return f'J{seq:04X} R{raw:02X} F{filtered:02X} P{presses:04X}\r\n'.encode()


class JoystickTests(unittest.TestCase):
    def test_saved_orientation_preserves_unknown_axes_and_rejects_bad_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'joystick_mapping.json'
            mapping = JoystickMapping(flip_y=True)
            mapping.save(path)
            loaded = JoystickMapping.load(path)
            self.assertEqual(loaded.apply(1, 1), (1, -1))
            self.assertEqual(loaded.apply(None, 1), (None, -1))
            self.assertEqual(JoystickMapping(swap=True, flip_x=True).apply(-1, 1), (-1, -1))
            path.write_text('{"swap": false, "flip_x": false, "flip_y": "false"}', encoding='utf8')
            with self.assertRaises(ValueError):
                JoystickMapping.load(path)

    def test_all_packet_splits_and_counter_wrap(self):
        data = wire(65535) + wire(0, 5, 5, 1)
        for split in range(len(data) + 1):
            parser = StreamParser()
            parser.feed(data[:split])
            parser.feed(data[split:])
            self.assertEqual(parser.joystick_records, 2)
            self.assertEqual(parser.joystick_sequence_errors, 0)
            self.assertEqual(parser.joystick_samples[-1].presses, 1)

    def test_bad_frame_resync_missing_sequence_and_mixed_records(self):
        parser = StreamParser()
        parser.feed(b'J0000 RFF F15 P0000\r\n' + wire(7) + b'K01:ABC\r\n' + wire(9))
        self.assertEqual(parser.joystick_records, 2)
        self.assertEqual(parser.records, 1)
        self.assertGreater(parser.joystick_errors, 0)
        self.assertEqual(parser.joystick_sequence_errors, 1)

    def test_threshold_regions_and_stale_press(self):
        self.assertEqual([axis_region(n) for n in range(4)], [-1, 0, None, 1])
        state = JoystickState()
        state.update(decode_joystick(wire()), 1)
        self.assertEqual((state.snapshot(1)['x'], state.snapshot(1)['y']), (0, 0))
        state.update(decode_joystick(wire(1, 15, 15, 1)), 1.1)
        self.assertTrue(state.snapshot(1.1)['pressed'])
        self.assertFalse(state.snapshot(2)['pressed'])
        self.assertFalse(state.snapshot(2)['fresh'])

    def test_app_passive_detection_csv_and_page(self):
        with tempfile.TemporaryDirectory() as folder:
            root = tk.Tk()
            root.attributes('-alpha', 0)
            args = argparse.Namespace(state_dir=Path(folder), profile=None, port=None, replay=None,
                                      diagnostics=None, quit_after=None)
            app = KeyboardApp(root, args)
            root.update_idletasks()
            reader = FakeReader()
            app._start_reader(reader, 'live', 'test')
            try:
                reader.data.put((time.monotonic(), wire()))
                app._poll()
                app.poll_board(time.monotonic())
                self.assertEqual(app.protocol, 'joystick')
                self.assertEqual(app.notebook.select(), str(app.joystick_page))
                self.assertEqual(reader.sent, [])
                app.joystick_page.flip_y.set(True)
                app.joystick_page.mapping_changed()
                self.assertTrue(JoystickMapping.load(app.joystick_mapping_path).flip_y)
                path = Path(folder) / 'joystick.csv'
                with patch('app.filedialog.asksaveasfilename', return_value=str(path)):
                    app.toggle_recording()
                reader.data.put((time.monotonic(), wire(1, 5, 5, 1)))
                app._poll()
                app.stop_recording()
                app.joystick_page.refresh(app.joystick, time.monotonic(), 'live', 'joystick')
                self.assertIn('按下', app.joystick_page.button.cget('text'))
                reader.data.put((time.monotonic(), wire(2, 29, 29, 1)))
                app._poll()
                app.joystick_page.refresh(app.joystick, time.monotonic(), 'live', 'joystick')
                self.assertEqual(app.joystick_page.pad.direction, '下')
                with path.open(encoding='utf-8-sig', newline='') as handle:
                    rows = list(csv.DictReader(handle))
                self.assertEqual(rows[0]['press_count'], '1')
                self.assertEqual(rows[0]['filtered_bits'], '5')
                app.disconnect()
                self.assertFalse(app.joystick.fresh(time.monotonic()))
                app.joystick_page.refresh(app.joystick, time.monotonic(), 'none', 'joystick')
                self.assertFalse(app.joystick_page.pad.valid)
                self.assertEqual(app.joystick_page.pad.shown, (0, 0))
            finally:
                app.close()


if __name__ == '__main__':
    unittest.main()
