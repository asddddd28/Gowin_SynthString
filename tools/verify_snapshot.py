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
    # Current comprehensive firmware has a newer preflight than the retained
    # historical HDMI 89B5 report. Check its own source and artifact fingerprints.
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
            if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != expected:
                errors.append(f'Current firmware source fingerprint mismatch: {original}')
    app = ROOT / 'Gowin/demo_test/desktop-tauri'
    release = json.loads((app / 'reports/buttons-release.json').read_text(encoding='utf-8'))
    if hashlib.sha256((app / release['artifact']).read_bytes()).hexdigest() != release['sha256']:
        errors.append('App release fingerprint mismatch')
    if errors:
        raise SystemExit('\n'.join(errors))
    print(f'PASS: {len(entries)} file checksums, {projects} project dependency lists, current firmware/App and historical audio fingerprints.')

if __name__ == '__main__':
    main()
