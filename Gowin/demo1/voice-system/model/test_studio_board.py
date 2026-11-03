"""Exercise the GUI Rust backend on the real board; restore boot patches afterward."""
from pathlib import Path
import subprocess,json,time,math,sys
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/unified-studio'
EXE=ROOT.parent/'desktop-tauri/src-tauri/target/debug/voice-workspace-probe.exe'
p=subprocess.Popen([str(EXE)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
log=(OUT/'board-actions.jsonl').open('w',encoding='utf-8')
def action(kind,expect=True,**kw):
    request=dict(kind=kind,**kw);p.stdin.write(json.dumps(request)+'\n');p.stdin.flush()
    line=p.stdout.readline()
    if not line:raise RuntimeError(p.stderr.read())
    result=json.loads(line);log.write(json.dumps(dict(request=request,response=result),ensure_ascii=False)+'\n');log.flush()
    if expect and not result['ok']:raise RuntimeError(result['error'])
    if not expect and result['ok']:raise AssertionError('Expected rejection')
    return result['view']
def native(mode):
    ops=[]
    for i in range(6):ops.append(dict(enabled=i<2,carrier=i==1,wave='sine',mode=mode,sources=[0] if i==1 else [],ratio=2 if i==0 else 1,fixed_hz=None,gain=1.,depth=(.7 if mode in ('am','ring') else .12) if i==1 else 0.,feedback=0.,morph=0.,pulse_width=.5,levels=[1.,.65,.65,0.],segment_ms=[8.,160.,0.,250.]))
    return dict(name=f'Studio {mode} verification',operators=ops)
def assign(key,patch=None,program=None,scope='key',expect=True):
    return action('assign_key',expect,key=key,scope=scope,program=program,patch=patch,operators=None)
def capture():
    start=time.monotonic();v=action('monitor_step');time.sleep(.02)
    for _ in range(70):
        v=action('monitor_step')
        if v['monitor']['capture_progress']==512:break
    samples=v['monitor']['samples'];assert len(samples)==512 and max(map(abs,samples))>0
    return dict(samples=samples,elapsed_ms=round((time.monotonic()-start)*1000),peak=max(map(abs,samples)),rms=math.sqrt(sum(s*s for s in samples)/512),generation=v['monitor']['generation'])
before=None;captures={};result={}
try:
    before=action('connect',port='COM4',fresh='--fresh' in sys.argv)
    assert before['monitor']['available'] and len(before['keys'])==32
    assert all(k==dict(slot=0,note=48+i,velocity=100) for i,k in enumerate(before['keys']))
    action('control',volume=.4,sustain=False)
    for key,mode in enumerate(('pm','am','ring')):
        v=assign(key,native(mode));slot=v['keys'][key]['slot'];assert slot==key+1
        action('configure_key',key=key,note=60+key*4,velocity=100)
        action('note',token='board-check',note=60,velocity=100,slot=slot,pressed=True)
        time.sleep(.12);captures[mode]=capture();action('note',token='board-check',note=60,velocity=100,slot=slot,pressed=False);action('panic')
        print(mode,'slot',slot,'capture',captures[mode]['elapsed_ms'],'ms', 'peak',captures[mode]['peak'],flush=True)
    old_keys=action('poll')['keys'];v=assign(3,native('fm'),expect=False);assert v['keys']==old_keys
    v=assign(0,program=32);slot=v['keys'][0]['slot'];assert slot==1 and v['keys'][1]['slot']==2
    action('note',token='board-check',note=60,velocity=100,slot=slot,pressed=True);time.sleep(.12);captures['FM1_GUITAR1']=capture();action('panic')
    # A completely assigned keyboard can still choose a sound already present.
    v=assign(4,program=32);assert v['keys'][4]['slot']==1
    action('disconnect');v=action('connect',port='COM4',fresh=False)
    assert v['keys'][0]['slot']==1 and v['keys'][1]['slot']==2 and v['keys'][4]['slot']==1
    assert v['keys'][0]['note']==60 and v['keys'][1]['note']==64
    for _ in range(9):v=action('poll')
    assert all(v['telemetry'][k]==0 for k in ('underruns','bad_packets','overruns','pcm_dropped'))
    assert v['retries']==0 and not v['pending']
    result=dict(result='PASS',port='COM4',features=['four-patch ownership allocator','key mapping ACK/readback','basic PM/AM/Ring capture','FM1 six-operator preset','full capacity rejection preserves map','existing-sound reuse','durable reconnect'],captures=captures,view=v)
    print('PASS real board mapping, preset assignment, PCM capture, reconnect, no hardware errors',flush=True)
finally:
    if before:
        try:
            action('panic')
            # Restore the original boot patches and original MIDI mapping.
            for slot,s in enumerate(before['slots']):
                action('load',slot=slot,program=s['program'],operators=s['operators'])
            assign(0,program=before['slots'][0]['program'],scope='all')
            for key,k in enumerate(before['keys']):action('configure_key',key=key,note=k['note'],velocity=k['velocity'])
            action('control',volume=before['volume'],sustain=False);result['restored']=True
            action('disconnect')
        except Exception as e:result['restore_error']=str(e)
    p.stdin.close();p.wait(timeout=8);log.close()
    (OUT/'board-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
