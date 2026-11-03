"""Measure hardware lowpass attenuation and autonomous LFO; restore user patch."""
from pathlib import Path
import copy,json,math,subprocess,time

SYSTEM=Path(__file__).resolve().parents[2]
APP=SYSTEM.parent/'desktop-tauri'
OUT=SYSTEM/'reports/master-lowpass'
process=subprocess.Popen([str(APP/'src-tauri/target/debug/voice-workspace-probe.exe')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
trace=[]
def action(kind,**values):
    request=dict(kind=kind,**values);process.stdin.write(json.dumps(request)+'\n');process.stdin.flush()
    line=process.stdout.readline()
    if not line:raise RuntimeError(process.stderr.read())
    response=json.loads(line);trace.append(dict(request=request,response=response))
    if not response['ok']:raise RuntimeError(response['error'])
    return response['view']

def capture():
    view=action('monitor_step')
    for _ in range(80):
        view=action('monitor_step')
        if view['monitor']['capture_progress']==512:break
    samples=view['monitor']['samples'];assert len(samples)==512
    return math.sqrt(sum(x*x for x in samples)/len(samples))

result={'status':'running'};original=None;old_filter=None
try:
    view=action('connect',port='COM4',fresh=False)
    assert view['filter']['available']
    original=copy.deepcopy(view['slots'][3]);old_filter=copy.deepcopy(view['filter']['profile'])
    action('panic')
    operator=dict(enabled=False,carrier=False,wave='sine',mode='pm',sources=[],ratio=None,fixed_hz=4000.,gain=.2,depth=0.,feedback=0.,morph=0.,pulse_width=.5,levels=[1.,1.,1.,0.],segment_ms=[5.,5.,5.,20.])
    operators=[copy.deepcopy(operator) for _ in range(6)];operators[0].update(enabled=True,carrier=True)
    action('load_native',slot=3,patch=dict(name='Lowpass measurement',operators=operators))
    base=dict(enabled=False,cutoff_hz=18000.,lfo_enabled=False,lfo_rate_hz=1.,lfo_depth_oct=2.,lfo_shape=0)
    action('filter_apply',profile=base)
    action('note',token='filter-measure',note=60,velocity=100,slot=3,pressed=True)
    time.sleep(.08);dry=capture();assert dry>50
    low={**base,'enabled':True,'cutoff_hz':300.};action('filter_apply',profile=low);time.sleep(.08);low_rms=capture()
    high={**base,'enabled':True};action('filter_apply',profile=high);time.sleep(.08);high_rms=capture()
    assert low_rms<dry*.1 and high_rms>dry*.7,(dry,low_rms,high_rms)
    action('panic')
    mod={**base,'enabled':True,'cutoff_hz':2000.,'lfo_enabled':True,'lfo_rate_hz':2.0,'lfo_depth_oct':2.0}
    action('filter_apply',profile=mod)
    cutoffs=[]
    for _ in range(18):
        time.sleep(.04);view=action('filter_step');cutoffs.append(view['filter']['actual_cutoff_hz']);assert view['filter']['applied']
    assert max(cutoffs)>3500 and min(cutoffs)<1200,cutoffs
    for _ in range(9):view=action('poll')
    assert view['retries']==0 and not view['pending']
    assert all(view['telemetry'][name]==0 for name in ['underruns','bad_packets','overruns','pcm_dropped'])
    result.update(status='PASS',dry_rms=dry,low_300hz_rms=low_rms,high_18000hz_rms=high_rms,attenuation_db=20*math.log10(max(low_rms,1e-9)/dry),lfo_cutoffs=cutoffs,retries=view['retries'],telemetry=view['telemetry'])
    print(f'PASS hardware lowpass:4kHz attenuation{result["attenuation_db"]:.1f}dB at300Hz cutoff; LFO{min(cutoffs):.0f}..{max(cutoffs):.0f}Hz;zero retries/errors',flush=True)
finally:
    try:
        action('panic')
        if original:
            if original.get('native'):action('load_native',slot=3,patch=original['native'])
            else:action('load',slot=3,program=original['program'],operators=original['operators'])
        if old_filter:action('filter_apply',profile=old_filter)
        view=action('filter_step');result['restored_filter']=view['filter'];result['restored_slot']=view['slots'][3]
        action('disconnect')
    except Exception as error:result['restore_error']=str(error)
    process.stdin.close();process.wait(timeout=10)
    (OUT/'board-filter.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'board-filter-actions.json').write_text(json.dumps(trace,ensure_ascii=False,indent=2),encoding='utf-8')
