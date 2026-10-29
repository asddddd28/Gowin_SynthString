import argparse
import json
import tempfile
import time
import tkinter as tk
import unittest
from pathlib import Path
from board_protocol import GameStatus, decode_game_status, crc8, BoardStatus, BoardLink, GAME_START, GAME_STOP
from keyboard_core import StreamParser
from app import KeyboardApp

def wire(game=1,phase=2,seconds=8,reason=0,score=123,misses=4,epoch=7,pixels=0xE4):
    raw=bytes((game,phase,seconds,reason))+score.to_bytes(2,'big')+bytes((misses,epoch))+pixels.to_bytes(8,'big')
    return b'#'+raw.hex().upper().encode()+f'*{crc8(raw):02X}\n'.encode()

class GameProtocolTests(unittest.TestCase):
    def test_decode_pixel_order_and_fields(self):
        status=decode_game_status(wire())
        self.assertEqual(status.score,123);self.assertEqual(status.colors[:4],(0,1,2,3))
        self.assertEqual(status.epoch,7)

    def test_mixed_stream_fragmentation_and_crc(self):
        data=b'K01:ABC\r\n'+wire()+b'K02:123\r\n'
        for split in range(len(data)+1):
            parser=StreamParser();samples=parser.feed(data[:split])+parser.feed(data[split:])
            self.assertEqual(samples,[(1,0xABC),(2,0x123)])
            self.assertEqual(parser.game_statuses.popleft().score,123)
            self.assertEqual(parser.game_errors,0)
        parser=StreamParser();bad=bytearray(wire());bad[34]=ord('Z')
        parser.feed(bad+wire());self.assertGreater(parser.game_errors,0)
        self.assertEqual(len(parser.game_statuses),1)

    def test_invalid_state_rejected(self):
        for fields in (dict(game=4),dict(phase=5),dict(reason=7)):
            with self.assertRaises(ValueError):decode_game_status(wire(**fields))


class GameAppTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory();self.root=tk.Tk();self.root.attributes('-alpha',0)
        args=argparse.Namespace(state_dir=Path(self.folder.name),profile=None,port=None,replay=None,diagnostics=None,quit_after=None)
        self.app=KeyboardApp(self.root,args);self.root.update()
        self.sent=[];self.app.board=BoardLink(self.sent.append);self.app.input_kind='live';self.app.input_ready=True
        self.app.board.supported=True;self.app.board.updated=time.monotonic()
        self.app.board.last_status=BoardStatus(1,0,True,2,0,1,0)

    def tearDown(self):
        self.app.close();self.folder.cleanup()

    def test_reconnect_preserves_ongoing_fpga_game(self):
        self.app.board.last_status=BoardStatus(1,0,True,5,0,9,0)
        self.app.auto_sync_pending=True;self.app.poll_board(time.monotonic())
        self.assertFalse(self.app.auto_sync_pending);self.assertFalse(self.app.need_sync)
        self.assertFalse(self.app.board.busy);self.assertEqual(self.sent,[])

    def test_game_controls_send_only_commands_no_engine(self):
        self.app.game_status=decode_game_status(wire());self.app.game_updated=time.monotonic()
        self.app.start_game(2)
        self.assertEqual(self.app.board.queue[0],dict(code=GAME_START,key=2))
        self.app.board.queue.clear();self.app.board.last_status=BoardStatus(1,0,True,5,0,1,0)
        self.app.stop_game()
        self.assertEqual(self.app.board.queue[0]['code'],GAME_STOP)

    def test_dashboard_uses_fpga_score_and_timeout_state(self):
        panel=self.app.games_page
        panel.refresh(decode_game_status(wire(game=2,phase=3,score=987,seconds=0)),True,True,True)
        self.assertEqual(panel.score.cget('text'),'得分 987')
        self.assertIn('结算',panel.message.cget('text'))
        panel.refresh(decode_game_status(wire()),False,False,False)
        self.assertIn('最后收到',panel.message.cget('text'))
        self.assertEqual(len(self.app.notebook.tabs()),2)

if __name__=='__main__':unittest.main()
