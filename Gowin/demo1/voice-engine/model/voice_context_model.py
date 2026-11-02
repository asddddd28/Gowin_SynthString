"""驻留算子状态与重发语义：不以音符号或数值相等代替事务身份。"""
from pathlib import Path
import json
import random
from voice_operator_model import MASK, UNITY, packet
from voice_fabric_model import result_for


class ContextModel:
    """32 个上下文，各自仅保留最近一次执行，拒绝失序而不重复推进。"""

    def __init__(self):
        self.contexts = {}
        self.counts = dict(executed=0, replayed=0, rejected=0, bound=0)

    def fail(self, status):
        self.counts['rejected'] += 1
        return status << 64

    def apply(self, opcode, payload, context=0, generation=0, sequence=0):
        """返回 128 位完成值；传输 tag 透明，不参与幂等身份。"""
        if opcode < 5:
            self.counts['executed'] += 1
            return result_for(opcode, payload)
        if opcode not in (*range(0x80, 0x85), 0x90, 0x91):
            return self.fail(1)
        if context >= 32:
            return self.fail(3)
        old = self.contexts.get(context)
        if 0x80 <= opcode <= 0x84:
            core = opcode - 0x80
            if old and generation < old['generation']:
                return self.fail(4)
            if old and generation == old['generation']:
                if old['image'] != payload or old['core'] != core:
                    return self.fail(5)
                self.counts['replayed'] += 1
                return 1 << 72
            state = payload & MASK
            if core == 4:
                state |= payload & (7 << 32)
            self.contexts[context] = dict(generation=generation, core=core, image=payload,
                                          state=state, last=None, signature=0, result=0)
            self.counts['bound'] += 1
            return 0
        if old is None:
            return self.fail(3)
        if generation != old['generation']:
            return self.fail(4)
        if opcode == 0x91:
            if payload:
                return self.fail(8)
            return (old['state'] | (int(old['last'] is not None) << 73)
                    | (old['core'] << 76) | ((old['last'] or 0) << 80))
        if payload >> 66:
            return self.fail(8)
        if old['last'] is not None:
            if sequence == old['last']:
                if payload != old['signature']:
                    return self.fail(5)
                self.counts['replayed'] += 1
                return old['result'] | (1 << 72)
            if sequence < old['last']:
                return self.fail(6)
            if sequence != old['last'] + 1:
                return self.fail(7)
        elif sequence != 0:
            return self.fail(7)
        words = [(old['image'] >> (32 * n)) & MASK for n in range(10)]
        core = old['core']
        if core != 2:
            words[0] = old['state'] & MASK
        if core == 0:
            words[2] = payload & MASK
        elif core == 2:
            words[0], words[2] = payload & MASK, (payload >> 32) & MASK
        elif core == 4:
            words[1] = ((words[1] & ~31) | ((old['state'] >> 32) & 7)
                        | (((payload >> 64) & 3) << 3))
        result = result_for(core, packet(*words))
        if core != 2:
            old['state'] = result & (MASK | (7 << 32) if core == 4 else MASK)
        old.update(last=sequence, signature=payload, result=result)
        self.counts['executed'] += 1
        return result


def generate():
    """顺序参考定义状态语义；RTL 可让不同 raw 操作乱序返回。"""
    rng = random.Random(0x43545831)
    model = ContextModel()
    rows = []

    def emit(opcode, payload=0, context=0, generation=0, sequence=0):
        response = model.apply(opcode, payload, context, generation, sequence)
        data = payload | ((generation << 8 | context) << 320) | (sequence << 352)
        rows.append((opcode, 1, data, True, response))

    # 连续 raw 流必须保持原共享核心的并发接纳。
    for n in range(160):
        emit(n % 5, rng.getrandbits(128) if n % 5 != 4 else 0)
    emit(0x90, context=0)
    emit(0x80, context=32)
    emit(0x90, context=255)
    images = []
    for context in range(32):
        core = context % 5
        image = packet(0, 0x01000000, 0, 0x08000000)
        if core == 1:
            image = packet(0, UNITY, UNITY // 17)
        elif core == 2:
            image = packet(0, UNITY // 2, 0, UNITY // 4)
        elif core == 3:
            image = packet(context + 1)
        elif core == 4:
            image = packet(0, 32, UNITY, UNITY // 2, UNITY // 3, 0,
                           UNITY // 7, UNITY // 13, UNITY // 19, UNITY // 11)
        images.append(image)
        emit(0x80 + core, image, context, 10)
    for sample in range(64):
        for context in range(32):
            live = packet(rng.randrange(UNITY), rng.randrange(UNITY),
                          1 if sample in (0, 21) else 2 if sample == 40 else 0)
            emit(0x90, live, context, 10, sample)
            if sample % 9 == 0:
                emit(0x90, live, context, 10, sample)  # 相同序号，只有 tag 会不同。
                emit(0x90, live ^ 1, context, 10, sample)
            if sample % 17 == 0:
                emit(0x80 + context % 5, images[context], context, 10)
                emit(0x91, 0, context, 10)
            if sample % 23 == 0:
                emit(0x90, live, context, 10, sample + 2)
            if sample > 0 and sample % 19 == 0:
                emit(0x90, live, context, 10, sample - 1)
    for context in range(32):
        core = context % 5
        emit(0x80 + core, images[context] ^ 1, context, 10)
        emit(0x80 + (core + 1) % 5, images[context], context, 10)
        emit(0x90, 1 << 66, context, 10, 64)
        emit(0x80 + core, images[context], context, 11)
        emit(0x90, 0, context, 10, 64)  # 延迟的旧代号不能改变新实例。
        emit(0x80 + core, images[context], context, 9)
        emit(0x90, 0, context, 11, 1)
        emit(0x90, 0, context, 11, 0)
        emit(0x91, 0, context, 11)
        emit(0x91, 1, context, 11)
    emit(0x80, packet(0xffffffff, 2, 0, 0), 0, 0xffffff)
    emit(0x90, 0, 0, 0xffffff, 0)
    emit(0x90, 0, 0, 0xffffff, 0xffffffff)  # 大跨度不能绕过连续序号检查。
    emit(0x80, 0, 0, 0)
    # 错误多拍包只返回一次错误，尾部即使看似 BIND 也不能执行。
    for n in range(12):
        rows.append((0x80, 0, 0, True, model.fail(2)))
        rows.append((0x80, 0, 0, False, 0))
        rows.append((0x80, 1, 0, False, 0))
        emit(0x91, 0, 0, 0xffffff)
        emit(0xfe)
    root = Path(__file__).resolve().parents[1] / 'vectors'
    root.mkdir(exist_ok=True)
    lines = [f'{op:02x} {last:x} {0xc0000000 | n:08x} {data:096x} {int(valid):x} {result:032x}'
             for n, (op, last, data, valid, result) in enumerate(rows)]
    (root / 'voice_context.txt').write_text('\n'.join(lines) + '\n', encoding='ascii')
    manifest = dict(beats=len(rows), responses=sum(r[3] for r in rows), counts=model.counts)
    (root / 'context_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(manifest))


if __name__ == '__main__':
    generate()
