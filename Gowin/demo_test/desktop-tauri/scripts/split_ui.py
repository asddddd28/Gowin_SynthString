"""Split the initial UI implementation into independently maintained pages."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]/'src'
source=(root/'main.tsx').read_text(encoding='utf8')
icons=re.search(r'import \{([^}]+)\} from "lucide-react";',source,re.S).group(1).replace('\n','').split(',')
icons=[s.strip() for s in icons if s.strip()]
types=['EncoderState','Page','Port','Settings','Snapshot']
helpers=['NAV','EFFECTS','NOTES','fmt','keyName','bytes','Act','Props']
components=['Badge','CardHead','Switch','Metric','Matrix','Chart','Knob','JoystickShape','PadSurface']
def header(body,sub=False,common=True,comps=True):
    pre='../' if sub else './'
    lines=[]
    hooks=[name for name in ['useEffect','useRef','useState'] if re.search(r'\b'+name+r'\b',body)]
    if hooks or 'React.' in body:
        imports=('React' if 'React.' in body else '')
        if hooks: imports+=(', ' if imports else '')+'{ '+', '.join(hooks)+' }'
        lines.append(f'import {imports} from "react";')
    used=[name for name in icons if re.search(r'\b'+name+r'\b',body)]
    if used:lines.append('import { '+', '.join(used)+' } from "lucide-react";')
    used=[name for name in types if re.search(r'\b'+name+r'\b',body)]
    if used:lines.append('import type { '+', '.join(used)+' } from "'+pre+'types";')
    if common:
        used=[name for name in helpers if re.search(r'\b'+name+r'\b',body)]
        if used:lines.append('import { '+', '.join(used)+' } from "'+pre+'config";')
    if comps:
        used=[name for name in components if re.search(r'\b'+name+r'\b',body)]
        if used:lines.append('import { '+', '.join(used)+' } from "'+pre+'components";')
    return '\n'.join(lines)+'\n\n'
config=source[source.index('const NAV:'):source.index('function Badge(')]
config=re.sub(r'(?m)^(const |type )',r'export \1',config)
(root/'config.ts').write_text(header(config,common=False,comps=False)+config,encoding='utf8')
ui=source[source.index('function Badge('):source.index('function Overview(')]
# Empty was a scaffold placeholder, not an active view.
ui=ui[:ui.index('function Empty(')]+ui[ui.index('function CardHead('):]
ui=re.sub(r'(?m)^function ',r'export function ',ui)
(root/'components.tsx').write_text(header(ui,comps=False)+ui,encoding='utf8')
pages=[('Overview','function Overview(','function KeyboardPage('),('KeyboardPage','function KeyboardPage(','function EncodersPage('),('EncodersPage','function EncodersPage(','function JoystickPage('),('JoystickPage','function JoystickPage(','function PadMappingControls('),('TouchpadPage','function PadMappingControls(','function GuitarPage('),('GuitarPage','function GuitarPage(','const GAME_NAMES'),('GamesPage','const GAME_NAMES','function App(')]
(root/'pages').mkdir(exist_ok=True)
for name,start,end in pages:
    body=source[source.index(start):source.index(end)]
    body=body.replace('function '+name+'(', 'export function '+name+'(',1)
    (root/'pages'/f'{name}.tsx').write_text(header(body,sub=True)+body,encoding='utf8')
body=source[source.index('function App('):source.index('createRoot(')]
body=body.replace('function App(', 'export default function App(',1)
imports='import { invoke } from "@tauri-apps/api/core";\n'
imports+='\n'.join(f'import {{ {name} }} from "./pages/{name}";' for name,_,_ in pages)+'\n'
(root/'App.tsx').write_text(header(body,comps=False)+imports+body,encoding='utf8')
(root/'main.tsx').write_text('import { createRoot } from "react-dom/client";\nimport App from "./App";\nimport "./style.css";\ncreateRoot(document.getElementById("root")!).render(<App/>);\n',encoding='utf8')
print('Extracted shared components and seven feature pages.')
