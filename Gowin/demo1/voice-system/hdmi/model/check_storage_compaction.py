"""验证显示 ROM 可达地址、I2C 查表语义以及完整画面均未改变。"""
from pathlib import Path
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / 'reports/resource-preserving'
BASE = REPORT / 'baseline'


def words(path):
    return [int(word, 16) for word in path.read_text(encoding='utf-8').split()]


def check_assets():
    """枚举包括未使用页在内的全部行指针，证明被删除区域不可达。"""
    assets = ROOT / 'hdmi/assets'
    old = words(BASE / 'assets/cells.hex')
    new = words(assets / 'cells.hex')
    rows = words(assets / 'rows.hex')
    assert len(old) == 16384 and len(new) == 11264
    assert new == old[:len(new)]
    banks = [words(assets / f'cells_{name}.hex') for name in ('main','middle','tail')]
    assert list(map(len, banks)) == [8192, 2048, 1024]
    assert sum(banks, []) == new
    assert all(value == 0 for value in old[len(new):])
    for row in rows:
        for column in range(128):
            address = row * 128 + column
            assert address < len(new) and new[address] == old[address]
            bank = 0 if not row & 64 else (2 if row & 16 else 1)
            bank_address = (row & (63, 15, 7)[bank]) * 128 + column
            assert banks[bank][bank_address] == old[address]
    for source in (BASE / 'assets').glob('*.hex'):
        if source.name != 'cells.hex':
            assert source.read_bytes() == (assets / source.name).read_bytes(), source.name
    # The MPR change is solely a synthesis placement attribute. No executable
    # token, configuration byte, state transition or sample cadence may change.
    mpr = ROOT.parents[1] / 'demo_test/diagnostics/touchpad_guitar/src/MprScanner.v'
    def tokens(path):
        text = path.read_text(encoding='utf-8')
        text = re.sub(r'//[^\n]*|/\*.*?\*/|\(\*.*?\*\)', '', text, flags=re.S)
        return re.findall(r"[A-Za-z_][\w$]*|\d+'[sS]?[hHdDbBoO][\da-fA-F_xXzZ?]+|\d+|\S", text)
    assert tokens(BASE / 'MprScanner.v') == tokens(mpr)
    result = dict(old_cells=len(old), new_cells=len(new), reachable_max=max(rows)*128+127,
                  checked_addresses=len(rows)*128, mpr_executable_tokens_identical=True)
    (REPORT / 'storage-equivalence.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('PASS storage equivalence:', result)


def check_frames():
    """比较真实 RTL 输出的七幅 RGB 图，不使用人工近似的图像模型。"""
    result = {}
    for source in (BASE / 'frames').glob('*.ppm'):
        candidate = REPORT / 'display-sim' / source.name
        assert source.read_bytes() == candidate.read_bytes(), source.name
        result[source.name] = hashlib.sha256(candidate.read_bytes()).hexdigest()
    assert len(result) == 7
    (REPORT / 'pixel-equivalence.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('PASS seven frames: all 6,451,200 RGB pixels byte-identical')


if __name__ == '__main__':
    check_assets()
    if '--frames' in sys.argv:
        check_frames()
