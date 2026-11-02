"""四段包络与内部任务路由的独立语义，参数映射不冒充 DX7 曲线。"""
from pathlib import Path
import json
import random
from voice_operator_model import MASK, UNITY, signed, packet, phase_pm, envelope_segment, gain_mix, noise_step

def multi_envelope(raw):
    """每次任务最多推进一个包络阶段；参数与状态是原子快照。"""
    words = [(raw >> (32 * n)) & MASK for n in range(10)]
    level, control = words[:2]
    stage, event, restart = control & 7, (control >> 3) & 3, (control >> 5) & 1
    levels, steps = words[2:6], words[6:10]
    bad = stage > 5
    if event == 1:
        stage, bad = 1, False
        if restart:
            level = levels[3]
    elif event == 3:
        stage, level, bad = 0, levels[3], False
    elif bad:
        stage = 0
    elif event == 2 and stage != 0:
        stage = 5
    moving = stage in (1, 2, 3, 5)
    reached = stalled = False
    if moving:
        index = 3 if stage == 5 else stage - 1
        result = envelope_segment(packet(level, levels[index], steps[index]))
        level, reached, stalled = result & MASK, bool((result >> 32) & 1), bool((result >> 33) & 1)
        if reached:
            stage = 0 if stage == 5 else stage + 1
    return level | (stage << 32) | (int(stage != 0) << 35) | (int(reached) << 36) | (int(stalled) << 37) | (int(bad) << 38)

OPERATIONS = [phase_pm, envelope_segment, gain_mix, noise_step, multi_envelope]

def result_for(destination, payload):
    """返回低64位数值与高位总线任务状态。"""
    return OPERATIONS[destination](payload) if destination < 5 else 1 << 64

def generate():
    """固定种子生成算子事件覆盖及混合任务参考。"""
    root = Path(__file__).resolve().parents[1] / "vectors"
    root.mkdir(exist_ok=True)
    rng = random.Random(0x41584934)
    rows = []
    levels = [UNITY, UNITY // 2, UNITY // 3, 0]
    steps = [UNITY // 17, UNITY // 31, UNITY // 7, UNITY // 41]
    for stage in range(8):
        for event in range(4):
            for restart in range(2):
                for level in [0, 1, UNITY, MASK, 0x80000000, 0x7fffffff]:
                    rows.append(packet(level, stage | event << 3 | restart << 5, *levels, *steps))
    for _ in range(2400):
        rows.append(rng.getrandbits(320))
    for voice in range(24):
        value, stage = 0, 0
        for frame in range(192):
            event = 1 if frame in (0, 52) else 2 if frame == 120 else 0
            raw = packet(value, stage | event << 3 | (voice & 1) << 5, *levels, *steps)
            rows.append(raw)
            result = multi_envelope(raw)
            value, stage = result & MASK, (result >> 32) & 7
    (root / "AxisEnvelopeMulti.txt").write_text("".join(f"{raw:080x} {multi_envelope(raw):016x}\n" for raw in rows), encoding="ascii")
    requests = []
    for index in range(1800):
        dest = index % 5 if index < 100 else rng.choice([0,1,2,3,4,0xfe])
        payload = rows[index % len(rows)] if dest == 4 else rng.getrandbits(128)
        if index % 137 == 0:
            requests.append((dest, 0, payload, True, 2 << 64))
            requests.append((dest, 0, rng.getrandbits(320), False, 0))
            requests.append((dest, 1, rng.getrandbits(320), False, 0))
        else:
            requests.append((dest, 1, payload, True, result_for(dest, payload)))
    lines = [f"{dest:02x} {last:x} {index:08x} {payload:080x} {int(expect):x} {result:032x}" for index,(dest,last,payload,expect,result) in enumerate(requests)]
    (root / "voice_fabric.txt").write_text("\n".join(lines)+"\n",encoding="ascii")
    manifest={"envelope_transactions":len(rows),"fabric_beats":len(lines),"fabric_responses":sum(int(r[3]) for r in requests)}
    (root / "fabric_manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(manifest))

if __name__ == "__main__":
    assert multi_envelope(packet(0, 1 << 3, UNITY, 0, 0, 0, UNITY, 1, 1, 1)) & MASK == UNITY
    generate()

