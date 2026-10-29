import json
import math
import random
import tempfile
import unittest
from pathlib import Path

from keyboard_core import CalibrationSession, KeyCalibration, KeyboardState, Profile, StreamParser


def frame(values=None):
    values = values or list(range(32))
    return b"".join(f"K{k:02d}:{value:03X}\r\n".encode() for k, value in enumerate(values, 1))


class ProtocolTests(unittest.TestCase):
    def test_every_byte_split_and_continuous_scans(self):
        parser = StreamParser()
        result = []
        for byte in frame() * 3:
            result += parser.feed(bytes([byte]))
        self.assertEqual(result, [(k, k - 1) for k in range(1, 33)] * 3)
        self.assertEqual((parser.scans, parser.sequence_errors, parser.discarded), (3, 0, 0))

    def test_noise_invalid_keys_and_partial_recovery(self):
        parser = StreamParser()
        data = b"boot\x00K00:123\r\nK33:456\r\nK01:XXZ\r\nK02:ABC\r\nK03:FFF\r\n"
        self.assertEqual(parser.feed(data), [(2, 0xABC), (3, 4095)])
        self.assertGreater(parser.discarded, 0)
        self.assertLessEqual(len(parser.buffer), 8)

    def test_missing_and_duplicate_records_report_sequence_fault(self):
        parser = StreamParser()
        parser.feed(b"K01:123\r\nK03:123\r\nK03:123\r\nK04:123\r\n")
        self.assertEqual(parser.sequence_errors, 2)
        self.assertEqual(parser.scans, 0)

    def test_large_garbage_does_not_accumulate(self):
        parser = StreamParser()
        parser.feed(b"X" * 200000 + b"K0")
        self.assertEqual(bytes(parser.buffer), b"K0")
        self.assertEqual(parser.feed(b"1:800\r\n"), [(1, 2048)])

    def test_real_recording_arbitrary_chunks(self):
        path = Path(__file__).resolve().parent.parent / "reports/keyboard_after_cn1_rework_all_keys_20261029_024626.bin"
        parser = StreamParser()
        data = path.read_bytes()
        rng, offset = random.Random(42), 0
        while offset < len(data):
            size = rng.randrange(1, 1500)
            parser.feed(data[offset:offset + size])
            offset += size
        self.assertEqual(parser.records, 113131)
        self.assertEqual(parser.sequence_errors, 0)
        self.assertEqual(parser.discarded, 0)


