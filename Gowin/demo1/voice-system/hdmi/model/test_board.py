"""Validate the HDMI/audio board through the same Rust session used by the App."""
from pathlib import Path
import json
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
SYSTEM=ROOT.parent
REPORT=SYSTEM/'reports/synthui-hdmi'
APP=SYSTEM.parent/'desktop-tauri'
before=json.loads((REPORT/'session-after-close.json').read_text(encoding='utf-8'))
process=subprocess.Popen([str(APP/'src-tauri/target/debug/voice-workspace-probe.exe')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
log=(REPORT/'board-actions.jsonl').open('a',encoding='utf-8')
def action(kind,**values):
    request=dict(kind=kind,**values)
    process.stdin.write(json.dumps(request)+'\n');process.stdin.flush()
    line=process.stdout.readline()
    if not line: raise RuntimeError(process.stderr.read())
    result=json.loads(line)
    log.write(json.dumps({'request':request,'response':result},ensure_ascii=False)+'\n');log.flush()
    if not result['ok']: raise RuntimeError(result['error'])
    return result['view']

def source_wave(name):
    helper=subprocess.Popen([str(APP/'src-tauri/target/debug/studio-test-harness.exe'),str(APP/'src-tauri/assets'),str(REPORT/'asset-probe-config.json')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
    def call(method,params={}):
        helper.stdin.write(json.dumps({'method':method,'params':params})+'\n');helper.stdin.flush()
        result=json.loads(helper.stdout.readline());assert result['ok'],result
        return result['result']
    try:
        sound=next(s for s in call('bank_catalog') if s['title']==name)
        return call('voice_preset_wave',{'timbre_id':sound['id']})
    finally: helper.stdin.close();helper.wait(timeout=10)

result={'status':'running','audio':[]}
try:
    view=action('connect',port='COM4',fresh='--fresh' in sys.argv)
    view=action('hdmi_step');assert view['hdmi']['available'] is True
    print('PASS HDMI capability, local protocol and existing monitor',flush=True)
    action('panic')
    if before.get('wave_name'):
        asset=source_wave(before['wave_name'])
        if view.get('wave_transfer') is None:
            action('wave_begin',name=asset['name'],samples=asset['samples'],morph=before.get('wave_morph',0))
        while True:
            view=action('wave_step')
            if view['wave_transfer']['written']%256==0:print('wave',view['wave_transfer']['written'],'/2048',flush=True)
            if view['wave_transfer']['written']==2048:break
        action('wave_finish')
    for slot,patch in enumerate(before['slots']):
        if patch.get('native'):action('load_native',slot=slot,patch=patch['native'])
        else:action('load',slot=slot,program=patch['program'],operators=patch['operators'])
    for key,mapping in enumerate(before['keys']):
        patch=before['slots'][mapping['slot']]
        action('assign_key',key=key,scope='key',program=patch['program'],patch=patch.get('native'),operators=None if patch.get('native') else patch['operators'])
        action('configure_key',key=key,note=mapping['note'],velocity=mapping['velocity'])
    view=action('control',volume=before['volume'],sustain=False)
    assert view['keys']==before['keys']
    for old,new in zip(before['slots'],view['slots']):
        for key in ('program','native','operators'):assert old.get(key)==new.get(key)
    result['restored']=True
    print('PASS four patches, wave and all32 key mappings restored',flush=True)
    for voices in (1,8):
        for n in range(voices):action('note',token=f'hdmi-test-{n}',note=48+n*3,velocity=90,slot=n%4,pressed=True)
        time.sleep(.1)
        view=action('monitor_step')
        for _ in range(70):
            view=action('monitor_step')
            if view['monitor']['capture_progress']==512:break
        assert len(view['monitor']['samples'])==512 and max(map(abs,view['monitor']['samples']))>0
        result['audio'].append({'voices':voices,'peak':max(map(abs,view['monitor']['samples']))})
        action('panic');print('PASS simultaneous HDMI and audio',voices,'voices',flush=True)
    for page in range(6):
        action('hdmi_page',page=page)
        for _ in range(3):view=action('hdmi_step')
        assert view['hdmi']['page']==page
    action('hdmi_page',page=0)
    for _ in range(210):view=action('hdmi_step')
    for _ in range(9):view=action('poll')
    assert all(view['telemetry'][name]==0 for name in ('underruns','bad_packets','overruns','pcm_dropped'))
    assert not view['pending'] and view['retries']==0
    result.update(status='PASS',telemetry=view['telemetry'],hdmi=view['hdmi'],packets=view['packets'],retries=view['retries'])
    print('PASS all six pages, metadata, audio counters and CRC / zero retries',flush=True)
finally:
    try:action('disconnect')
    except Exception as error:result['disconnect_error']=str(error)
    process.stdin.close();process.wait(timeout=10);log.close()
    (REPORT/'board-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
