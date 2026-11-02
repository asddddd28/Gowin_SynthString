"""Timestamp encoder telemetry; drain old USB data before measuring live deltas."""
import argparse
import datetime as dt
import json
from pathlib import Path
import re
import time

import serial


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', default='COM4')
    parser.add_argument('--seconds', type=float, default=120)
    parser.add_argument('--warmup', type=float, default=5)
    parser.add_argument('--label', default='live')
    parser.add_argument('--stop-file', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent / 'reports'
    root.mkdir(exist_ok=True)
    prefix = root / ('encoder_' + args.label + '_' + dt.datetime.now().strftime('%Y%m%d_%H%M%S'))
    pattern = re.compile(rb'E([1-5]) A([0-3]) F([0-3]) Q([0-9A-F]{4}) P([0-9A-F]{4}) N([0-9A-F]{4}) X([0-9A-F]{4})\r\n')
    first, last, states = {}, {}, {}
    count = sequence_errors = invariant_errors = unmatched_bytes = 0
    previous = None
    pending = b''
    started = time.monotonic()
    started_at = dt.datetime.now().astimezone().isoformat()
    last_save = 0
    ready = False

    def save(finished=False):
        channels = []
        for channel in sorted(last):
            a, b = first[channel], last[channel]
            channels.append(dict(encoder=channel, first=a, last=b,
                                 positive_delta=(b['positive']-a['positive']) & 65535,
                                 negative_delta=(b['negative']-a['negative']) & 65535,
                                 invalid_delta=(b['invalid']-a['invalid']) & 65535,
                                 raw_states=sorted(states[channel])))
        summary = dict(started_at=started_at, elapsed=time.monotonic()-started,
                       warmup_seconds=args.warmup, finished=finished, port=args.port,
                       records=count, sequence_errors=sequence_errors,
                       invariant_errors=invariant_errors, unmatched_bytes=unmatched_bytes,
                       pending_bytes=len(pending), channels=channels,
                       timestamp_note='Host receive time; USB batches may contain multiple FPGA snapshots.',
                       transport_pass=count > 0 and len(last) == 5 and
                       sequence_errors == 0 and invariant_errors == 0 and unmatched_bytes == 0)
        prefix.with_suffix('.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
        return summary

    port = serial.Serial(port=None, baudrate=115200, timeout=0.1,
                         rtscts=False, dsrdtr=False, xonxoff=False)
    port.dtr = port.rts = False
    port.port = args.port
    print('Prefix=' + str(prefix), flush=True)
    try:
        port.open()
        port.reset_input_buffer()
        started = time.monotonic()
        with prefix.with_suffix('.bin').open('wb') as raw, prefix.with_suffix('.jsonl').open('w', encoding='utf-8') as rows:
            while time.monotonic()-started < args.warmup + args.seconds:
                if args.stop_file and args.stop_file.exists():
                    break
                data = port.read(port.in_waiting or 1)
                elapsed = time.monotonic()-started
                raw.write(data)
                raw.flush()
                pending += data
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1)
                    match = pattern.fullmatch(line + b'\n')
                    if elapsed < args.warmup:
                        continue
                    if not match:
                        unmatched_bytes += len(line)+1
                        continue
                    values = [int(v, 10 if i < 3 else 16) for i, v in enumerate(match.groups())]
                    channel, raw_ab, filtered, position, positive, negative, invalid = values
                    record = dict(elapsed=round(elapsed, 6), encoder=channel,
                                  raw=raw_ab, filtered=filtered,
                                  position=position-65536 if position >= 32768 else position,
                                  positive=positive, negative=negative, invalid=invalid)
                    if previous is not None and channel != previous % 5 + 1:
                        sequence_errors += 1
                    if position != (positive-negative) & 65535:
                        invariant_errors += 1
                    previous = channel
                    first.setdefault(channel, record)
                    last[channel] = record
                    states.setdefault(channel, set()).add(raw_ab)
                    count += 1
                    rows.write(json.dumps(record)+'\n')
                rows.flush()
                if elapsed >= args.warmup and not ready:
                    ready = True
                    print('READY: warmup complete; recording live telemetry', flush=True)
                if elapsed-last_save >= 1:
                    save()
                    last_save = elapsed
    finally:
        port.close()
        summary = save(finished=True)
        print(json.dumps(summary, indent=2), flush=True)


if __name__ == '__main__':
    main()
