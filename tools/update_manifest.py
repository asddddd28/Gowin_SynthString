"""Record tracked files plus this explicitly selected final-release export."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT=Path(__file__).resolve().parents[1]
names=subprocess.check_output(['git','ls-files','-z','--cached','--others','--exclude-standard'],cwd=ROOT).decode('utf-8').split('\0')
entries=[]
for name in sorted(set(names)):
    if not name or name=='UPLOAD_MANIFEST.json':continue
    path=ROOT/name
    if not path.is_file():continue
    assert not set(x.lower() for x in path.relative_to(ROOT).parts)&{'reference','material','materials','project-backups','node_modules','target','__pycache__','.venv'},name
    data=path.read_bytes()
    assert len(data)<40_000_000,name
    entries.append(dict(path=name,category='project_snapshot',bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
(ROOT/'UPLOAD_MANIFEST.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'Manifest: {len(entries)} files, {sum(e["bytes"] for e in entries)/1048576:.1f} MiB')
