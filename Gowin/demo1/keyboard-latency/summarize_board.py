"""Summarize actual App telemetry; keep hearing confirmation separate."""
from pathlib import Path
import argparse,datetime,json

ROOT=Path(__file__).resolve().parent

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hearing',default='Awaiting user confirmation')
    args=parser.parse_args()
    rows=[]
    for line in (ROOT/'reports/app-telemetry.jsonl').read_text(encoding='utf-8').splitlines():
        try:rows.append(json.loads(line))
        except json.JSONDecodeError:pass  # Capture writer may be finishing its last line.
    rows=[r for r in rows if r.get('version')==4]
    assert rows,'No App protocol-4 capture'
    for r in rows:
        assert r['flags']&7==0 and r['cycles']==385 and r['stages']==127,r
        latency=r['latency']
        if latency['records']:
            assert latency['total']==sum(latency[k] for k in ('qualify','queue','compute','onset_wait','output'))
            assert latency['total']==(latency['dac']-latency['start'])&0xffffffff
            assert latency['minimum']<=latency['total']<=latency['maximum']
            assert latency['mix']<=latency['output']
    last=rows[-1];l=last['latency']
    physical={r['latency']['dac']:r['latency'] for r in rows if r['latency']['records'] and r['latency']['flags']&1}
    summary=dict(created=datetime.datetime.now().isoformat(),digital_validation_passed=True,
        hearing_confirmation=args.hearing,packets_observed=len(rows),
        cycles_per_frame=385,compute_microseconds=7.7,sample_rate_hz=50000000/1024,
        max_active_in_app_snapshots=max(r['active'] for r in rows),
        max_physical_pressed_in_app_snapshots=max(r['pressed'].bit_count() for r in rows),
        fault_overrun_underrun_packets=0,clip_counter_increase=last['clips']-rows[0]['clips'],
        latest_statistics=l,
        latest_statistics_ms=dict(minimum=l['minimum']/50000,mean=l['sum']/max(1,l['records'])/50000,maximum=l['maximum']/50000) if l['records'] else None,
        physical_details_seen=len(physical),
        physical_keys_seen=sorted(set(p['key']+1 for p in physical.values())),
        scan_period_cycles=sorted(set(p['scan_period'] for p in physical.values())),
        last_frame=last,
        limitations=['UART capture contains periodic snapshots, not lossless per-event detail.',
            'Aggregate counters and sum include every FPGA completion since the last clear.',
            'Start is first qualifying ADC result, excluding mechanical-to-first-scan wait.',
            'End is digital PT8211 left-word latch, excluding analog/acoustic delay.'])
    (ROOT/'reports/app_validation.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in summary.items() if k not in ('last_frame','latest_statistics','limitations')},ensure_ascii=False,indent=2))

if __name__=='__main__':main()
