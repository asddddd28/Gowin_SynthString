"""Qualify four more factory patches with the unchanged whole-engine RTL oracle.

All vectors, simulator products and exported patches stay in a separate report
directory. The boot bank, RTL and the initial-four regression remain unchanged.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from dx7_bank import ROOT, FACTORY_SHA, convert, unpack_voice
import dx7_validation

PROGRAMS = (32, 43, 79, 106)
REPORT = ROOT.parent / 'voice-system/reports/dry-audition'


def main():
    work = REPORT / 'simulation'
    for folder in ('vectors', 'examples', 'rom', 'patches'):
        (work / folder).mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'examples/FM_Keys.json', work / 'examples/FM_Keys.json')
    for rom in (ROOT / 'rom').glob('*.hex'):
        shutil.copy2(rom, work / 'rom' / rom.name)
    data = (ROOT / 'assets/fm1/factory.vmem').read_bytes()
    assert hashlib.sha256(data).hexdigest() == FACTORY_SHA
    voices = [data[i:i+128] for i in range(0, len(data), 128)]
    patches = []
    for program in PROGRAMS:
        patch = convert(voices[program], program)
        destination = work / 'patches' / f'{program:03d}.json'
        destination.write_text(json.dumps(patch, indent=2) + '\n', encoding='utf-8')
        patches.append(dict(program=program, name=unpack_voice(voices[program])['name'],
                            path=str(destination), raw_sha256=hashlib.sha256(voices[program]).hexdigest()))
    # Reuse the same independent model and unchanged testbench in an isolated cwd.
    dx7_validation.ROOT = work
    dx7_validation.INITIAL = PROGRAMS
    report = dx7_validation.engine_vectors(voices)
    vectors = (work / 'vectors/fm1_engine.txt').read_text(encoding='ascii')
    report['nonzero_model_frames'] = sum(line.startswith('1 ') and int(line.split()[-1], 16) != 0 for line in vectors.splitlines())
    assert report['nonzero_model_frames'] >= 9000, 'existing coverage threshold must remain valid'
    sources = [ROOT / name for name in (ROOT / 'sources.f').read_text().splitlines()]
    sources.append(ROOT / 'sim/tb_fm1_engine.v')
    (work / 'sources.prj').write_text(''.join(f'verilog work "{p.as_posix()}"\n' for p in sources), encoding='utf-8')
    report.update(programs=patches, factory_sha256=FACTORY_SHA,
                  source_sha256={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
                  vector_sha256=hashlib.sha256(vectors.encode('ascii')).hexdigest())
    vivado = Path('D:/Xilinx/2025.1/Vivado/bin')
    for name, args in [('xvlog', ['-prj', 'sources.prj']),
                       ('xelab', ['work.tb_fm1_engine', '-s', 'audition']),
                       ('xsim', ['audition', '-runall'])]:
        result = subprocess.run([str(vivado / f'{name}.bat'), *args], cwd=work,
                                capture_output=True, text=True, errors='replace', timeout=180)
        log = result.stdout + result.stderr
        (work / f'{name}-console.log').write_text(log, encoding='utf-8')
        if result.returncode or 'FATAL' in log or 'Fatal:' in log:
            raise RuntimeError(f'{name} failed: {log[-3000:]}')
        if name == 'xsim':
            passed = [line for line in log.splitlines() if line.startswith('PASS fm1_engine')]
            assert len(passed) == 1, log[-3000:]
            report['rtl_result'] = passed[0]
    report['status'] = 'model_and_rtl_pass'
    (REPORT / 'patch-qualification.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report | {'source_sha256': f'{len(sources)} checked source files'}, indent=2), flush=True)


if __name__ == '__main__':
    main()
