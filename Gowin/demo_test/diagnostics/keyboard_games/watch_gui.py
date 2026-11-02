"""Save App diagnostics during operator interaction; never opens the COM port."""
import json,time
from pathlib import Path
folder=Path(__file__).resolve().parent/'reports'
previous=None
with (folder/'gui_physical_session.jsonl').open('a',encoding='utf-8') as target:
    deadline=time.monotonic()+180
    while time.monotonic()<deadline:
        try:
            data=json.loads((folder/'gui_live.json').read_text(encoding='utf-8'))
            if data!=previous:
                target.write(json.dumps(dict(time=time.time(),state=data),ensure_ascii=False)+'\n');target.flush();previous=data
        except (OSError,ValueError):pass
        time.sleep(.25)
print('Saved GUI observations for physical test')
