"""独立 OSC 字节向量、本机 UDP 和软件参数到既有硬件协议的联调。"""
import copy
import math
import socket
import struct
import unittest

from profiles import preset, words
from surge_bridge import OscReader, SurgeSnapshot, decode_packet, map_envelope


def message(address, number=0.5, label='软件读数'):
    def string(value):
        raw = value.encode('utf-8') + b'\0'
        return raw + bytes((-len(raw)) % 4)
    return string(address) + b',fs\0' + struct.pack('>f', number) + string(label)


def fixture(scene='a'):
    snapshot = SurgeSnapshot()
    prefix = '/param/' + scene + '/aeg/'
    for field, value in (('attack', 0.0), ('decay', 8/13), ('release', 7/13), ('sustain', .65)):
        snapshot.feed(prefix + field, [value, 'display'])
        snapshot.feed('/doc' + prefix + field, [field, 'float', '0' if field == 'sustain' else '-8', '1' if field == 'sustain' else '5'])
    for field in ('attack', 'decay', 'release'):
        snapshot.feed(prefix + field + '/tempo_sync+', [0.0])
    snapshot.feed(prefix + 'release/deform+', [0.0])
    return snapshot


class SurgeBridgeTests(unittest.TestCase):
    def test_network_byte_order_and_nested_bundle(self):
        raw = message('/param/a/aeg/attack', .25, '起音 500 ms')
        decoded = decode_packet(raw)
        self.assertEqual(decoded, [('/param/a/aeg/attack', [.25, '起音 500 ms'])])
        bundle = b'#bundle\0' + struct.pack('>Q', 1) + struct.pack('>i', len(raw)) + raw
        nested = b'#bundle\0' + struct.pack('>Q', 1) + struct.pack('>i', len(bundle)) + bundle
        self.assertEqual(decode_packet(nested), decoded)

    def test_reject_malformed_packets(self):
        good = message('/param/test')
        for raw in (b'', good[:-1], good+b'\0', b'#bundle\0',
                    b'#bundle\0'+bytes(8)+struct.pack('>i', -1), message('/param/test', math.nan),
                    b'/x\0\0,b\0\0'+bytes(4)):
            with self.assertRaises(ValueError):
                decode_packet(raw)

    def test_real_udp_read_only_and_recovery_after_bad_packet(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        server.bind(('127.0.0.1', 0))
        server.settimeout(2)
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.bind(('127.0.0.1', 0))
        receive_port = probe.getsockname()[1]
        probe.close()
        client = OscReader(server.getsockname()[1], receive_port)
        try:
            client.start()
            query, peer = server.recvfrom(1024)
            self.assertEqual(query, b'/q/all_params\0\0\0,\0\0\0')
            server.sendto(b'malformed', peer)
            server.sendto(message('/param/a/aeg/sustain', .5), peer)
            kind, data = client.events.get(timeout=2)
            self.assertEqual(kind, 'messages')
            self.assertEqual(data[0][0], '/param/a/aeg/sustain')
            self.assertEqual(data[0][1][0], .5)
        finally:
            client.close()
            server.close()
        self.assertFalse(client.thread.is_alive())

    def test_map_native_units_and_preserve_timbre(self):
        original = preset('FM 电钢琴')
        before = copy.deepcopy(original)
        profile, notes = map_envelope(fixture(), original)
        self.assertEqual(profile['attack'], 0)
        self.assertAlmostEqual(profile['decay'], 1000)
        self.assertAlmostEqual(profile['release'], 500)
        self.assertAlmostEqual(profile['sustain'], 65)
        self.assertEqual(original, before)
        for key in original:
            if key not in ('attack','decay','sustain','release'):
                self.assertEqual(profile[key], original[key])
        self.assertEqual(len(words(profile)), 18)
        self.assertTrue(words(profile)[0] & 0x8000)
        self.assertIn('不是完整音色转换', notes[-1])

    def test_reject_incomplete_tempo_freeze_and_overlong(self):
        for field, value in (('attack/tempo_sync+', 1), ('release/deform+', 1), ('decay', 11/13), ('sustain', -1)):
            data = fixture()
            data.feed('/param/a/aeg/' + field, [value])
            with self.assertRaises(ValueError):
                map_envelope(data, preset('正弦'))
        data = fixture()
        del data.docs['/param/a/aeg/attack']
        with self.assertRaises(ValueError):
            map_envelope(data, preset('正弦'))
        with self.assertRaises(ValueError):
            map_envelope(fixture(), preset('正弦'), 'b')
        self.assertEqual(map_envelope(fixture('b'), preset('正弦'), 'b')[0]['attack'], 0)

    def test_snapshot_roundtrip_patch_reset_and_bad_json(self):
        data = fixture()
        saved = data.export()
        restored = SurgeSnapshot.from_json(saved)
        self.assertEqual(restored.export()['parameters'], saved['parameters'])
        restored.parameters['/param/a/aeg/attack']['value'] = .1
        self.assertEqual(data.parameters['/param/a/aeg/attack']['value'], 0)
        self.assertTrue(data.feed('/patch/load', ['test.fxp']))
        self.assertEqual((data.parameters, data.docs), ({},{}))
        corrupt = copy.deepcopy(saved)
        corrupt['parameters']['/param/a/aeg/attack']['value'] = True
        with self.assertRaises(ValueError):
            SurgeSnapshot.from_json(corrupt)


if __name__ == '__main__':
    unittest.main()
