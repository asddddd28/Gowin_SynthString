"""Exercise RGB through the App UART owner, then capture 1/8-voice PCM.

Run after programming and restoring the session. Does not write the SD card.
Use --rgb-only while validating the hardware control endpoint.
"""
from pathlib import Path
import json
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'reports/keyboard-rgb/board'
PROBE = ROOT.parent / 'desktop-tauri/src-tauri/target/debug/voice-workspace-probe.exe'
process = subprocess.Popen([str(PROBE), '--keep-audio'], stdin=subprocess.PIPE,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8')
log = (OUT/'rgb-audio-actions.jsonl').open('w', encoding='utf-8')
result = {'ok': False, 'physical_led_confirmation': False, 'modes': [], 'audio': []}
owned = []

def action(kind, **values):
    request = dict(kind=kind, **values)
    process.stdin.write(json.dumps(request)+'\n'); process.stdin.flush()
    line = process.stdout.readline()
    if not line:
        raise RuntimeError(process.stderr.read())
    reply = json.loads(line)
    log.write(json.dumps(dict(request=request, response=reply), ensure_ascii=False)+'\n'); log.flush()
    if not reply['ok']:
        raise RuntimeError(reply['error'])
    return reply['view']

def discover():
    view = action('connect', port='COM4', fresh=False)
    for _ in range(3):
        view = action('hdmi_step')
    assert view['hdmi']['rgb_available'] is True
    return view

try:
    view = discover()
    assert not view['sequencer']['recording'] and not view['sequencer']['playing']
    before = {k:view[k] for k in ('slots','keys','volume','wave_name','wave_morph')}
    # Reconnect to force actual RTL readback, rather than inspecting cached state.
    for mode, direction in [(0,False),(1,False),(2,False),(3,False),(3,True),(4,False),(6,False)]:
        action('hdmi_rgb', mode=mode, direction=direction)
        action('disconnect')
        view = discover()
        assert view['hdmi']['rgb_mode'] == mode and view['hdmi']['rgb_direction'] == direction
        result['modes'].append(dict(mode=mode, direction=direction, readback=True))
    view = action('storage_step')
    assert view['storage']['available'] is False and not view['storage']['service']
    if '--rgb-only' not in sys.argv:
        # Restored slot 2 is sustained sine bass; rainbow runs throughout PCM test.
        assert view['slots'][1]['native']['name'] == '正弦贝斯'
        for count in (1,8):
            stamp = view['monitor']['captured_at_ms']
            for n in range(count):
                token = f'rgb-smoke-{n}'
                action('note', token=token, note=48+n*3, velocity=80, slot=1, pressed=True)
                owned.append((token,48+n*3))
            for _ in range(140):
                view = action('monitor_step')
                m = view['monitor']
                if m['captured_at_ms'] != stamp and m['capture_progress'] == 512:
                    break
            samples = m['samples']
            assert m['captured_at_ms'] != stamp and len(samples) == 512 and max(map(abs,samples))>0
            result['audio'].append(dict(voices=count,peak_pcm=max(map(abs,samples)),monitor=m))
            print('PASS RGB active, PCM',count,'voices, peak',max(map(abs,samples)),flush=True)
            for token,note in list(owned):
                action('note',token=token,note=note,velocity=80,slot=1,pressed=False)
                owned.remove((token,note))
            time.sleep(.3)
    action('hdmi_rgb',mode=1,direction=False)
    for _ in range(9):
        view = action('poll')
    assert all(view['telemetry'][k]==0 for k in ('underruns','overruns','bad_packets','pcm_dropped'))
    assert view['retries']==0 and not view['pending']
    assert {k:view[k] for k in before} == before
    result.update(ok=True,telemetry=view['telemetry'],retries=view['retries'],settings_unchanged=True)
    print('PASS all RGB modes/readback, SD disabled, zero audio/serial faults',flush=True)
finally:
    for token,note in owned:
        try: action('note',token=token,note=note,velocity=80,slot=1,pressed=False)
        except Exception as error: result['release_error']=str(error)
    process.stdin.close(); process.wait(timeout=15); log.close()
    (OUT/'rgb-audio-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
