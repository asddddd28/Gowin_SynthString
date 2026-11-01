"""Protocol, counter rollover and real-capture/App regression tests."""
import argparse
import csv
from pathlib import Path
import queue
import tempfile
import time
import tkinter as tk
import unittest
from unittest.mock import patch

from app import KeyboardApp
from encoder_core import EncoderState, decode_encoder, PHYSICAL_ORDER
from keyboard_core import StreamParser


def wire(channel=1, p=0, n=0, x=0, a=3, f=3):
    return f'E{channel} A{a} F{f} Q{(p-n)&65535:04X} P{p:04X} N{n:04X} X{x:04X}\r\n'.encode()


class EncoderProtocolTests(unittest.TestCase):
    def test_every_split_and_mixed_keyboard_stream(self):
        data = b'K01:ABC\r\n' + wire(5, p=2, n=3, a=1, f=2) + b'K02:123\r\n'
        for split in range(len(data) + 1):
            parser = StreamParser()
            samples = parser.feed(data[:split]) + parser.feed(data[split:])
            self.assertEqual(samples, [(1, 0xabc), (2, 0x123)])
            record = parser.encoder_samples.popleft()
            self.assertEqual((record.channel, record.raw, record.filtered, record.q), (5, 1, 2, -1))
            self.assertEqual(parser.encoder_errors, 0)

    def test_reject_inconsistent_counts_resync_and_sequence_loss(self):
        bad = wire().replace(b'Q0000', b'Q0001')
        with self.assertRaises(ValueError):
            decode_encoder(bad)
        parser = StreamParser()
        parser.feed(b'junk' + bad + wire(4) + wire(1) + wire(2))
        self.assertEqual([r.channel for r in parser.encoder_samples], [4, 1, 2])
        self.assertGreater(parser.encoder_errors, 0)
        self.assertEqual(parser.encoder_sequence_errors, 1)
        parser.feed(b'?' * 100000)
        self.assertLess(len(parser.buffer), 34)

    def test_signed_and_unsigned_rollover_and_direction(self):
        model = EncoderState()
        c = model.channels[0]
        model.update(decode_encoder(wire(p=32766)), 1)
        model.update(decode_encoder(wire(p=32770)), 1.1)
        self.assertEqual(c.record.q, -32766)
        self.assertEqual(c.edges, 4)
        self.assertIn('顺时针', c.direction(1.1))
        model = EncoderState()
        c = model.channels[0]
        model.update(decode_encoder(wire(p=65534, n=65534, x=65535)), 1)
        model.update(decode_encoder(wire(p=2, n=65534, x=0)), 1.1)
        model.update(decode_encoder(wire(p=2, n=2, x=0)), 1.2)
        self.assertEqual((c.edges, c.positive, c.negative, c.invalid), (0, 4, 4, 1))
        self.assertIn('逆时针', c.direction(1.2))

    def test_baseline_zero_stale_gap_reset_and_bounce(self):
        model = EncoderState()
        c = model.channels[0]
        model.update(decode_encoder(wire(p=100)), 1)
        self.assertEqual(c.edges, 0)
        self.assertEqual(c.direction(1), '静止')
        model.update(decode_encoder(wire(p=104)), 1.1)
        model.zero()
        self.assertEqual((c.edges, c.record.q, c.positive), (0, 104, 4))
        model.update(decode_encoder(wire(p=108, n=4)), 1.2)
        self.assertEqual(c.direction(1.2), '往返 / 抖动')
        model.update(decode_encoder(wire(p=108, n=4)), 1.7)
        self.assertEqual(c.direction(1.85), '静止')
        self.assertEqual(c.direction(2.4), '数据超时')
        model.update(decode_encoder(wire(p=200, n=4)), 3)
        self.assertEqual((c.edges, c.discontinuities), (0, 1))
        model.update(decode_encoder(wire()), 3.1)
        self.assertEqual((c.edges, c.discontinuities), (0, 2))
        model.update(decode_encoder(wire(p=4)), 3.2)
        self.assertEqual(c.edges, 4)
        model.invalidate()
        self.assertFalse(c.fresh(3.2))

    def test_saved_physical_trials(self):
        folder = Path(__file__).resolve().parents[1] / 'diagnostics/encoder/reports'
        trials = [('encoder_restart_first_20261031_232319.bin', {5}),
                  ('encoder_resolder_remaining_20261031_232537.bin', {1, 2, 3}),
                  ('encoder_resolder_second_only_20261031_232846.bin', set())]
        for name, moved in trials:
            parser, model = StreamParser(), EncoderState()
            raw = (folder / name).read_bytes()
            clock = 0
            for offset in range(0, len(raw), 113):
                parser.feed(raw[offset:offset + 113])
                while parser.encoder_samples:
                    clock += .02
                    model.update(parser.encoder_samples.popleft(), clock)
            # The capture joins warm-up and steady-state with one truncated E1 line.
            # The parser must reject it and recover without losing subsequent moves.
            self.assertEqual(parser.encoder_errors, 1, name)
            self.assertEqual(parser.encoder_sequence_errors, 0, name)
            self.assertGreater(parser.encoder_records, 3000)
            for i, c in enumerate(model.channels, 1):
                self.assertEqual((c.positive, c.negative), (20, 20) if i in moved else (0, 0), (name, i))
                self.assertEqual((c.edges, c.invalid, c.discontinuities), (0, 0, 0), (name, i))


