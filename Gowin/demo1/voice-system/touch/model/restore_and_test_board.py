"""Restore the immutable pre-update user session and exercise real hardware."""
from pathlib import Path
import json,subprocess,sys,time,math
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'reports/touch-performance';APP=ROOT.parent/'desktop-tauri'
before=json.loads((OUT/'before-board/session-COM4.json').read_text(encoding='utf-8'))
process=subprocess.Popen([str(APP/'src-tauri/target/debug/voice-workspace-probe.exe')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
log=(OUT/'board-actions.jsonl').open('a',encoding='utf-8')
def action(kind,**values):
 request=dict(kind=kind,**values);process.stdin.write(json.dumps(request)+'\n');process.stdin.flush()
 line=process.stdout.readline()
 if not line:raise RuntimeError(process.stderr.read())
 r=json.loads(line);log.write(json.dumps({'request':request,'response':r},ensure_ascii=False)+'\n');log.flush()
 if not r['ok']:raise RuntimeError(r['error'])
 return r['view']
def source_wave(name):
 helper=subprocess.Popen([str(APP/'src-tauri/target/debug/studio-test-harness.exe'),str(APP/'src-tauri/assets'),str(OUT/'asset-probe-config.json')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,encoding='utf-8')
 def call(method,params={}):
  helper.stdin.write(json.dumps(dict(method=method,params=params))+'\n');helper.stdin.flush();r=json.loads(helper.stdout.readline());assert r['ok'],r;return r['result']
 try:
  sound=next(s for s in call('bank_catalog') if s['title']==name)
  return call('voice_preset_wave',{'timbre_id':sound['id']})
 finally:helper.stdin.close();helper.wait(timeout=10)
def capture():
 view=action('monitor_step')
 for _ in range(85):
  view=action('monitor_step')
  if view['monitor']['capture_progress']==512:break
 samples=view['monitor']['samples'];assert len(samples)==512
 return {'peak':max(map(abs,samples)),'rms':math.sqrt(sum(x*x for x in samples)/len(samples))}
result={'status':'running'};touch=None
try:
 view=action('connect',port='COM4',fresh='--fresh' in sys.argv);assert view['abi']==0x10007 and view['touch']['available']
 action('panic');print('PASS ABI1.7 touch capability',flush=True)
 if before.get('wave_name'):
  asset=source_wave(before['wave_name']);action('wave_begin',name=asset['name'],samples=asset['samples'],morph=before.get('wave_morph',0))
  while True:
   view=action('wave_step');written=view['wave_transfer']['written']
   if written%256==0:print('Restore wave',written,'/2048',flush=True)
   if written==2048:break
  action('wave_finish')
 for slot,p in enumerate(before['slots']):
  if p.get('native'):action('load_native',slot=slot,patch=p['native'])
  else:action('load',slot=slot,program=p['program'],operators=p['operators'])
 for key,m in enumerate(before['keys']):
  p=before['slots'][m['slot']]
  action('assign_key',key=key,scope='key',program=p['program'],patch=p.get('native'),operators=None if p.get('native') else p['operators'])
  view=action('configure_key',key=key,note=m['note'],velocity=m['velocity'])
 assert view['keys']==before['keys']
 for a,b in zip(before['slots'],view['slots']):
  for field in ['native','program','operators']:assert a.get(field)==b.get(field),(field,a,b)
 if before.get('keyboard'):
  p=before['keyboard'];view=action('keyboard_apply',**{k:p[k] for k in ['release','press','sensitivity','velocity_enabled','velocity_ceiling']});assert view['keyboard']['profile']['keys']==p['keys']
 if before.get('filter'):view=action('filter_apply',profile=before['filter']);assert view['filter']['applied']
 view=action('control',volume=before['volume'],sustain=False)
 touch=before.get('touch') or view['touch']['profile'];view=action('touch_apply',profile=touch)
 result['restored']=True;print('PASS user four patches,32 maps,keyboard calibration,filter,wave,volume restored',flush=True)
 initial=action('keyboard_step')['keyboard']['scans'];time.sleep(.12);view=action('keyboard_step');assert view['keyboard']['scans']>initial
 result['raw_adc']=view['keyboard']['raw'];result['keyboard']=view['keyboard']['profile']
 result['modes']=[]
 for mode in range(4):
  view=action('touch_apply',profile={**touch,'mode':mode});assert view['touch']['mode']==mode and view['touch']['applied']
  time.sleep(.08);view=action('touch_step');result['modes'].append(view['touch'])
  if not view['touch']['touching']:
   assert abs(view['touch']['gain']-1)<.001 and abs(view['touch']['pitch_semitones'])<.001 and abs(view['touch']['cutoff_octaves'])<.001
 action('touch_apply',profile=touch)
 result['audio']=[]
 for voices in [1,8]:
  for n in range(voices):action('note',token=f'touch-test-{n}',note=48+n*3,velocity=90,slot=n%4,pressed=True)
  time.sleep(.04);audio=capture();assert audio['peak']>0;result['audio'].append({'voices':voices,**audio});action('panic');print('PASS live PCM',voices,'voices',audio,flush=True)
 for _ in range(9):view=action('poll')
 view=action('touch_step');result['touch']=view['touch'];result['telemetry']=view['telemetry'];result['retries']=view['retries'];result['packets']=view['packets']
 assert all(view['telemetry'][name]==0 for name in ['underruns','bad_packets','overruns','pcm_dropped'])
 assert not view['pending'] and view['retries']==0
 assert view['touch']['errors']==[0,0],view['touch']
 result['status']='PASS';print('PASS dual MPR connected, four mode ACK/readback, neutral release, zero audio/serial faults',flush=True)
finally:
 try:
  action('panic')
  if touch:action('touch_apply',profile=touch)
  action('control',volume=before['volume'],sustain=before['sustain'])
  view=action('hdmi_step');result['final_view']=view
  action('disconnect')
 except Exception as error:result['cleanup_error']=str(error)
 process.stdin.close();process.wait(timeout=10);log.close()
 (OUT/'board-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
