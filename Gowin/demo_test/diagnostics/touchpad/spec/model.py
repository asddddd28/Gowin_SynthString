"""双 MPR121 的寄存器配置及串口参考模型；独立于 RTL。"""
CONFIG = [(0x80, 0x63), (0x5e, 0)]
CONFIG += list(zip(range(0x2b, 0x36), [1, 1, 14, 0, 1, 5, 1, 0, 0, 0, 0]))
CONFIG += [(r, 12 if r % 2 else 6) for r in range(0x41, 0x59)]
CONFIG += [(0x5b, 0), (0x5c, 0x10), (0x5d, 0x24),
           (0x7b, 0x00), (0x7c, 0x00), (0x7d, 201), (0x7e, 131), (0x7f, 181), (0x5e, 0x8c)]

def crc8(data):
    value = 0
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = ((value << 1) ^ (7 if value & 128 else 0)) & 255
    return value

def packet(board, sequence, address, error, lines, raw):
    assert len(raw) == 42
    body = f'T{board}{sequence:04X}{address:02X}{error:02X}{lines:X}'.encode() + raw.hex().upper().encode()
    return body + f'*{crc8(body):02X}\r\n'.encode()

if __name__ == '__main__':
    assert len(CONFIG) == 46
    assert len(packet(1, 0, 0x5a, 0, 7, bytes(42))) == 100
    assert crc8(b'123456789') == 0xf4
    print('PASS configuration 46 writes; packet 100 bytes; CRC-8 standard vector')
