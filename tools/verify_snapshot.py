"""Read-only checksum and project dependency checks; never accesses the board."""
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = 'D:/Projects/ai/'

def exported_path(path, base):
    path = path.replace('\\', '/')
    if path.lower().startswith(ORIGINAL.lower()):
        return ROOT / path[len(ORIGINAL):]
    return base / path

def main():
    entries = json.loads((ROOT / 'UPLOAD_MANIFEST.json').read_text(encoding='utf-8'))
    errors = []
    projects = 0
    for entry in entries:
        path = ROOT / entry['path']
        if not path.is_file():
            errors.append('Missing: ' + entry['path'])
            continue
        data = path.read_bytes()
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            errors.append('Checksum mismatch: ' + entry['path'])
        if path.suffix == '.gprj':
            projects += 1
            for node in ET.parse(path).iter('File'):
                dependency = exported_path(node.attrib['path'], path.parent)
                if not dependency.is_file():
                    errors.append(f"Missing dependency in {entry['path']}: {node.attrib['path']}")
    for report in [
        'Gowin/demo1/keyboard-latency/reports/latency_supervisor.json',
        'Gowin/demo1/keyboard-latency/reports/latency_keyboard_audio.json',
    ]:
        content = json.loads((ROOT / report).read_text(encoding='utf-8'))
        fingerprints = content.get('source_sha256', content)
        for original, expected in fingerprints.items():
            path = exported_path(original, ROOT)
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                errors.append(f'Historical source fingerprint mismatch: {original}')
    # Retained hardware-lab artifacts predate the final RGB release. Preserve
    # their original scanner separately instead of checking a newer shared file.
    historical_sources = {
        'Gowin/demo_test/diagnostics/touchpad_guitar/src/MprScanner.v':
            ROOT / 'Gowin/demo_test/diagnostics/hardware_lab/reports/buttons_merge/source/MprScanner.v',
    }
    integrated = json.loads((ROOT / 'Gowin/demo_test/diagnostics/hardware_lab/reports/buttons_merge/preflight.json').read_text(encoding='utf-8'))
    standalone = json.loads((ROOT / 'Gowin/demo_test/diagnostics/tactile_buttons/reports/preflight.json').read_text(encoding='utf-8'))
    builds = [integrated['hardware_lab'], integrated['hardware_hdmi'], standalone]
    standalone['bitstream'] = 'Gowin/demo_test/diagnostics/tactile_buttons/impl/pnr/tactile_buttons.fs'
    for build in builds:
        artifact = exported_path(build['bitstream'], ROOT)
        if not artifact.is_file() or hashlib.sha256(artifact.read_bytes()).hexdigest() != build['bitstream_sha256']:
            errors.append(f'Firmware fingerprint mismatch: {artifact}')
        for original, expected in build['source_sha256'].items():
            source = exported_path(original, ROOT)
            source = historical_sources.get(source.relative_to(ROOT).as_posix(), source)
            if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != expected:
                errors.append(f'Historical hardware-lab source fingerprint mismatch: {original}')
    app = ROOT / 'Gowin/demo_test/desktop-tauri'
    release = json.loads((app / 'reports/buttons-release.json').read_text(encoding='utf-8'))
    if hashlib.sha256((app / release['artifact']).read_bytes()).hexdigest() != release['sha256']:
        errors.append('App release fingerprint mismatch')
    # The Nov 2 candidate remains explicitly unqualified historical evidence.
    voice = ROOT / 'Gowin/demo1/voice-system'
    snapshot = json.loads((voice / 'reports/release/snapshot.json').read_text(encoding='utf-8'))
    timing = json.loads((voice / 'reports/gowin-board-summary.json').read_text(encoding='utf-8'))
    if snapshot['status'] != 'simulation_passed_timing_failed_not_programmed' or snapshot['hardware_tested']:
        errors.append('Candidate qualification status changed unexpectedly')
    if timing['clean'] or not timing['timing']['violations'] or timing['timing']['fmax'][0]['constraintMhz'] != 50:
        errors.append('Candidate timing evidence inconsistent')
    artifact = ROOT / snapshot['bitstream']
    if hashlib.sha256(artifact.read_bytes()).hexdigest() != snapshot['bitstream_sha256']:
        errors.append('Candidate firmware fingerprint mismatch')
    if hashlib.sha256((voice / 'app/SynthStringVoiceStudio.exe').read_bytes()).hexdigest() != snapshot['app_sha256']:
        errors.append('Voice Studio fingerprint mismatch')
    # The Nov 2 candidate and its artifact remain historical evidence. Active
    # source now belongs to the final RGB release, so validate its own manifest.
    release = json.loads((ROOT/'FINAL_RELEASE.json').read_text(encoding='utf-8'))
    if release['status']!='final_timing_passed_sram_tested' or release['clock_hz']!=50_000_000:
        errors.append('Final qualification or clock changed unexpectedly')
    if release['sd_enabled'] or release['fx_enabled'] or release['flash_written']:
        errors.append('Final build feature/programming profile mismatch')
    for key in ['bitstream','app']:
        p=ROOT/release[key]
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=release[key+'_sha256']:
            errors.append('Final artifact fingerprint mismatch: '+key)
    for rel, expected in release['source_sha256'].items():
        source = ROOT/rel
        if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest()!=expected:
            errors.append('Final source fingerprint mismatch: '+rel)
    for info in release['constraints'].values():
        if hashlib.sha256((ROOT/info['path']).read_bytes()).hexdigest()!=info['sha256']:
            errors.append('Final constraint fingerprint mismatch: '+info['path'])
    for rel in release['rtl_sources']:
        if not (ROOT/rel).is_file():errors.append('Missing final RTL: '+rel)
    timing=json.loads((ROOT/release['timing_report']).read_text(encoding='utf-8'))
    if not timing['clean'] or timing['timing']['violations'] or any(c['failing'] for c in timing['timing']['fmax']):
        errors.append('Final timing did not close')
    verification=json.loads((ROOT/release['verification']).read_text(encoding='utf-8'))
    if verification['board']['retries'] or any(verification['board']['telemetry'][k] for k in ['underruns','overruns','bad_packets','pcm_dropped']):
        errors.append('Final board transport/audio faults')
    if errors:
        raise SystemExit('\n'.join(errors))
    print(f'PASS: {len(entries)} file checksums, {projects} project dependency lists, final RGB source/constraints/firmware/App and retained historical artifacts.')

if __name__ == '__main__':
    main()
