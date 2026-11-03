"""独占真实 COM4 验证事件导入/导出和 PCM；不会覆盖已有录音。

仅在 App 已断开、当前固件支持 ARC1 时手动运行。合成测试音，
验证后清除本脚本创建的测试循环，保留全部音色和按键设置。
"""
from pathlib import Path
import json
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'reports/sequencer/archive-board-20261103'
PROBE = ROOT.parent/'desktop-tauri/src-tauri/target/debug/voice-workspace-probe.exe'


def main():
    OUT.mkdir(exist_ok=True)
    target = OUT/'hardware-archive-result.json'
    if target.exists():
        raise RuntimeError('证据已存在，请使用新的测试目录')
    process = subprocess.Popen([str(PROBE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, encoding='utf-8')
    log = (OUT/'hardware-archive-actions.jsonl').open('w', encoding='utf-8')
    report = {'ok':False, 'physical_keyboard_test':False}
    created = False
    connected = False

    def action(kind, **values):
        request = dict(kind=kind, **values)
        process.stdin.write(json.dumps(request)+'\n')
        process.stdin.flush()
        line = process.stdout.readline()
        if not line:
            raise RuntimeError('探针退出：'+process.stderr.read())
        result = json.loads(line)
        log.write(json.dumps(dict(request=request, response=result), ensure_ascii=False)+'\n')
        log.flush()
        if not result['ok']:
            raise RuntimeError(result['error'])
        return result['view']

    try:
        view = action('connect', port='COM4', fresh=False)
        connected = True
        s = view['sequencer']
        if not s['archive_available'] or s['recording'] or s['playing'] or s['events'] or s['loop_ticks']:
            raise RuntimeError('要求 ARC1 固件及空工作区；未修改现有音序')
        before = {k:view[k] for k in ('slots','keys','volume','wave_name','wave_morph')}
        events = []
        for key, tick, note in ((0,0,48), (1,960,55)):
            slot = view['keys'][key]['slot']
            phase = round(2**32*440*2**((note-69)/12)/(50_000_000/1024))
            anchor = len(events)
            on = tick | anchor<<20 | phase<<30 | 90<<62 | note<<69 | slot<<76 | 1<<78 | 1<<79 | key<<80
            off = (tick+600) | anchor<<20 | key<<80
            events.extend([[value&0xffffffff,(value>>32)&0xffffffff,value>>64] for value in (on,off)])
        image = dict(ppq=960, bpm=120, loop_ticks=3840, events=events)
        action('sequence_import', image=image)
        created = True
        view = action('sequence_export')
        assert view['sequencer']['event_image'] == image
        report['roundtrip_exact'] = True
        action('sequencer_control', action=3, bpm=None)
        begin = time.monotonic()
        peak = 0
        generations = set()
        wraps = 0
        previous = 0
        while time.monotonic()-begin < 7:
            view = action('monitor_step')
            peak = max(peak, max(map(abs, view['monitor']['samples']), default=0))
            generations.add(view['monitor']['generation'])
            view = action('sequencer_step')
            position = view['sequencer']['position']
            if position < previous:
                wraps += 1
            previous = position
            if view['sequencer']['fault']:
                raise RuntimeError('回放 fault')
        action('sequencer_control', action=3, bpm=None)
        for _ in range(9):
            view = action('poll')
        assert peak > 0 and wraps >= 2, (peak,wraps)
        assert all(view['telemetry'][k] == 0 for k in ('underruns','bad_packets','overruns','pcm_dropped'))
        assert view['retries'] == 0 and not view['pending']
        assert {k:view[k] for k in before} == before
        report.update(ok=True, peak_pcm=peak, loop_wraps=wraps, pcm_generations=len(generations),
                      telemetry=view['telemetry'], retries=view['retries'], image=image,
                      settings_unchanged=True)
        print('PASS hardware archive roundtrip, restored loop PCM, zero audio/serial faults', flush=True)
    except BaseException as error:
        report['error'] = repr(error)
        raise
    finally:
        if created:
            try:
                action('sequencer_control', action=2, bpm=None)
                report['test_loop_cleared'] = True
            except Exception as error:
                report['cleanup_error'] = str(error)
        if connected:
            try:
                action('disconnect')
            except Exception as error:
                report['disconnect_error'] = str(error)
        target.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        log.close()
        process.stdin.close()
        process.wait(timeout=10)


if __name__ == '__main__':
    main()
