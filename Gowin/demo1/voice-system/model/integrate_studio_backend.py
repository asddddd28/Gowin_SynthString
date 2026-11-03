from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
relative='demo_test/desktop-tauri/src-tauri/src/voice_engine.rs'
p=ROOT.parents[1]/relative
text=(ROOT/'reports/unified-studio/before'/relative).read_text(encoding='utf-8')
replacements=[
('pub use native::{NativePatch,compile_native};','pub use native::{NativePatch,compile_native};\n#[path="voice_workspace.rs"]\nmod workspace;\nuse workspace::{KeyMapping,MonitorView,default_keys};'),
('WaveStopped, WaveAdvance { next:usize }, WaveFinished,','WaveStopped, WaveAdvance { next:usize }, WaveFinished,\n    Key { key:u8,value:KeyMapping },'),
('next_sequence: u32, next_note: u32, pending: Option<Pending>, slots: [Slot; 4],','next_sequence: u32, next_note: u32, pending: Option<Pending>, slots: [Slot; 4],\n    #[serde(default="default_keys")] keys:Vec<KeyMapping>,'),
('next_sequence: 0, next_note: 1, pending: None, slots: Default::default(),','next_sequence: 0, next_note: 1, pending: None, slots: Default::default(),keys:default_keys(),'),
('pub fx_available: bool,','pub fx_available: bool,\n    keys:Vec<KeyMapping>,monitor:MonitorView,'),
('fx_available: bool,\n    serial: SerialDiagnostics,','fx_available: bool,\n    monitor:MonitorView,capture_chunk:Option<u8>,capture_samples:Vec<i16>,\n    serial: SerialDiagnostics,'),
('kind > 2','kind > 3'),
('error:String::new(),fx_available:false,serial:','error:String::new(),fx_available:false,monitor:MonitorView::default(),capture_chunk:None,capture_samples:Vec::new(),serial:'),
('fx_available:self.fx_available,serial:','fx_available:self.fx_available,keys:self.saved.keys.clone(),monitor:self.monitor.clone(),serial:'),
('self.fx_available=self.read(0x4c)?!=0;','self.fx_available=self.read(0x4c)?!=0;\n        self.discover_workspace()?;'),
('Effect::None=>{}, Effect::Slot','Effect::Key{key,value}=>self.saved.keys[key as usize]=value,\n                Effect::None=>{}, Effect::Slot'),
('self.poll_index=(self.poll_index+1)%addresses.len();Ok(())','self.poll_index=(self.poll_index+1)%addresses.len();self.poll_monitor()?;Ok(())'),
('Action::Poll=>self.poll(),','''Action::Poll=>self.poll(),
                        Action::MonitorStep=>self.capture_step(),
                        Action::ConfigureKey{key,note,velocity}=>self.configure_key(key,note,velocity),
                        Action::AssignKey{key,scope,program,patch,operators}=>self.assign_key(key,scope,program,patch,operators),'''),
('Connect{port:String,fresh:bool},Disconnect,Recover,Poll,Panic,','''Connect{port:String,fresh:bool},Disconnect,Recover,Poll,Panic,MonitorStep,
    ConfigureKey{key:u8,note:u8,velocity:u8},
    AssignKey{key:u8,scope:String,program:Option<u8>,patch:Option<NativePatch>,operators:Option<Vec<Operator>>},'''),
]
for old,new in replacements:
    assert old in text,old
    text=text.replace(old,new,1)
p.write_text(text,encoding='utf-8')
print('Integrated durable key mapping and monitor acquisition')
