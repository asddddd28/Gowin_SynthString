import unittest
from board_protocol import *
from keyboard_core import Profile, KeyCalibration, StreamParser, KeyboardState


def reply(seq=0, result=0, configured=1, mode=4, direction=0, generation=1, pressed=0):
    raw = bytes([seq,result,configured,mode*16+direction,generation])+pressed.to_bytes(4,'big')
    return b'@'+raw.hex().upper().encode()+f'*{crc8(raw):02X}\n'.encode()


class BoardProtocolTests(unittest.TestCase):
    def test_crc_known_vector(self):
        self.assertEqual(crc8(b'123456789'), 0xF4)

    def test_command_endpoints_and_printable_bytes(self):
        p=Profile([KeyCalibration(900,100),KeyCalibration(100,900)]+[KeyCalibration(900,100)]*30,press_threshold=.9,release_threshold=.5)
        plan=calibration_commands(p)
        self.assertEqual((plan[1]['press'],plan[1]['release']), (180,500))
        self.assertEqual((plan[2]['press'],plan[2]['release']), (820,500))
        for seq,fields in enumerate(plan):
            wire=command(seq,**fields)
            self.assertEqual(len(wire),25)
            self.assertTrue(all(32<=c<=126 for c in wire[:-1]))
            self.assertEqual(crc8(bytes.fromhex(wire[1:21].decode())),int(wire[22:24],16))

    def test_fragmented_mixed_stream_and_bad_crc(self):
        p=StreamParser()
        stream=b'K01:123\r\n'+reply(pressed=0x80000001)+b'K02:456\r\n'
        samples=[]
        for c in stream:samples+=p.feed(bytes([c]))
        self.assertEqual(samples,[(1,0x123),(2,0x456)])
        self.assertEqual(p.statuses.popleft().pressed,0x80000001)
        self.assertEqual((p.discarded,p.sequence_errors),(0,0))
        bad=bytearray(reply());bad[20]=ord('F') if bad[20]!=ord('F') else ord('0')
        p.feed(bad+reply())
        self.assertEqual(len(p.statuses),1)
        self.assertGreater(p.status_errors,0)

    def test_board_state_overrides_software_threshold_and_expires(self):
        m=KeyboardState(Profile([KeyCalibration(900,100)]*32))
        m.update(1,900,1)
        m.apply_board_state(decode_status(reply(pressed=1)),1)
        m.update(1,900,1.1)
        self.assertTrue(m.pressed[0])
        m.tick(1.7)
        self.assertFalse(m.pressed[0])

    def test_stop_wait_retry_same_packet_and_wrong_ack(self):
        sent=[];link=BoardLink(sent.append)
        link.start([dict(code=BEGIN),dict(code=COMMIT)],'test')
        link.tick(0);link.receive(decode_status(reply(seq=8)),.1)
        self.assertTrue(link.busy)
        link.tick(1.1)
        self.assertEqual(sent[0],sent[1])
        link.receive(decode_status(reply(seq=0)),1.2);link.tick(1.3)
        self.assertEqual(len(sent),3)
        link.receive(decode_status(reply(seq=1,result=4)),1.4)
        self.assertFalse(link.busy);self.assertEqual(link.failures,1)

    def test_timeout_never_reports_success(self):
        sent=[];link=BoardLink(sent.append)
        link.start([dict(code=QUERY)],'query')
        for t in (0,1.1,2.2,3.3):link.tick(t)
        self.assertEqual(len(sent),3);self.assertEqual(link.success_serial,0)
        self.assertFalse(link.busy)

    def test_reconnect_sequence_collision_uses_fresh_sequence(self):
        sent=[];link=BoardLink(sent.append)
        link.start([dict(code=QUERY)],'query');link.tick(0)
        link.receive(decode_status(reply(seq=0,result=7)),.1)
        self.assertEqual(len(sent),2)
        self.assertEqual(sent[1],command(1,QUERY))
        link.receive(decode_status(reply(seq=0)),.2)
        self.assertTrue(link.busy)
        link.receive(decode_status(reply(seq=1)),.3)
        self.assertEqual(link.success_serial,1)
        self.assertEqual(link.failures,0)

    def test_partial_calibration_is_not_transmitted(self):
        with self.assertRaises(ValueError):calibration_commands(Profile.empty())


if __name__=='__main__':unittest.main()
