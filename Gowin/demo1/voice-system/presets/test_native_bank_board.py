"""Exercise the shipped Native bank through the real GUI backend; restore settings."""
from pathlib import Path
import argparse,copy,json,math,os,subprocess,time

SYSTEM=Path(__file__).resolve().parents[1]
APP=SYSTEM.parent/'desktop-tauri'
OUT=SYSTEM/'reports/native-presets'
SESSION=Path(os.environ['LOCALAPPDATA'])/'SynthString/voice-engine/COM4.json'

def saved_session():
    # COM4 is a reserved DOS basename; the actual persisted file uses Win32 long paths.
    return Path('\\\\?\\'+str(SESSION)).read_text(encoding='utf-8')

before_raw=saved_session();(OUT/'baseline/session-COM4.json').write_text(before_raw,encoding='utf-8')
before=json.loads(before_raw)
bank=json.loads((APP/'src-tauri/assets/native-presets.json').read_text(encoding='utf-8'))['presets']
parser=argparse.ArgumentParser();parser.add_argument('--preset',action='append');args=parser.parse_args()
selected=[p for p in bank if not args.preset or p['id'] in args.preset]
process=subprocess.Popen([str(APP/'src-tauri/target/debug/voice-workspace-probe.exe')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
trace=[]

def action(kind,**values):
    request=dict(kind=kind,**values);process.stdin.write(json.dumps(request)+'\n');process.stdin.flush()
    line=process.stdout.readline()
    if not line:raise RuntimeError(process.stderr.read())
    response=json.loads(line)
    # Repeated full 512-sample snapshots are unnecessary in the command trace.
    short=copy.deepcopy(response)
    if short.get('view',{}).get('monitor'):short['view']['monitor'].pop('samples',None)
    trace.append(dict(request=request,response=short))
    if not response['ok']:raise RuntimeError(response['error'])
    return response['view']

def capture():
    view=action('monitor_step')
    for _ in range(85):
        view=action('monitor_step')
        if view['monitor']['capture_progress']==512:break
    assert view['monitor']['capture_progress']==512,'capture incomplete'
    samples=view['monitor']['samples'];assert len(samples)==512
    return dict(rms=math.sqrt(sum(x*x for x in samples)/512),peak=max(map(abs,samples)),samples=samples)

def equivalent(a,b):
    if isinstance(a,dict):return isinstance(b,dict) and a.keys()==b.keys() and all(equivalent(a[k],b[k]) for k in a)
    if isinstance(a,list):return isinstance(b,list) and len(a)==len(b) and all(equivalent(x,y) for x,y in zip(a,b))
    # serde_json round-trips non-dyadic ratios within an ULP; topology stays exact.
    if isinstance(a,float):return isinstance(b,(int,float)) and math.isclose(a,b,rel_tol=1e-14,abs_tol=1e-14)
    return a==b

result=dict(status='running',presets=[]);original=None;old_filter=None;failure=None
try:
    view=action('connect',port='COM4',fresh=False)
    original=copy.deepcopy(view['slots'][3]);old_filter=copy.deepcopy(view['filter']['profile'])
    action('panic');action('filter_apply',profile={**old_filter,'enabled':False,'lfo_enabled':False})
    for _ in range(9):view=action('poll')
    initial=copy.deepcopy(view['telemetry'])
    for preset in selected:
        action('panic');view=action('load_native',slot=3,patch=preset['patch'])
        assert equivalent(view['slots'][3]['native'],preset['patch']),preset['id']
        action('note',token='native-bank-test',note=60,velocity=110,slot=3,pressed=True)
        if not preset['percussive']:time.sleep(.4)
        audio=capture();assert audio['peak']>8,(preset['id'],audio['peak'])
        row=dict(id=preset['id'],rms=audio['rms'],peak=audio['peak'],samples=audio['samples'])
        result['presets'].append(row)
        if preset['percussive']:
            time.sleep(.75)
            for _ in range(9):view=action('poll')
            row['held_telemetry']=view['telemetry'];tail=capture()
            row['tail_samples']=tail['samples']
            row['held_tail_peak']=tail['peak']
            assert tail['peak']==0,(preset['id'],'held tail',tail['peak'],view['telemetry'])
        action('note',token='native-bank-test',note=60,velocity=110,slot=3,pressed=False)
        print('PASS',preset['id'],'PCM peak',audio['peak'],flush=True)
    action('panic')
    open_hat=next(p for p in bank if p['id']=='drum-hat-open')
    action('load_native',slot=3,patch=open_hat['patch'])
    for index in range(8):action('note',token=f'native-chord-{index}',note=48+index,velocity=110,slot=3,pressed=True)
    chord=capture();assert 8<chord['peak']<32760
    for _ in range(9):view=action('poll')
    counters=['underruns','bad_packets','overruns','pcm_dropped']
    deltas={k:view['telemetry'][k]-initial[k] for k in counters}
    assert not any(deltas.values()),deltas
    assert view['retries']==0 and not view['pending']
    result.update(status='PASS',chord_8voices=chord,retries=view['retries'],telemetry=view['telemetry'],error_deltas=deltas)
except Exception as error:
    failure=error;result.update(status='FAIL',error=str(error))
finally:
    try:
        action('panic')
        if original:
            if original.get('native'):action('load_native',slot=3,patch=original['native'])
            else:action('load',slot=3,program=original['program'],operators=original['operators'])
        if old_filter:action('filter_apply',profile=old_filter)
        view=action('filter_step');action('disconnect')
        after=json.loads(saved_session())
        # Revisions and protocol sequence advance; all user-owned settings must match.
        def settings(v):
            v=copy.deepcopy(v)
            for s in v.get('slots',[]):s.pop('revision',None)
            return {k:v[k] for k in ['slots','keys','volume','sustain','wave_name','wave','wave_morph','keyboard','filter'] if k in v}
        assert settings(after)==settings(before),'user settings differ after restore'
        result['user_settings_restored']=True
        (OUT/'restored-session.json').write_text(json.dumps(after,ensure_ascii=False,indent=2),encoding='utf-8')
    except Exception as error:
        result['restore_error']=str(error);result['status']='FAIL';failure=failure or error
    process.stdin.close();process.wait(timeout=10)
    (OUT/'board.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'board-actions.json').write_text(json.dumps(trace,ensure_ascii=False,indent=2),encoding='utf-8')
if failure:raise failure
print(f'PASS{len(selected)} hardware patches;8-voice six-operator drum;zero new audio/protocol errors;user settings restored',flush=True)
