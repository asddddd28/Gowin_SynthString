"""Exercise every supported pool count, then the complete board pin-level path."""
from pathlib import Path
import json, subprocess, sys

ROOT = Path(__file__).resolve().parent
template = (ROOT / 'sim/tb_parallel_equivalence.v').read_text(encoding='utf-8')
for count in (1, 2, 3, 4):
    name = f'parallel_cores_{count}'
    bench = template.replace('tb_parallel_equivalence', 'tb_' + name)
    bench = bench.replace('C_PHASE=1,C_WAVE=2,C_ENV=3,C_MOD=1,C_FILTER=1,C_VCA=1',
                          ','.join(f'C_{kind}={count}' for kind in ('PHASE', 'WAVE', 'ENV', 'MOD', 'FILTER', 'VCA')))
    (ROOT / 'sim' / f'tb_{name}.v').write_text(bench, encoding='utf-8')
    subprocess.run([sys.executable, str(ROOT / 'run_test.py'), name], check=True, cwd=ROOT)

source = ROOT.parent / 'keyboard-studio'
bench = (source / 'sim/tb_keyboard_audio.v').read_text(encoding='utf-8')
bench = bench.replace('tb_keyboard_audio', 'tb_parallel_keyboard_audio').replace('KeyboardAxisTop #', 'ParallelAxisTop #')
(ROOT / 'sim/tb_parallel_keyboard_audio.v').write_text(bench, encoding='utf-8')
(ROOT / 'studio_packets.hex').write_bytes((source / 'studio_packets.hex').read_bytes())
subprocess.run([sys.executable, str(ROOT / 'run_test.py'), 'parallel_keyboard_audio'], check=True, cwd=ROOT)
