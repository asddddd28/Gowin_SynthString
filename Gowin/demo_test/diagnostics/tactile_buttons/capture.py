"""Capture B1 switch telemetry; optionally perform an explicit SRAM-only download."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import serial

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'spec'))
from reference_model import decode

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', default='COM4')
    parser.add_argument('--seconds', type=float, default=8)
    parser.add_argument('--out', default='idle')
    parser.add_argument('--program', action='store_true')
    args = parser.parse_args()
    if not args.out.replace('_','').replace('-','').isalnum():
        raise SystemExit('Output name must be a simple stem')
    path = ROOT / 'reports' / args.out
    port = serial.Serial(port=None, baudrate=115200, timeout=.03, write_timeout=.5)
    port.dtr = False
    port.rts = False
    port.port = args.port
    records, events, buffer = [], [], bytearray()
    errors = gaps = 0
    port.open()  # Exclusive access must succeed before any programming.
    try:
        if args.program:
            fs = ROOT / 'impl/pnr/tactile_buttons.fs'
            preflight = json.loads((ROOT / 'reports/preflight.json').read_text(encoding='utf-8'))
            assert hashlib.sha256(fs.read_bytes()).hexdigest() == preflight['bitstream_sha256']
            assert preflight['timing_clean'] and preflight['simulation_passed']
            for source, digest in preflight['source_sha256'].items():
                assert hashlib.sha256(Path(source).read_bytes()).hexdigest() == digest, source
            with (ROOT / 'reports/program_sram.log').open('w', encoding='utf-8') as log:
                result = subprocess.run([
                    'C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe',
                    '--device', 'GW5AT-60B', '--cable-index', '4', '--run', '2',
                    '--frequency', '15MHz', '--fsFile', str(fs)], stdout=log, stderr=subprocess.STDOUT, timeout=90)
            log = (ROOT / 'reports/program_sram.log').read_text(encoding='utf-8')
            assert result.returncode == 0 and 'Finished.' in log, log[-1000:]
            print(log[-280:], flush=True)
        # Discard the bridge's opening fragment and retain evidence from a complete line.
        warmup = time.monotonic() + 1
        while time.monotonic() < warmup:
            port.read(max(1, min(4096, port.in_waiting)))
        port.reset_input_buffer()
        aligned = False
        start = time.monotonic()
        print(f'CAPTURE READY {args.port} {args.out}', flush=True)
        with path.with_suffix('.bin').open('wb') as raw:
            while time.monotonic() - start < args.seconds:
                data = port.read(max(1, min(4096, port.in_waiting)))
                raw.write(data)
                buffer.extend(data)
                while b'\n' in buffer:
                    end = buffer.index(10) + 1
                    line = bytes(buffer[:end]); del buffer[:end]
                    if not aligned:
                        aligned = True
                        continue
                    try:
                        row = decode(line)
                    except (ValueError, AssertionError):
                        errors += 1
                        continue
                    row['seconds'] = round(time.monotonic() - start, 4)
                    if records:
                        old = records[-1]
                        if row['sequence'] != (old['sequence'] + 1) & 65535:
                            gaps += 1
                        for i in range(6):
                            press = (row['presses'][i] - old['presses'][i]) & 65535
                            release = (row['releases'][i] - old['releases'][i]) & 65535
                            if press or release:
                                event = dict(seconds=row['seconds'], switch=i+1, press=press, release=release)
                                events.append(event)
                                print(json.dumps(event), flush=True)
                    records.append(row)
                    # A small live summary is atomically refreshed for asynchronous review.
                    if len(records) % 50 == 0:
                        live = dict(packets=len(records), errors=errors, gaps=gaps, last=row, events=events)
                        temp = path.with_suffix('.tmp')
                        temp.write_text(json.dumps(live, indent=2), encoding='utf-8')
                        temp.replace(path.with_suffix('.live.json'))
    finally:
        port.close()
    summary = dict(port=args.port, packets=len(records), errors=errors, gaps=gaps,
                   first=records[0] if records else None, last=records[-1] if records else None,
                   events=events, records=records)
    path.with_suffix('.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    print(json.dumps({k:v for k,v in summary.items() if k not in ('records','events')}, indent=2), flush=True)
    if not records or errors or gaps:
        raise SystemExit(1)

if __name__ == '__main__':
    main()
