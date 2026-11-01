"""综合固件能力声明，只有CRC正确且版本受支持才启用多模块通信。"""
from dataclasses import dataclass
import re
from touchpad_core import crc8

FRAME_SIZE=15
FRAME=re.compile(rb'H1([0-9A-F]{4})([0-9A-F]{4})\*([0-9A-F]{2})\r\n')

@dataclass(frozen=True)
class HardwareIdentity:
    capabilities:int
    build:int

def decode_hardware(packet):
    match=FRAME.fullmatch(packet)
    if not match or crc8(packet[:10])!=int(match[3],16):
        raise ValueError('综合固件能力帧CRC或格式错误')
    value=HardwareIdentity(int(match[1],16),int(match[2],16))
    if value.capabilities!=0x7f or value.build>>8!=1:
        raise ValueError('综合固件能力或版本尚不支持')
    return value
