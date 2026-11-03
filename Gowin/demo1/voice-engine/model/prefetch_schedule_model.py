"""用抽象同步RAM验证单槽预取的行归属、在途标记和禁用算子跳转。"""

import json
from pathlib import Path
import random


def run_case(enabled, carriers, rng):
    """随机执行器等待期间预读下一行，独立比对顺序与完成的归属。"""
    operator = 0
    row = 0
    state = 1
    carrier = False
    packet = None
    in_flight = None
    remaining = 0
    issued = []
    retired = []
    cycles = 0
    while state != 5:
        next_row = min(operator + 1, 5) if state in (1, 2, 3) else operator
        if state == 1:
            assert row == operator, (state, row, operator)
            if enabled & (1 << operator):
                packet = (operator, row)
                carrier = bool(carriers & (1 << row))
                state = 2
            elif operator == 5:
                state = 5
            else:
                operator += 1
        elif state == 2:
            assert packet == (operator, operator)
            if rng.randrange(4):
                assert in_flight is None
                in_flight = packet
                issued.append(packet)
                remaining = rng.randrange(1, 21)
                state = 3
        elif state == 3:
            remaining -= 1
            if remaining == 0:
                assert in_flight[0] == operator
                assert carrier == bool(carriers & (1 << operator))
                retired.append((in_flight[0], carrier))
                in_flight = None
                if operator == 5:
                    state = 5
                else:
                    operator += 1
                    state = 1
        row = next_row
        cycles += 1
        assert cycles < 1000
    expected = [index for index in range(6) if enabled & (1 << index)]
    assert issued == [(index, index) for index in expected]
    assert retired == [(index, bool(carriers & (1 << index))) for index in expected]
    return len(issued)


def main():
    """遍历全部启用/载波组合，多次随机化就绪与完成延迟。"""
    rng = random.Random(0x50524546)
    cases = transactions = 0
    for _ in range(8):
        for enabled in range(64):
            for carriers in range(64):
                transactions += run_case(enabled, carriers, rng)
                cases += 1
    result = {"status": "PASS", "cases": cases, "transactions": transactions,
              "enabled_masks": 64, "carrier_masks": 64,
              "predicted_full_voice_cycles": 874 - 8 * (5 * 2 + 1),
              "predicted_full_chain_cycles": 948 - 88,
              "scope": "abstract synchronous RAM and ownership; numeric oracle remains voice_engine_model.py"}
    destination = Path(__file__).resolve().parents[1] / "reports/prefetch-schedule-model.json"
    destination.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"PASS prefetch_schedule cases={cases} transactions={transactions}")


if __name__ == "__main__":
    main()
