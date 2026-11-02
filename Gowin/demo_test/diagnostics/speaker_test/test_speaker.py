"""Short, low-volume speaker test through the existing verified FPGA audio path.

No RTL, saved App profiles, bridge firmware or Flash is modified. The caller
must first confirm the attached load and absence of a 3.5 mm headphone plug.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import sys
import time

ROOT = Path(__file__).resolve().parent
AUDIO = ROOT.parents[2] / 'demo1/keyboard-latency'
sys.path.insert(0, str(AUDIO))
from live_latency import Board, profile


def preflight():
    bitstream = AUDIO / 'impl/pnr/keyboard_latency.fs'
    expected = '3a75079156d8297e54b693b39644fd1981deadba368cbdc0e5d5e6e1047d02ec'
    actual = hashlib.sha256(bitstream.read_bytes()).hexdigest()
    assert actual == expected, 'Bitstream differs from the previously validated audio build'
    for name in ('latency_supervisor', 'latency_keyboard_audio'):
        report = json.loads((AUDIO / f'reports/{name}.json').read_text(encoding='utf-8'))
        assert report['passed'], name
        for path, digest in report['source_sha256'].items():
            assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, path
    return dict(bitstream=str(bitstream), sha256=actual, source_match=True,
                existing_simulations_passed=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preflight-only', action='store_true')
    parser.add_argument('--port', default='COM4')
    parser.add_argument('--volume', type=int, choices=(1, 2, 3, 4, 5, 6), default=1)
    args = parser.parse_args()
    (ROOT / 'reports').mkdir(exist_ok=True)
    result = dict(created=datetime.datetime.now().isoformat(), preflight=preflight(),
                  digital_passed=False, hearing='Awaiting user confirmation', tones=[])
    if args.preflight_only:
        (ROOT / 'reports/preflight.json').write_text(json.dumps(result['preflight'], indent=2), encoding='utf-8')
        print(json.dumps(result['preflight'], indent=2))
        return

    board = Board(args.port)
    changed = False
    key = 12
    restored = False
    error = None

    def poll(seconds):
        until = time.monotonic() + seconds
        heartbeat = time.monotonic()
        while time.monotonic() < until:
            board.poll(min(.06, max(.001, until-time.monotonic())))
            assert board.records and board.records[-1]['pressed'] == 0, 'Release physical keys during the speaker test'
            if time.monotonic()-heartbeat >= .35:
                board.send(7)
                heartbeat = time.monotonic()

    try:
        board.port.write(b'0P')
        board.poll(.5)
        assert board.records, 'No protocol-4 telemetry'
        result['initial'] = board.records[-1]
        assert result['initial']['pressed'] == 0, 'A physical key is held'
        board.command(4)
        board.command(6, payload=bytes([0]))
        tone = profile(note=69, wave_a=0, gain_a=1, gain_b=0, velocity=80,
                       attack=20, decay=100, sustain=.7, release=80, cutoff=2500)
        changed = True
        board.command(1, key, tone.to_bytes(64, 'little'))
        board.command(6, payload=bytes([args.volume]))
        poll(.3)
        for index in range(3):
            offset = len(board.records)
            before = board.records[-1]
            board.command(2, key, bytes([80]))
            poll(.7)
            sounded = board.records[-1]
            assert sounded['active'] == 1 and sounded['nonzero'] > before['nonzero']
            peak = max(r['output_peak'] for r in board.records[offset:])
            assert peak > 0 and sounded['clips'] == before['clips']
            board.command(3, key)
            poll(.45)
            assert board.records[-1]['active'] == 0
            result['tones'].append(dict(number=index+1,frequency_hz=440,volume=args.volume,
                                       peak_pcm24=peak,nonzero_frames=sounded['nonzero']-before['nonzero'],
                                       automatic_noteoff=True))
            print(f'Tone {index+1}: peak={peak}, active returned to zero', flush=True)
        assert board.bad == 0, f'Invalid telemetry packets: {board.bad}'
        result['digital_passed'] = True
    except Exception as exc:
        error = str(exc)
    finally:
        try:
            board.command(4)
            board.port.write(b'P')
            board.command(6, payload=bytes([0]))
            if changed:
                original = int((AUDIO / 'note_profiles.hex').read_text().splitlines()[key], 16)
                board.command(1, key, original.to_bytes(64, 'little'))
                restored = True
            board.poll(.25)
        except Exception as exc:
            error = (error + '; ' if error else '') + 'cleanup: ' + str(exc)
        finally:
            board.port.close()
        result.update(error=error, key_profile_restored_to_boot=restored,
                      final=board.records[-1] if board.records else None,
                      packets=len(board.records),bad_packets=board.bad,
                      commands=board.commands,records=board.records)
        prefix = f'speaker_volume_{args.volume}'
        (ROOT / f'reports/{prefix}.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
        (ROOT / f'reports/{prefix}.bin').write_bytes(board.raw)
    print(json.dumps({k:v for k,v in result.items() if k not in ('records','commands')},indent=2))
    if error or not result['digital_passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
