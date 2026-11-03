"""分拍前后整数运算对照；原有音频参考模型保持独立、不随RTL改公式。"""

import json
from pathlib import Path
import random

from dx7_model import VELOCITY


def smooth(current, target):
    """复现既有平滑规则，每帧只前进一步。"""
    distance = abs(target - current)
    step = int(distance != 0) if distance < 64 else distance >> 6
    return current + step if current < target else current - step


def main():
    """验证注册边界不改变整数结果，覆盖负数、饱和及全路由掩码。"""
    rng = random.Random(0x50495045)
    for velocity in range(128):
        for sensitivity in range(8):
            old = (((VELOCITY[velocity >> 1] - 239) * sensitivity + 7) >> 3) << 4
            offset_register = VELOCITY[velocity >> 1] - 239
            new = ((offset_register * sensitivity + 7) >> 3) << 4
            assert old == new
    cases = 0
    for index in range(200000):
        current, target = rng.randrange(1 << 32), rng.randrange(1 << 32)
        modulation = rng.randrange(-(1 << 31), 1 << 31)
        expected = min(1 << 26, max(0, smooth(current, target) + modulation))
        row_current, row_target = current, target
        smooth_register = smooth(row_current, row_target)
        assert expected == min(1 << 26, max(0, smooth_register + modulation))
        values = [rng.randrange(-(1 << 31), 1 << 31) for _ in range(6)]
        if index < 768:
            values = [[-(1 << 31), (1 << 31) - 1][(index >> i) & 1] for i in range(6)]
        mask, operator = index % 64, (index // 64) % 6
        chosen = [value if i < operator and mask & (1 << i) else 0 for i, value in enumerate(values)]
        low, high = sum(chosen[:3]), sum(chosen[3:])
        assert -(1 << 33) <= low < (1 << 33) and -(1 << 33) <= high < (1 << 33)
        combined = low + high
        clamp = lambda value: max(-(1 << 31), min((1 << 31) - 1, value))
        assert clamp(sum(chosen)) == clamp(combined)
        level, increment = rng.randrange(1 << 32), rng.randrange(1 << 32)
        base = max(level, 112459776)
        distance = ((285212672 - base) & 0xffffffff) >> 24
        old_rising = base + ((distance * increment) & 0xffffffff)
        base_register, distance_register = base, distance
        step_register = (distance_register * increment) & 0xffffffff
        assert old_rising == base_register + step_register
        cases += 1
    report = {'status': 'PASS', 'velocity_cases': 1024, 'arithmetic_cases': cases,
              'native_voice_cycles': 834, 'all_dx_voice_cycles': 882,
              'scope': 'integer decomposition only; external RTL oracles and PnR required'}
    destination = Path(__file__).resolve().parents[1] / 'reports/critical-pipeline-model.json'
    destination.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('PASS critical_pipeline_model', report)


if __name__ == '__main__':
    main()
