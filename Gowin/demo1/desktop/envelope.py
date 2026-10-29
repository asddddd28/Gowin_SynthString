"""逐键包络的紧凑分数步长编码；保持十八个参数字的传输长度。"""
import math

FULL_LEVEL = 262143
FRACTION_BITS = 14
FULL_STATE = FULL_LEVEL << FRACTION_BITS
PRECISE_ENVELOPE = 0x8000


def encode_step(distance, milliseconds, sample_rate):
    """把幅度距离/时间换成十一位尾数、五位指数的无符号步长。"""
    if milliseconds == 0 or distance == 0:
        return 0
    raw = max(1, round((distance << FRACTION_BITS) * 1000 / (milliseconds * sample_rate)))
    raw = min(FULL_STATE, raw)
    exponent = max(0, raw.bit_length() - 11)
    mantissa = (raw + (1 << (exponent - 1))) >> exponent if exponent else raw
    if mantissa == 2048:
        exponent += 1
        mantissa = 1024
    return (exponent << 11) | mantissa


def decode_step(word):
    """还原 Q18.14 步长；拒绝会溢出或含有零尾数的非零编码。"""
    if type(word) is not int or not 0 <= word <= 65535:
        raise ValueError('包络编码必须是十六位无符号整数。')
    exponent, mantissa = word >> 11, word & 2047
    if exponent > 22 or (word != 0 and mantissa == 0):
        raise ValueError('包络指数或尾数不合法。')
    return min(FULL_STATE, mantissa << exponent)


def duration_samples(distance, word):
    """计算一段包络实际占用的采样数，包括零时间的一次状态转换。"""
    step = decode_step(word)
    return 1 if step == 0 else math.ceil((distance << FRACTION_BITS) / step)
