"""Load all qualified presets through the App backend; preserve the user's mapping."""
import json
import math
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'reports/fm1-wave-repair'
EXE = ROOT.parent / 'desktop-tauri/src-tauri/target/debug/voice-workspace-probe.exe'
CATALOG = ROOT.parents[1] / 'demo_test/desktop-tauri/src-tauri/assets/fm1-library.json'


def main():
    process = subprocess.Popen([str(EXE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, encoding='utf-8')
    log = (REPORT / 'preset-board-actions.jsonl').open('w', encoding='utf-8')

    def action(kind, **values):
        request = dict(kind=kind, **values)
        process.stdin.write(json.dumps(request) + '\n')
        process.stdin.flush()
        line = process.stdout.readline()
        if not line:
            raise RuntimeError(process.stderr.read())
        result = json.loads(line)
        log.write(json.dumps(dict(request=request, response=result), ensure_ascii=False) + '\n')
        log.flush()
        if not result['ok']:
            raise RuntimeError(result['error'])
        return result['view']

    def capture():
        view = action('monitor_step')
        for _ in range(70):
            view = action('monitor_step')
            if view['monitor']['capture_progress'] == 512:
                return view['monitor']['samples']
        raise RuntimeError('capture did not complete')

    before = None
    report = dict(status='running', programs=[])
    try:
        before = action('connect', port='COM4', fresh=False)
        assert before['wave_transfer'] is None
        slot = before['keys'][0]['slot']
        for preset in json.loads(CATALOG.read_text(encoding='utf-8'))['presets']:
            action('panic')
            view = action('load', slot=slot, program=preset['program'], operators=None)
            assert view['slots'][slot]['program'] == preset['program']
            action('note', token='qualified-bank-test', note=60, velocity=100, slot=slot, pressed=True)
            time.sleep(.05)
            samples = capture()
            peak = max(map(abs, samples))
            assert peak > 0, f"silent preset {preset['program']}"
            view = action('panic')
            assert view['retries'] == 0 and not view['pending']
            report['programs'].append(dict(program=preset['program'], name=preset['name'],
                                           peak=peak, rms=math.sqrt(sum(s*s for s in samples)/512)))
            print('PASS', preset['program'], preset['name'], 'peak', peak, flush=True)
        for _ in range(9):
            view = action('poll')
        assert all(view['telemetry'][k] == 0 for k in ('underruns','bad_packets','overruns','pcm_dropped'))
        report['telemetry'] = view['telemetry']
        report['status'] = 'PASS'
    finally:
        if before:
            action('panic')
            for slot, patch in enumerate(before['slots']):
                if patch.get('native'):
                    action('load_native', slot=slot, patch=patch['native'])
                else:
                    action('load', slot=slot, program=patch['program'], operators=patch['operators'])
            view = action('poll')
            assert view['keys'] == before['keys']
            for original, restored in zip(before['slots'], view['slots']):
                for field in ('program','operators','native'):
                    assert original.get(field) == restored.get(field)
            report['user_configuration_restored'] = True
            action('disconnect')
        process.stdin.close()
        process.wait(timeout=10)
        log.close()
        (REPORT / 'preset-board-result.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')


if __name__ == '__main__':
    main()
