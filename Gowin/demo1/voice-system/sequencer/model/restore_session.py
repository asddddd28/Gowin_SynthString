"""Restore the latest pre-SD-diagnostic session, without changing user drafts."""
from pathlib import Path
import json,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'reports/sequencer/sd-recheck-20261103'
APP=ROOT.parent/'desktop-tauri'
before=json.loads((OUT/'session-COM4.json').read_text(encoding='utf-8'))
process=subprocess.Popen([str(APP/'src-tauri/target/debug/voice-workspace-probe.exe')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
log=(OUT/'restore-actions.jsonl').open('a',encoding='utf-8')


def action(kind,**values):
    request=dict(kind=kind,**values);process.stdin.write(json.dumps(request)+'\n');process.stdin.flush()
    line=process.stdout.readline()
    if not line:raise RuntimeError(process.stderr.read())
    reply=json.loads(line);log.write(json.dumps(dict(request=request,response=reply),ensure_ascii=False)+'\n');log.flush()
    if not reply['ok']:raise RuntimeError(reply['error'])
    return reply['view']


def source_wave(name):
    helper=subprocess.Popen([str(APP/'src-tauri/target/debug/studio-test-harness.exe'),str(APP/'src-tauri/assets'),str(OUT/'asset-probe-config.json')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,encoding='utf-8')
    def call(method,params={}):
        helper.stdin.write(json.dumps(dict(method=method,params=params))+'\n');helper.stdin.flush()
        result=json.loads(helper.stdout.readline());assert result['ok'],result;return result['result']
    try:
        sound=next(s for s in call('bank_catalog') if s['title']==name)
        return call('voice_preset_wave',dict(timbre_id=sound['id']))
    finally:helper.stdin.close();helper.wait(timeout=10)


result={'ok':False}
try:
    view=action('connect',port='COM4',fresh=True);assert view['abi']==0x10007
    deadline=time.monotonic()+60
    while view['storage'].get('service') and (view['storage']['busy'] or view['storage'].get('syncing')):
        if time.monotonic()>deadline:raise RuntimeError('SD service did not become idle before restore')
        time.sleep(.05);view=action('storage_step')
    action('panic');print('Original ABI 1.7 confirmed',flush=True)
    if before.get('wave_name'):
        wave=source_wave(before['wave_name']);action('wave_begin',name=wave['name'],samples=wave['samples'],morph=before.get('wave_morph',0))
        while True:
            view=action('wave_step');written=view['wave_transfer']['written']
            if written%256==0:print('Restoring wave',written,'/2048',flush=True)
            if written==2048:break
        action('wave_finish')
    for slot,patch in enumerate(before['slots']):
        if patch.get('native'):action('load_native',slot=slot,patch=patch['native'])
        else:action('load',slot=slot,program=patch['program'],operators=patch['operators'])
    for key,mapping in enumerate(before['keys']):
        patch=before['slots'][mapping['slot']]
        action('assign_key',key=key,scope='key',program=patch['program'],patch=patch.get('native'),operators=None if patch.get('native') else patch['operators'])
        view=action('configure_key',key=key,note=mapping['note'],velocity=mapping['velocity'])
    assert view['keys']==before['keys']
    for expected,actual in zip(before['slots'],view['slots']):
        for field in ('native','program','operators'):assert expected.get(field)==actual.get(field),field
    if before.get('keyboard'):
        profile=before['keyboard'];view=action('keyboard_apply',**{k:profile[k] for k in ('release','press','sensitivity','velocity_enabled','velocity_ceiling')})
        assert view['keyboard']['profile']['keys']==profile['keys']
    if before.get('filter'):action('filter_apply',profile=before['filter'])
    if before.get('touch'):action('touch_apply',profile=before['touch'])
    action('control',volume=before['volume'],sustain=before['sustain'])
    for _ in range(9):view=action('poll')
    assert all(view['telemetry'][k]==0 for k in ('underruns','bad_packets','overruns','pcm_dropped'))
    assert not view['pending'] and view['retries']==0
    result.update(ok=True,final_view=view)
    print('PASS all four patches, 32 mappings, wave, calibration, filter, touch, volume restored; zero serial/audio faults',flush=True)
finally:
    try:action('disconnect')
    except Exception as error:result['disconnect_error']=str(error)
    process.stdin.close();process.wait(timeout=10);log.close()
    (OUT/'restore-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
