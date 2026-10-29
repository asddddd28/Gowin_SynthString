"""Checked ASCII command protocol and stop-and-wait FPGA configuration transfer."""
from collections import deque
from dataclasses import dataclass

BEGIN, KEY, COMMIT, EFFECT, QUERY = 0x10, 0x11, 0x12, 0x20, 0x30
GAME_START, GAME_STOP = 0x41, 0x42


def crc8(data):
    value = 0
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = ((value << 1) ^ (7 if value & 128 else 0)) & 255
    return value


def command(seq, code, key=0, rest=0, bottom=0, press=0, release=0, mode=0, direction=0):
    fields = ((seq, 8), (code, 8), (key, 8), (rest, 12), (bottom, 12),
              (press, 12), (release, 12), (mode, 4), (direction, 4))
    packed = 0
    for value, width in fields:
        if type(value) is not int or not 0 <= value < (1 << width):
            raise ValueError('协议字段超出范围')
        packed = (packed << width) | value
    raw = packed.to_bytes(10, 'big')
    return b'!' + raw.hex().upper().encode() + f'*{crc8(raw):02X}\n'.encode()


@dataclass(frozen=True)
class BoardStatus:
    seq: int
    result: int
    configured: bool
    mode: int
    direction: int
    generation: int
    pressed: int


def decode_status(line):
    if len(line) != 23 or line[:1] != b'@' or line[19:20] != b'*' or line[-1:] != b'\n':
        raise ValueError('板卡应答格式不正确')
    if any(c not in b'0123456789ABCDEF' for c in line[1:19] + line[20:22]):
        raise ValueError('板卡应答不是大写十六进制')
    raw = bytes.fromhex(line[1:19].decode())
    if crc8(raw) != int(line[20:22], 16):
        raise ValueError('板卡应答CRC错误')
    if raw[2] not in (0, 1) or raw[3] >> 4 > 5 or raw[3] & 15 > 1:
        raise ValueError('板卡应答状态超出范围')
    return BoardStatus(raw[0], raw[1], bool(raw[2]), raw[3] >> 4, raw[3] & 15, raw[4], int.from_bytes(raw[5:], 'big'))


@dataclass(frozen=True)
class GameStatus:
    game: int
    phase: int
    seconds: int
    reason: int
    score: int
    misses: int
    epoch: int
    pixels: int

    @property
    def colors(self):
        return tuple((self.pixels >> (2*key)) & 3 for key in range(32))


def decode_game_status(line):
    if len(line) != 37 or line[:1] != b'#' or line[33:34] != b'*' or line[-1:] != b'\n':
        raise ValueError('游戏状态格式错误')
    if any(c not in b'0123456789ABCDEF' for c in line[1:33]+line[34:36]):
        raise ValueError('游戏状态不是大写十六进制')
    raw = bytes.fromhex(line[1:33].decode())
    if crc8(raw) != int(line[34:36],16):
        raise ValueError('游戏状态CRC错误')
    if raw[0]>3 or raw[1]>4 or raw[3]>6:
        raise ValueError('游戏状态值无效')
    return GameStatus(raw[0],raw[1],raw[2],raw[3],int.from_bytes(raw[4:6],'big'),raw[6],raw[7],int.from_bytes(raw[8:],'big'))


def calibration_commands(profile):
    profile.validate()
    if any(cal is None for cal in profile.keys):
        raise ValueError('下发前需要完成全部32键校准')
    result = [dict(code=BEGIN)]
    for index, cal in enumerate(profile.keys):
        rest, bottom = round(cal.rest), round(cal.bottom)
        press = round(rest + (bottom-rest)*profile.press_threshold)
        release = round(rest + (bottom-rest)*profile.release_threshold)
        if abs(bottom-rest) < 100 or press == release:
            raise ValueError(f'K{index+1:02d} 的整数阈值不能区分触发和释放')
        result.append(dict(code=KEY, key=index, rest=rest, bottom=bottom, press=press, release=release))
    result.append(dict(code=COMMIT))
    return result


class BoardLink:
    """One outstanding command; CRC-valid matching ACK is the only success signal."""
    def __init__(self, send):
        self.send = send
        self.seq = 0
        self.queue = deque()
        self.pending = None
        self.last_status = None
        self.updated = float('-inf')
        self.supported = False
        self.message = '等待板卡协议确认'
        self.completed = self.total = self.failures = 0
        self.success_serial = 0
        self.operation = ''

    @property
    def busy(self):
        return self.pending is not None or bool(self.queue)

    def start(self, commands, label):
        if self.busy:
            raise ValueError('正在等待板卡确认，请稍候')
        self.queue.extend(commands)
        self.completed, self.total = 0, len(commands)
        self.operation = label
        self.message = label + ' · 准备发送'

    def receive(self, status, now):
        self.last_status, self.updated, self.supported = status, now, True
        if status.result == 0x80 or self.pending is None or status.seq != self.pending['seq']:
            return
        if status.result == 7 and self.pending['collisions'] < 2:
            # A newly opened App may reuse the previous session's last sequence.
            # The FPGA explicitly rejected it, so retry with a fresh sequence.
            seq = self.seq
            self.seq = (self.seq + 1) % 255
            self.pending.update(seq=seq, packet=command(seq, **self.pending['fields']),
                                sent=now, tries=1, collisions=self.pending['collisions'] + 1)
            self.send(self.pending['packet'])
            return
        if status.result:
            errors = {1:'CRC错误',2:'没有暂存事务',3:'范围或阈值无效',4:'32键配置不完整',6:'命令不支持',7:'序号冲突'}
            self.failures += 1
            self.message = '板卡拒绝：' + errors.get(status.result, f'错误{status.result}')
            self.queue.clear(); self.pending = None
            return
        self.completed += 1
        self.pending = None
        self.message = f'{self.operation} · 已确认 {self.completed}/{self.total}'
        if not self.queue:
            self.success_serial += 1

    def tick(self, now):
        if self.pending:
            if now - self.pending['sent'] < 1.0:
                return
            if self.pending['tries'] >= 3:
                self.message = '板卡确认超时；未确认下发成功，请检查固件与连接'
                self.pending = None; self.queue.clear(); self.failures += 1
                return
            self.pending['tries'] += 1
            self.pending['sent'] = now
            self.send(self.pending['packet'])
        elif self.queue:
            fields = self.queue.popleft()
            seq = self.seq
            self.seq = (self.seq + 1) % 255
            packet = command(seq, **fields)
            self.pending = dict(seq=seq, packet=packet, sent=now, tries=1, fields=fields, collisions=0)
            self.send(packet)
