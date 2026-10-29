"""验证长包络的时间误差、编码边界与旧版本量化问题。"""
import math
import unittest
from envelope import FULL_LEVEL, FULL_STATE, FRACTION_BITS, encode_step, decode_step, duration_samples
from protocol import SAMPLE_RATE


class EnvelopePrecisionTests(unittest.TestCase):
    def test_long_envelopes_match_time(self):
        for distance in (FULL_LEVEL, FULL_LEVEL // 2, FULL_LEVEL // 10):
            for milliseconds in (10, 100, 1000, 2500, 5000):
                word = encode_step(distance, milliseconds, SAMPLE_RATE)
                actual = duration_samples(distance, word) * 1000 / SAMPLE_RATE
                self.assertLessEqual(abs(actual-milliseconds), milliseconds*.0006 + 1000/SAMPLE_RATE)

    def test_previous_five_second_failure_is_resolved(self):
        old_step = max(1, round(FULL_LEVEL / (5*SAMPLE_RATE)))
        old_ms = math.ceil(FULL_LEVEL/old_step)*1000/SAMPLE_RATE
        self.assertLess(old_ms, 2800)
        actual = duration_samples(FULL_LEVEL, encode_step(FULL_LEVEL, 5000, SAMPLE_RATE))*1000/SAMPLE_RATE
        self.assertLess(abs(actual-5000), 3)

    def test_zero_short_and_invalid_steps(self):
        self.assertEqual(encode_step(FULL_LEVEL, 0, SAMPLE_RATE), 0)
        self.assertEqual(encode_step(0, 5000, SAMPLE_RATE), 0)
        self.assertEqual(decode_step(encode_step(FULL_LEVEL, .001, SAMPLE_RATE)), FULL_STATE)
        for value in (-1, 65536, 23 << 11, 1 << 11, True):
            with self.assertRaises(ValueError):
                decode_step(value)

    def test_rate_rounding_is_monotonic(self):
        rates = [decode_step(encode_step(FULL_LEVEL, ms, SAMPLE_RATE)) for ms in range(1, 5001)]
        self.assertEqual(rates, sorted(rates, reverse=True))
        self.assertEqual(FULL_STATE, FULL_LEVEL << FRACTION_BITS)


if __name__ == '__main__':
    unittest.main()