class FakeThread:
    def is_alive(self):
        return False


class FakeReader:
    def __init__(self):
        self.status, self.data = queue.Queue(), queue.Queue()
        self.thread = FakeThread()
        self.tx_bytes = self.dropped = 0
        self.sent = []

    def start(self):
        self.status.put(('ready', 'test'))

    def send(self, packet):
        self.sent.append(packet)
        self.tx_bytes += len(packet)

    def stop(self):
        pass


class EncoderAppTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = tk.Tk()
        self.root.attributes('-alpha', 0)
        args = argparse.Namespace(state_dir=Path(self.folder.name), profile=None, port=None,
                                  replay=None, diagnostics=None, quit_after=None)
        self.app = KeyboardApp(self.root, args)
        self.root.update_idletasks()
        self.reader = FakeReader()
        self.app._start_reader(self.reader, 'live', 'test')

    def tearDown(self):
        self.app.close()
        self.folder.cleanup()

    def receive(self, data):
        self.reader.data.put((time.monotonic(), data))
        self.app._poll()
        self.app.poll_board(time.monotonic())

    def test_passive_autodetection_no_commands_and_reconnect_reset(self):
        self.app._poll()
        self.app.poll_board(time.monotonic())
        self.assertEqual(self.reader.sent, [])
        self.receive(b''.join(wire(i) for i in range(1, 6)))
        self.assertEqual(self.app.protocol, 'encoder')
        self.assertEqual(self.app.notebook.select(), str(self.app.encoders_page))
        self.assertFalse(self.app.auto_sync_pending)
        self.receive(wire(5, p=20))
        self.assertEqual(self.app.encoders.channels[4].edges, 20)
        self.app.zero_encoders()
        self.app.send_effect()
        self.app.request_sync()
        self.assertEqual(self.reader.sent, [])
        self.app.disconnect()
        self.assertTrue(all(not c.fresh(time.monotonic()) for c in self.app.encoders.channels))
        self.app._start_reader(self.reader, 'live', 'test')
        self.receive(wire(5, p=24))
        self.assertEqual(self.app.encoders.channels[4].edges, 0)
        self.assertEqual(self.reader.sent, [])

    def test_keyboard_still_queries_after_valid_data(self):
        self.receive(b'K01:800\r\n')
        self.assertEqual(self.app.protocol, 'keyboard')
        self.assertEqual(len(self.reader.sent), 1)
        self.assertEqual(len(self.reader.sent[0]), 25)

    def test_encoder_csv_schema_and_samples(self):
        self.receive(wire())
        path = Path(self.folder.name) / 'capture.csv'
        with patch('app.filedialog.asksaveasfilename', return_value=str(path)):
            self.app.toggle_recording()
        self.receive(wire(p=4, a=1, f=1))
        self.app.stop_recording()
        with path.open(encoding='utf-8-sig', newline='') as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(rows[0]['fpga_p'], '4')
        self.assertEqual(rows[0]['relative_edges'], '4')
        self.assertEqual(rows[0]['raw_ab'], '1')

    def test_cards_fit_minimum_window_and_show_timeout(self):
        self.receive(b''.join(wire(i, p=65535) for i in range(1, 6)))
        self.root.geometry('1100x740')
        self.root.update()
        panel = self.app.encoders_page
        panel.refresh(self.app.encoders, time.monotonic(), 'live', 'encoder')
        self.root.update_idletasks()
        self.assertEqual([c['channel'] for c in panel.cards], list(PHYSICAL_ORDER))
        for card in panel.cards:
            frame = card['frame']
            for key in ('value', 'phase', 'counters', 'activity'):
                label = card[key]
                self.assertLessEqual(label.winfo_reqwidth(), label.winfo_width(), key)
                self.assertLessEqual(label.winfo_rooty() + label.winfo_height(),
                                     panel.body.winfo_rooty() + panel.body.winfo_height(), key)
        # The compact window keeps the entire page reachable via its scrollbar.
        self.assertTrue(panel.canvas.cget('scrollregion'))
        panel.refresh(self.app.encoders, time.monotonic() + 1, 'live', 'encoder')
        self.assertTrue(all(c['status'].cget('text') == '数据超时' for c in panel.cards))


if __name__ == '__main__':
    unittest.main()
