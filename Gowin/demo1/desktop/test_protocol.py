"""协议边界、串口分包以及同一音键的输入所有权回归。"""
import copy
import json
import unittest
from pathlib import Path
from functools import reduce
from operator import xor
from protocol import packet, defaults, validate_config, StatusParser, sound_packets, piano_sound


class ProtocolTests(unittest.TestCase):
    def test_wire_and_ranges(self):
        self.assertEqual(packet(1, 32, 60, 96).hex(), 'a501203c600000d8')
        config = defaults()
        validate_config(config)
        self.assertEqual(len({x['keycode'] for x in config['keys']}), 32)
        for index, key in enumerate(config['keys']):
            frame = packet(1, 32+index, key['note'], key['velocity'])
            self.assertEqual(reduce(xor, frame), 0)
        config['keys'][1]['keycode'] = config['keys'][0]['keycode']
        with self.assertRaises(ValueError):
            validate_config(config)

    def test_bad_config(self):
        for malformed in [dict(version=1, keys=None), dict(version=1, keys=[None]*32),
                          dict(defaults(), sound=None)]:
            with self.assertRaises(ValueError):
                validate_config(malformed)
        for field, value in [('note', 128), ('velocity', 0), ('keycode', 27), ('name', '')]:
            config = defaults()
            config['keys'][0][field] = value
            with self.assertRaises(ValueError):
                validate_config(config)
        config = defaults()
        config['sound']['attack'] = float('nan')
        with self.assertRaises(ValueError):
            validate_config(config)

    def test_status_fragment_corruption(self):
        data = bytes([0xA5, 0x85, 0, 32, 32, 7, 1]) + (123).to_bytes(4, 'little') + (0xA585).to_bytes(4, 'little')
        frame = data + bytes([reduce(xor, data)])
        parser = StatusParser()
        self.assertEqual(parser.feed(b'noise' + frame[:9]), [])
        result = parser.feed(frame[9:] + b'\xa5\x85' + b'\0'*14 + frame)
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0]['voices'], 32)
        self.assertEqual(result[0]['cycles'], 263)
        self.assertEqual(result[0]['clips'], 123)

    def test_piano_wire_parameters(self):
        config = defaults(); config['sound'] = piano_sound()
        validate_config(config)
        values = {f[2]: int.from_bytes(f[5:7], 'little') for f in sound_packets(config['sound'])}
        self.assertEqual((values[5], values[6]), (3, 0))
        self.assertEqual(values[7] + values[8], 65535)
        self.assertEqual(values[3], 0)
        self.assertEqual(values[2], 2)
        self.assertGreater(values[4], 0)
        self.assertEqual(values[9], 0)
        ordinary = {f[2]: int.from_bytes(f[5:7], 'little') for f in sound_packets(defaults()['sound'])}
        self.assertEqual((ordinary[5], ordinary[6], ordinary[8], ordinary[9]), (0, 0, 0, 0))

    def test_adsr_steps(self):
        frames = sound_packets(defaults()['sound'])
        values = {f[2]: int.from_bytes(f[5:7], 'little') for f in frames}
        self.assertEqual(values[1], 273)
        self.assertEqual(values[2], 27)
        self.assertEqual(values[4], 27)
        self.assertEqual(values[10], 32)
        sound = defaults()['sound']; sound['attack'] = 0
        self.assertEqual(sound_packets(sound)[1][5:7], b'\0\0')

    def test_output_gain_migration_and_bounds(self):
        config=defaults();validate_config(config)
        self.assertEqual(config['sound']['output_boost'],0)
        for boost in range(5):
            config['sound']['output_boost']=boost
            validate_config(config)
            self.assertEqual(sound_packets(config['sound'])[-1],packet(3,12,value=boost))
        for boost in (-1,5,1.5,True):
            config['sound']['output_boost']=boost
            with self.assertRaises(ValueError):validate_config(config)


def vectors():
    frames = [packet(3, identity=i, value=0) for i in (1, 2, 4)]
    frames += [packet(1, 32+i, 48+i, 96) for i in range(32)]
    frames += [packet(2, 32+i) for i in range(32)]
    frames += [packet(1, 32, 60, 96), packet(5), packet(4)]
    target = Path(__file__).resolve().parents[1] / 'sim' / 'work' / 'uartkeys.mem'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('\n'.join(f'{b:02x}' for frame in frames for b in frame), encoding='ascii')


if __name__ == '__main__':
    vectors()
    unittest.main()
