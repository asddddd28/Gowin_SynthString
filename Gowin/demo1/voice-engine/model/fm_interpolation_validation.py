"""Independent integer boundaries for the registered FM interpolation product."""
import json
import random
from pathlib import Path

from voice_engine_model import operator
from voice_operator_model import packet, UNITY

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT.parent / 'voice-system/reports/fm-interpolation-pipeline'


def signed_width(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value >> (bits - 1) else value


def check_arithmetic():
    """Compare unbounded mathematical lerp with the exact registered widths."""
    rng = random.Random(0x494E5445)
    edges = [-2**31, -2**31+1, -UNITY, -1, 0, 1, UNITY, 2**31-2, 2**31-1]
    fractions = [0, 1, 2**21-1, 2**21, 2**22-2, 2**22-1]
    rows = [(a, b, f) for a in edges for b in edges for f in fractions]
    rows += [(rng.randrange(-2**31, 2**31), rng.randrange(-2**31, 2**31),
              rng.randrange(2**22)) for _ in range(100000)]
    for a, b, fraction in rows:
        reference = a + ((b-a)*fraction >> 22)
        delta = signed_width(b-a, 33)
        product_register = signed_width(delta*fraction, 56)
        registered = signed_width(a+(product_register >> 22), 32)
        assert registered == reference, (a, b, fraction)
    return len(rows)


def generate():
    checks = check_arithmetic()
    REPORT.mkdir(parents=True, exist_ok=True)
    edges = [-2**31, 2**31-1, -1, 1, -UNITY, UNITY, 0]
    low = [edges[n % len(edges)] for n in range(1024)]
    high = [edges[(n*3+1) % len(edges)] for n in range(1024)]
    # Make the wrapping neighbour discontinuous at both signed limits.
    low[1023], low[0] = -2**31, 2**31-1
    high[1023], high[0] = 2**31-1, -2**31
    (ROOT/'vectors/fm_interp_upload.txt').write_text(
        ''.join(f'{v & 0xffffffff:08x}\n' for v in low+high), encoding='ascii')
    rows = []
    for index in list(range(16))+[511, 512, 1022, 1023]:
        for fraction in [0, 1, 2**21-1, 2**21, 2**22-2, 2**22-1]:
            for morph in [0, 1, 32767, 32768, 65535, 65536, 65537, 0xffffffff]:
                phase = (index << 22) | fraction
                words = [phase, 0, 0, 0, UNITY, UNITY, 4,
                         UNITY, UNITY, UNITY, 0, 1, 1, 1, 1,
                         0, 0, 0, 1, 5, morph]
                rows.append((packet(*words), operator(words, (low, high))))
    (ROOT/'vectors/fm_interp_boundary.txt').write_text(
        ''.join(f'{p:0168x} {r:040x}\n' for p, r in rows), encoding='ascii')
    result = dict(arithmetic_checks=checks, boundary_vectors=len(rows),
                  uploaded_points=2048, signed_sample_bits=32, delta_bits=33,
                  product_bits=56, fraction_bits=22, pass_all=True)
    (REPORT/'semantic-model.json').write_text(
        json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    generate()
