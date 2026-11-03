"""One-time integration of touch settings into the existing Rust engine and UI."""
from pathlib import Path
root=Path(__file__).resolve().parents[4]
p=root/'demo_test/desktop-tauri/src-tauri/src/voice_engine.rs'
s=p.read_text(encoding='utf-8')
def replace(a,b):
    global s
    assert a in s,a
    s=s.replace(a,b)
replace('use filter::{Filter,Profile as FilterProfile};','use filter::{Filter,Profile as FilterProfile};\n#[path="voice_touch.rs"]\nmod touch;\nuse touch::{Touch,Profile as TouchProfile};')
replace('Filter {profile:FilterProfile},','Filter {profile:FilterProfile},\n    Touch {profile:TouchProfile},')
replace('#[serde(default)] filter:Option<FilterProfile>,','#[serde(default)] filter:Option<FilterProfile>,\n    #[serde(default)] touch:Option<TouchProfile>,')
replace('keyboard:None,filter:None,','keyboard:None,filter:None,touch:None,')
replace('keyboard:Keyboard,filter:Filter,','keyboard:Keyboard,filter:Filter,touch:Touch,')
replace('filter:Filter::default()','filter:Filter::default(),touch:Touch::default()')
replace('filter:self.filter.clone(),','filter:self.filter.clone(),touch:self.touch.clone(),')
replace('let filter=self.saved.filter.clone();self.saved=Saved::default();self.saved.keyboard=keyboard;self.saved.filter=filter;','let filter=self.saved.filter.clone();let touch=self.saved.touch.clone();self.saved=Saved::default();self.saved.keyboard=keyboard;self.saved.filter=filter;self.saved.touch=touch;')
replace('self.discover_filter()?;','self.discover_filter()?;self.discover_touch()?;')
replace('Effect::Filter{profile}=>','Effect::Touch{profile}=>{self.saved.touch=Some(profile.clone());self.touch.profile=profile;},\n                Effect::Filter{profile}=>')
replace('Action::FilterApply{profile}=>','Action::TouchApply{profile}=>self.touch_apply(profile),Action::TouchStep=>self.touch_step(),\n                        Action::FilterApply{profile}=>')
replace('FilterStep,FilterApply{profile:FilterProfile},','FilterStep,FilterApply{profile:FilterProfile},\n    TouchStep,TouchApply{profile:TouchProfile},')
p.write_text(s,encoding='utf-8')
p=root/'demo1/desktop-tauri/src/useStudioEngine.ts';s=p.read_text(encoding='utf-8')
replace("import type {FilterView}","import type {TouchView} from './TouchSettings';\nimport type {FilterView}")
replace('filter?:FilterView','filter?:FilterView;touch?:TouchView')
replace('lastFilter=useRef(0);','lastFilter=useRef(0),lastTouch=useRef(0);')
replace("else if(now-lastPoll.current>220)","else if(v.touch?.available&&!v.keyboard?.calibration&&!v.wave_transfer&&now-lastTouch.current>350){lastTouch.current=now;void run({kind:'touch_step'},true).catch(()=>{});}\n   else if(now-lastPoll.current>220)")
p.write_text(s,encoding='utf-8')
p=root/'demo1/desktop-tauri/src/App.tsx';s=p.read_text(encoding='utf-8')
replace("import {MasterFilter}","import {TouchSettings,TouchStatus} from './TouchSettings';\nimport {MasterFilter}")
replace("{page==='status'&&<StatusDashboard", "{page==='status'&&<TouchStatus view={view}/>}\n {page==='status'&&<StatusDashboard")
replace("{page==='device'&&<KeyboardSettings", "{page==='device'&&<TouchSettings view={view} run={run} busy={busy} onError={catchError}/>}\n {page==='device'&&<KeyboardSettings")
p.write_text(s,encoding='utf-8')
