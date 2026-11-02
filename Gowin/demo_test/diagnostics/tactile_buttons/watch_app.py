"""Record diagnostic snapshots without opening a second UART handle."""
import argparse
import json
from pathlib import Path
import time

root = Path(__file__).resolve().parent
args = argparse.ArgumentParser()
args.add_argument('--seconds', type=float, default=180)
args.add_argument('--out', default='guided')
options = args.parse_args()
if not options.out.replace('_','').replace('-','').isalnum():
    raise SystemExit('Use a simple output stem')
previous = None
start = time.monotonic()
records = []
events = []
print('APP CAPTURE READY', flush=True)
with (root / 'reports' / (options.out+'.jsonl')).open('w', encoding='utf-8') as out:
    while time.monotonic() - start < options.seconds:
        try:
            state = json.loads((root / 'reports/app-live.json').read_text(encoding='utf-8'))
            button = state['buttons']['record']
        except (OSError, ValueError, KeyError):
            time.sleep(.1)
            continue
        if button and (previous is None or button['sequence'] != previous['record']['sequence']):
            row = dict(seconds=round(time.monotonic()-start,3), now=state['now'], record=button,
                       connection=state['connection'], fresh=state['buttons']['fresh'],
                       errors=state['errors'], sequence_errors=state['sequence_errors'],
                       rx_bytes=state['rx_bytes'], tx_bytes=state['tx_bytes'])
            out.write(json.dumps(row)+'\n');out.flush();records.append(row)
            if previous:
                for i in range(6):
                    press=(button['presses'][i]-previous['record']['presses'][i])&65535
                    release=(button['releases'][i]-previous['record']['releases'][i])&65535
                    if press or release:
                        event=dict(seconds=row['seconds'],switch=i+1,press=press,release=release)
                        events.append(event);print(json.dumps(event),flush=True)
            previous=row
        time.sleep(.1)
summary=dict(first=records[0] if records else None,last=records[-1] if records else None,events=events,snapshots=len(records))
(root / 'reports' / (options.out+'.json')).write_text(json.dumps(summary,indent=2),encoding='utf-8')
print('APP CAPTURE COMPLETE',len(records),flush=True)