class ProfileTests(unittest.TestCase):
    def profile(self):
        return Profile([KeyCalibration(900, 120, 12)] * 32, "test", "unit test")

    def test_polarity_clipping_and_middle(self):
        decreasing = KeyCalibration(900, 100)
        increasing = KeyCalibration(100, 900)
        self.assertEqual(decreasing.depth(500), .5)
        self.assertEqual(increasing.depth(500), .5)
        self.assertEqual(decreasing.depth(1000), 0)
        self.assertEqual(decreasing.depth(0), 1)

    def test_bad_endpoints_rejected(self):
        for rest, bottom in [(900, 890), (math.nan, 120), (900, math.inf), (4096, 120), (True, 120)]:
            with self.subTest(rest=rest, bottom=bottom), self.assertRaises(ValueError):
                KeyCalibration(rest, bottom)

    def test_partial_profile_roundtrip(self):
        profile = Profile.empty()
        profile.keys[0] = KeyCalibration(900, 120)
        restored = Profile.from_dict(profile.to_dict())
        self.assertEqual(restored.keys[0].rest, 900)
        self.assertIsNone(restored.keys[1])

    def test_atomic_save_load(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "profile.json"
            self.profile().save(path)
            original = path.read_bytes()
            bad = self.profile()
            bad.release_threshold = .9
            with self.assertRaises(ValueError):
                bad.save(path)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(Profile.load(path).keys[31].bottom, 120)
            self.assertEqual(list(Path(directory).glob("*.tmp")), [])

    def test_invalid_schema_and_duplicate_key_do_not_load(self):
        for modifier in [lambda d: d.update(version=99), lambda d: d["keys"].pop(),
                         lambda d: d["keys"][1].update(key=1), lambda d: d.update(press_threshold=float("nan")),
                         lambda d: d.update(release_threshold=.8)]:
            data = self.profile().to_dict()
            modifier(data)
            with self.assertRaises(ValueError):
                Profile.from_dict(data)


class StateTests(unittest.TestCase):
    def model(self):
        return KeyboardState(Profile([KeyCalibration(900, 100)] * 32))

    def test_hysteresis_and_stale_release(self):
        model = self.model()
        for i in range(12):
            model.update(1, 100, i * .03)
        self.assertTrue(model.pressed[0])
        for i in range(12):
            model.update(1, 540, .4 + i * .03)  # 45%: remains pressed inside hysteresis band.
        self.assertTrue(model.pressed[0])
        model.tick(1.5)
        self.assertFalse(model.pressed[0])
        self.assertIsNone(model.depth(0, 1.5))
        model.update(1, 900, 1.6)
        self.assertEqual(model.depth(0, 1.6), 0)
        self.assertFalse(model.pressed[0])

    def test_reconnect_resets_press_and_candidate_keeps_profile(self):
        model = self.model()
        old = model.profile
        model.update(1, 100, 0)
        model.session = CalibrationSession([1], 0)
        model.reset_stream()
        self.assertFalse(any(model.pressed))
        self.assertTrue(all(raw is None for raw in model.raw))
        self.assertIs(model.profile, old)
        self.assertEqual(model.session.stage, "error")

    def test_uncalibrated_keys_do_not_report_fake_depth(self):
        model = KeyboardState()
        model.update(1, 10, 0)
        self.assertIsNone(model.depth(0, 0))
        self.assertFalse(model.pressed[0])


class CalibrationTests(unittest.TestCase):
    def rest_session(self, targets=(1, 2)):
        session = CalibrationSession(targets, 0)
        for frame_index in range(68):
            now = frame_index * .03
            for key in targets:
                session.feed(key, 900 + frame_index % 3, now)
            session.tick(now)
        self.assertEqual(session.stage, "ready")
        session.start_press(2.1)
        return session

    def test_complete_transaction_detects_both_directions(self):
        session = self.rest_session()
        for i in range(20):
            session.feed(1, 120, 2.1 + .03 * i)
            session.feed(2, 1500, 2.1 + .03 * i)
        old = Profile.empty()
        new = session.apply(old, "new", "test")
        self.assertIsNone(old.keys[0])
        self.assertEqual(new.keys[0].bottom, 120)
        self.assertEqual(new.keys[1].bottom, 1500)
        self.assertEqual(new.keys[1].depth(1500), 1)

    def test_one_sample_spike_is_not_an_endpoint(self):
        session = self.rest_session((1,))
        for i, value in enumerate([900] * 7 + [0] + [900] * 10):
            session.feed(1, value, 2.1 + i * .03)
        self.assertFalse(session.complete)
        with self.assertRaises(ValueError):
            session.apply(Profile.empty(), "test", "test")

    def test_unpressed_key_blocks_all_key_commit(self):
        session = self.rest_session()
        for i in range(20):
            session.feed(1, 120, 2.1 + i * .03)
            session.feed(2, 900, 2.1 + i * .03)
        self.assertFalse(session.complete)

    def test_stale_samples_abort_without_commit(self):
        session = self.rest_session((1,))
        session.tick(3)
        self.assertEqual(session.stage, "error")
        self.assertFalse(session.complete)

    def test_unstable_rest_rejected(self):
        session = CalibrationSession([1], 0)
        for i in range(68):
            session.feed(1, 800 if i % 2 else 1200, i * .03)
            session.tick(i * .03)
        self.assertEqual(session.stage, "error")

    def test_selected_key_preserves_other_calibrations(self):
        old = Profile([KeyCalibration(1000, 150)] * 32)
        session = self.rest_session((5,))
        for i in range(15):
            session.feed(5, 120, 2.1 + i * .03)
        result = session.apply(old, "new", "test")
        self.assertEqual(result.keys[4].bottom, 120)
        self.assertEqual(result.keys[3].bottom, 150)


if __name__ == "__main__":
    unittest.main(verbosity=2)
