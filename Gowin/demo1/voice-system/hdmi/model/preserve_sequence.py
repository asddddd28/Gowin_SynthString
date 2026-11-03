"""Back up and restore ARC1 RAM loops across a display-only SRAM update.

Requires exclusive COM4. Never stop an active recording or replace a nonempty
sequence. Timbres, mappings and waveform must be restored before --restore.
"""
import argparse
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT.parent/'desktop-tauri/src-tauri/target/debug/voice-workspace-probe.exe'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('backup', 'restore', 'verify'))
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    out = args.directory.resolve()
    out.mkdir(parents=True, exist_ok=True)
    image_path = out/'sequence-before.json'
    if args.mode == 'backup' and image_path.exists():
        raise RuntimeError('Existing backup must not be overwritten')
    process = subprocess.Popen([str(PROBE),'--keep-audio'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, encoding='utf-8')
    log = (out/f'sequence-{args.mode}-actions.jsonl').open('a', encoding='utf-8')
    result = {'ok': False, 'mode': args.mode}

    def action(kind, **values):
        request = dict(kind=kind, **values)
        process.stdin.write(json.dumps(request)+'\n')
        process.stdin.flush()
        line = process.stdout.readline()
        if not line:
            raise RuntimeError(process.stderr.read())
        reply = json.loads(line)
        log.write(json.dumps(dict(request=request,response=reply),ensure_ascii=False)+'\n')
        log.flush()
        if not reply['ok']:
            raise RuntimeError(reply['error'])
        return reply['view']

    try:
        view = action('connect', port='COM4', fresh=False)
        # HDMI discovery is lazy; connect alone leaves available/page unset.
        for _ in range(4):
            view = action('hdmi_step')
        assert view['hdmi']['available'] and view['hdmi']['page_count'] == 8
        s = view['sequencer']
        if not s['archive_available'] or s['recording'] or s['finalizing'] or s['archive_busy']:
            raise RuntimeError('Requires ARC1 and stopped recording; existing take was not changed')
        if args.mode == 'backup':
            playing = s['playing']
            if playing:
                action('sequencer_control', action=3, bpm=None)
                time.sleep(.15)
            view = action('sequence_export')
            image = view['sequencer']['event_image']
            assert image is not None
            snapshot = dict(image=image, was_playing=playing, page=view['hdmi']['page'],
                            settings={k:view[k] for k in ('slots','keys','volume','wave_name','wave_morph')})
            image_path.write_text(json.dumps(snapshot,ensure_ascii=False,indent=2),encoding='utf-8')
            assert json.loads(image_path.read_text(encoding='utf-8')) == snapshot
            result.update(events=len(image['events']), loop_ticks=image['loop_ticks'])
        elif args.mode == 'restore':
            snapshot = json.loads(image_path.read_text(encoding='utf-8'))
            if s['events'] or s['loop_ticks'] or s['playing']:
                raise RuntimeError('Refusing to replace a nonempty sequence')
            # Revision numbers change after programming; actual timbre content must match.
            expected = snapshot['settings']
            assert view['keys'] == expected['keys']
            for old, new in zip(expected['slots'], view['slots']):
                for field in ('native','program','operators'):
                    assert old.get(field) == new.get(field), field
            assert all(view[k] == expected[k] for k in ('volume','wave_name','wave_morph'))
            action('sequence_import', image=snapshot['image'])
            view = action('sequence_export')
            assert view['sequencer']['event_image'] == snapshot['image']
            result.update(roundtrip_exact=True, events=len(snapshot['image']['events']))
        else:
            snapshot = json.loads(image_path.read_text(encoding='utf-8'))
            original_page = snapshot['page']
            for page in range(8):
                action('hdmi_page', page=page)
                for _ in range(3):
                    view = action('hdmi_step')
                assert view['hdmi']['page'] == page
            action('hdmi_page', page=original_page)
            if snapshot['was_playing'] and not view['sequencer']['playing']:
                action('sequencer_control', action=3, bpm=None)
            for _ in range(9):
                view = action('poll')
            assert all(view['telemetry'][k] == 0 for k in ('underruns','overruns','bad_packets','pcm_dropped'))
            assert not view['pending'] and view['retries'] == 0
            result.update(pages=8, telemetry=view['telemetry'], retries=view['retries'],
                          resumed=snapshot['was_playing'])
        result['ok'] = True
        print('PASS', args.mode, result, flush=True)
    finally:
        # This helper never owns test notes. Drop COM4 without panicking a resumed loop.
        process.stdin.close()
        process.wait(timeout=15)
        log.close()
        (out/f'sequence-{args.mode}-result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')


if __name__ == '__main__':
    main()
