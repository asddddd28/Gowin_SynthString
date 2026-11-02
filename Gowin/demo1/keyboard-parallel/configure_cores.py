"""Validate compile-time core counts and apply them to the board top only.

Run with --check to verify without changing RTL. Re-simulate and implement
after changing counts: arithmetic compatibility does not imply board fit.
"""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
PARAMETERS = dict(phase='C_PHASE_CORES', wave='C_WAVE_CORES',
                  envelope='C_ENV_CORES', modulation='C_MOD_CORES',
                  filter='C_FILTER_CORES', vca='C_VCA_CORES')

def read_counts():
    counts = json.loads((ROOT / 'core_counts.json').read_text(encoding='utf-8'))
    if set(counts) != set(PARAMETERS):
        raise ValueError('core_counts.json must contain exactly: ' + ', '.join(PARAMETERS))
    for key, value in counts.items():
        if type(value) is not int or not 1 <= value <= 4:
            raise ValueError(f'{key}: expected an integer from 1 through 4')
    return counts

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    counts = read_counts()
    path = ROOT / 'src/ParallelAxisTop.v'
    original = path.read_text(encoding='utf-8')
    candidate = original
    for key, parameter in PARAMETERS.items():
        candidate, found = re.subn(r'(parameter\s+' + parameter + r'\s*=\s*)[0-9]+',
                                  lambda match: match[1] + str(counts[key]), candidate)
        if found != 1:
            raise ValueError(f'Expected one declaration for {parameter}, got {found}')
    if candidate != original:
        if args.check:
            raise SystemExit('Core configuration differs from board top; run configure_cores.py, then validate and rebuild.')
        path.write_text(candidate, encoding='utf-8')
        print('Updated board top. Simulation and Gowin implementation must be repeated.')
    else:
        print('PASS board top matches core counts:', counts)
