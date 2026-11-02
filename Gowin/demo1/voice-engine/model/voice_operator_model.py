"""Voice Engine 基础算子的整数语义；与 RTL 无关的宽整数参考。"""
from pathlib import Path
import json
import random

MASK = (1 << 32) - 1
UNITY = 1 << 26

def signed(word):
    """将输入字解释为二进制补码整数。"""
    return (word & MASK) - (1 << 32) if word & (1 << 31) else word & MASK

def phase_pm(packet):
    """低字反馈无调制相位，高字用于本次查表，PM 不进入积分状态。"""
    phase, step, modulation, depth = [(packet >> (32 * n)) & MASK for n in range(4)]
    accumulator = (phase + step) & MASK
    offset = (signed(modulation) * signed(depth)) // UNITY
    return accumulator | (((accumulator + offset) & MASK) << 32)

def envelope_segment(packet):
    """有符号目标逼近；正步长是绝对幅度，零步长报告停滞。"""
    level = signed(packet)
    target = signed(packet >> 32)
    step = (packet >> 64) & MASK
    distance = target - level
    reached = abs(distance) <= step
    stalled = step == 0 and distance != 0
    advanced = target if reached else level + (step if distance > 0 else -step)
    return (advanced & MASK) | (int(reached) << 32) | (int(stalled) << 33)

def gain_mix(packet):
    """两个 Q26 乘积先全精度相加，再负向取整、饱和到有符号 32 位。"""
    source, gain, other, other_gain = [signed(packet >> (32 * n)) for n in range(4)]
    scaled = (source * gain + other * other_gain) // UNITY
    clipped = min(max(scaled, -(1 << 31)), (1 << 31) - 1)
    return (clipped & MASK) | (int(clipped != scaled) << 32)

def noise_step(packet):
    """显式传入与返回伪随机状态；零种子映射为一。"""
    state = (packet & MASK) or 1
    state ^= (state << 13) & MASK
    state ^= state >> 17
    state ^= (state << 5) & MASK
    sample = signed(state) // 32
    return state | ((sample & MASK) << 32)

OPERATORS = {
    "AxisPhasePm": phase_pm,
    "AxisEnvelopeSegment": envelope_segment,
    "AxisGainMix": gain_mix,
    "AxisNoiseStep": noise_step,
}

def packet(*words):
    """按低字优先的固定操作数布局打包。"""
    return sum((word & MASK) << (32 * n) for n, word in enumerate(words))

def write_vectors(destination):
    """生成边界用例、重复状态序列和固定种子随机事务。"""
    destination.mkdir(parents=True, exist_ok=True)
    rng = random.Random(0x564F4943)
    boundaries = [0, 1, MASK, 0x80000000, 0x7FFFFFFF, UNITY, -UNITY, UNITY - 1]
    vectors = {name: [] for name in OPERATORS}
    for first in boundaries:
        for second in boundaries:
            vectors["AxisPhasePm"].append(packet(first, second, -UNITY, 0x7FFFFFFF))
            vectors["AxisEnvelopeSegment"].append(packet(first, second, 0))
            vectors["AxisEnvelopeSegment"].append(packet(first, second, MASK))
            vectors["AxisGainMix"].append(packet(first, second, first, second))
            vectors["AxisNoiseStep"].append(packet(first))
    vectors["AxisGainMix"].extend([
        packet(0x7FFFFFFF, UNITY, 1, UNITY - 1),
        packet(0x7FFFFFFF, UNITY, 1, UNITY),
        packet(0x80000000, UNITY, -1, 1),
        packet(0x80000000, UNITY, 1, UNITY - 1),
        packet(0x80000000, 0x80000000, 0x80000000, 0x80000000),
    ])
    for name in OPERATORS:
        for _ in range(1500):
            vectors[name].append(rng.getrandbits(128))
    phase, noise, envelope = 0, 0, 0
    for index in range(512):
        p = packet(phase, 0x1020304, (index - 256) * 10000, 0x70000000)
        vectors["AxisPhasePm"].append(p)
        phase = phase_pm(p) & MASK
        vectors["AxisNoiseStep"].append(packet(noise))
        noise = noise_step(packet(noise)) & MASK
        target = UNITY if index < 256 else 0
        e = packet(envelope, target, UNITY // 127)
        vectors["AxisEnvelopeSegment"].append(e)
        envelope = envelope_segment(e) & MASK
    report = {}
    for name, packets in vectors.items():
        lines = [f"{p:032x} {OPERATORS[name](p):016x}" for p in packets]
        (destination / f"{name}.txt").write_text("\n".join(lines) + "\n", encoding="ascii")
        report[name] = len(lines)
    (destination / "manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report

if __name__ == "__main__":
    assert phase_pm(packet(0, 1, UNITY, 100)) == (101 << 32) | 1
    assert envelope_segment(packet(-10, 10, 25)) == (1 << 32) | 10
    assert gain_mix(packet(UNITY, UNITY, -UNITY, UNITY)) == 0
    assert noise_step(0) == noise_step(1)
    print(json.dumps(write_vectors(Path(__file__).resolve().parents[1] / "vectors")))

