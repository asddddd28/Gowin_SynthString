import { useCallback, useEffect, useRef, useState } from 'react';
import { Activity, AudioLines, Cable, Check, ChevronRight, CircleHelp, Cpu, Download, FolderOpen, Headphones, Keyboard, Library, Link2, LoaderCircle, Music2, Power, Radio, RefreshCw, Save, Search, Settings2, SlidersHorizontal, Square, Upload, Waves, X } from 'lucide-react';
import { request, chooseFile } from './api';
import { Envelope, Modal, Parameter, ParameterControls, Toggle, Waveform } from './components';
import { PerformanceControls } from './PerformanceControls';
import { MODES, WAVES, noteName } from './types';
import type { Config, KeyPatch, MidiPort, PairPreview, Profile, Resource, Snapshot, Sound, StudioState, Timbre } from './types';

type Page = 'design' | 'library' | 'waves' | 'surge' | 'device';
const pages = [
  { id: 'design' as const, title: '声音设计', subtitle: 'SOUND DESIGN', icon: SlidersHorizontal },
  { id: 'library' as const, title: '音色浏览器', subtitle: 'PRESET LIBRARY', icon: Library },
  { id: 'waves' as const, title: '波表工坊', subtitle: 'WAVETABLE LAB', icon: Waves },
  { id: 'surge' as const, title: 'Surge 桥接', subtitle: 'SURGE BRIDGE', icon: Link2 },
  { id: 'device' as const, title: '设备与输出', subtitle: 'DEVICE & OUTPUT', icon: Settings2 },
];

export default function App() {
  const [state, setState] = useState<StudioState | null>(null);
  const [bank, setBank] = useState<Timbre[]>([]);
  const [ports, setPorts] = useState<{ device: string; description: string }[]>([]);
  const [port, setPort] = useState('');
  const [page, setPage] = useState<Page>('design');
  const [selected, setSelected] = useState(0);
  const [draft, setDraft] = useState<KeyPatch | null>(null);
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState('全部');
  const [envelopeTab, setEnvelopeTab] = useState(false);
  const [modulationOpen, setModulationOpen] = useState(false);
  const [keyboard, setKeyboard] = useState(true);
  const [capture, setCapture] = useState(false);
  const [pressed, setPressed] = useState<number[]>([]);
  const [error, setError] = useState('');
  const [working, setWorking] = useState(false);
  const [help, setHelp] = useState(false);
  const [confirm, setConfirm] = useState<{ title: string; description: string; action: () => void } | null>(null);
  const [resources, setResources] = useState<Resource[]>([]);
  const [resourceId, setResourceId] = useState(0);
  const [position, setPosition] = useState(0);
  const [pair, setPair] = useState<PairPreview | null>(null);
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [scene, setScene] = useState('a');
  const [surgePorts, setSurgePorts] = useState([53280, 53281]);
  const [output, setOutput] = useState({ volume: 25, boost: 0 });
  const [template, setTemplate] = useState<Sound | null>(null);
  const [controlStyle,setControlStyle]=useState<'knob'|'slider'>(()=>localStorage.getItem('tang.controls')==='slider'?'slider':'knob');
  const [midiPorts,setMidiPorts]=useState<MidiPort[]>([]),[midiId,setMidiId]=useState(-1);
  const [showPerformance,setShowPerformance]=useState(true);
  const [playMode,setPlayMode]=useState(false),[touchVelocity,setTouchVelocity]=useState(false);
  const [liveVolume,setLiveVolume]=useState(25),volumeEdit=useRef(0),volumePending=useRef<number|null>(null);
  const [,setHistoryVersion]=useState(0);
  const history=useRef<{past:KeyPatch[];future:KeyPatch[];stamp:number;group:string}>({past:[],future:[],stamp:0,group:''});
  const draftRef=useRef(draft);draftRef.current=draft;
  const saveRef=useRef<(sync?:boolean)=>void>(()=>{}),undoRef=useRef<(redo?:boolean)=>void>(()=>{});
  const auditionKey=useRef<{code:string;index:number}|null>(null);
  const livePending=useRef<{index:number;profile:Profile}|null>(null),liveRequest=useRef(false);
  const pedalDown=useRef(false),pointerOwners=useRef(new Map<number,number>());
  const playingOwners=useRef(new Map<number,Set<string>>());
  const down = useRef(new Map<number, number>());
  const polling = useRef(false);
  const stateRef = useRef(state); stateRef.current = state;
  const dirty = !!(draft && state && JSON.stringify(draft) !== JSON.stringify(state.config.keys[selected]));
  const liveBusy=state?.live.inflight!==null&&state?.live.inflight!==undefined;
  const busy = working || (!!state?.transfer&&!liveBusy);
  const savingBusy=busy||liveBusy||!!state?.live.pending.length;

  const refresh = useCallback(async () => {
    const next = await request<StudioState>('get_state');
    setState(next);
    return next;
  }, []);
  const refreshPorts = useCallback(async () => {
    const next = await request<typeof ports>('ports');
    setPorts(next); setPort(current => next.some(p => p.device === current) ? current : next[0]?.device ?? '');
  }, []);
  const run = useCallback(async (action: () => Promise<unknown>) => {
    setWorking(true); setError('');
    try { await action(); await refresh(); }
    catch (e) { setError(String(e).replace(/^Error: /, '')); }
    finally { setWorking(false); }
  }, [refresh]);
  const command=useCallback((method:string,params:Record<string,unknown>={})=>{void request(method,params).then(refresh).catch(e=>setError(String(e).replace(/^Error: /,'')));},[refresh]);
  const refreshMidi=useCallback(()=>{void request<MidiPort[]>('midi_ports').then(p=>{setMidiPorts(p);setMidiId(i=>p.some(v=>v.id===i)?i:p[0]?.id??-1);}).catch(e=>setError(String(e)));},[]);

  useEffect(() => {
    let mounted = true;
    void (async () => {
      try {
        const initial = await request<StudioState>('get_state');
        if (!mounted) return;
        setState(initial);
        const catalog = await request<Timbre[]>('bank_catalog'); if(mounted) setBank(catalog);
        const waves = await request<Resource[]>('library_catalog'); if(mounted) setResources(waves);
        if(mounted) {await refreshPorts();refreshMidi();}
      } catch(e) { if(mounted) setError(String(e).replace(/^Error: /, '')); }
    })();
    const timer = setInterval(async () => {
      if(polling.current || !stateRef.current) return;
      polling.current = true;
      try { const next = await request<StudioState>('get_state'); if(mounted) setState(next); }
      catch(e) { if(mounted) setError(String(e)); }
      finally { polling.current = false; }
    }, 250);
    return () => { mounted = false; clearInterval(timer); };
  }, [refreshPorts,refreshMidi]);

  useEffect(() => {
    if(state) {
      setDraft(structuredClone(state.config.keys[selected]));
      setOutput({ volume: state.config.sound.volume, boost: state.config.sound.output_boost });
      setTemplate(structuredClone(state.config.sound));
      history.current={past:[],future:[],stamp:0,group:''};setHistoryVersion(v=>v+1);
    }
  }, [selected, state?.revision]);

  const releaseAll = useCallback(() => {
    down.current.clear();pointerOwners.current.clear();playingOwners.current.clear();auditionKey.current=null;pedalDown.current=false; setPressed([]);
    void request('release_all').catch(() => {});
  }, []);
  useEffect(() => {
    window.addEventListener('blur', releaseAll);
    const hide = () => { if(document.hidden) releaseAll(); };
    document.addEventListener('visibilitychange', hide);
    return () => { window.removeEventListener('blur', releaseAll); document.removeEventListener('visibilitychange', hide); };
  }, [releaseAll]);
  useEffect(()=>{
    const active=()=>page==='design'&&!help&&!confirm&&!capture&&!document.hidden&&document.hasFocus();
    const arm=()=>{if(!active())releaseAll();void request('performance_arm',{enabled:active()}).catch(()=>{});};
    const disarm=()=>{releaseAll();void request('performance_arm',{enabled:false}).catch(()=>{});};
    arm();window.addEventListener('focus',arm);window.addEventListener('blur',disarm);document.addEventListener('visibilitychange',arm);
    return()=>{window.removeEventListener('focus',arm);window.removeEventListener('blur',disarm);document.removeEventListener('visibilitychange',arm);};
  },[page,help,confirm,capture,releaseAll]);
  useEffect(()=>{
    if(!state?.online){setPressed([]);down.current.clear();pointerOwners.current.clear();playingOwners.current.clear();auditionKey.current=null;volumePending.current=null;}
  },[state?.online]);
  useEffect(()=>{if(state&&Date.now()-volumeEdit.current>350)setLiveVolume(state.performance.volume);},[state?.performance.volume,state]);
  useEffect(()=>{
    const timer=setInterval(()=>{const volume=volumePending.current;if(volume===null)return;volumePending.current=null;void request('set_live_volume',{volume}).catch(e=>setError(String(e)));},60);
    return()=>clearInterval(timer);
  },[]);
  useEffect(()=>{
    livePending.current=state?.live.enabled&&state.online&&page==='design'&&draft&&!confirm&&!help&&!busy?{index:selected,profile:draft.synth}:null;
    return()=>{livePending.current=null;};
  },[selected,draft?.synth,state?.live.enabled,state?.online,page,confirm,help,busy]);
  useEffect(()=>{
    const timer=setInterval(()=>{const edit=livePending.current;if(!edit||liveRequest.current)return;livePending.current=null;liveRequest.current=true;void request('live_edit',edit).catch(e=>setError(String(e).replace(/^Error: /,''))).finally(()=>{liveRequest.current=false;});},100);
    return()=>clearInterval(timer);
  },[]);

  const play = useCallback((index: number, owner: string, velocity?:number) => {
    const s=stateRef.current;
    if(!s?.online || (s.transfer&&s.live.inflight===null) || !s.synced.includes(index) || s.live.pending.includes(index)) return;
    const owners=playingOwners.current.get(index)??new Set<string>();owners.add(owner);playingOwners.current.set(index,owners);setPressed([...playingOwners.current.keys()]);
    void request('perform_note_on', { index, owner,...(velocity!==undefined?{velocity}:{}) }).catch(e => { setError(String(e));const owners=playingOwners.current.get(index);owners?.delete(owner);if(!owners?.size)playingOwners.current.delete(index);setPressed([...playingOwners.current.keys()]); });
  }, []);
  const stop = useCallback((index: number, owner: string) => {
    const owners=playingOwners.current.get(index);owners?.delete(owner);if(!owners?.size)playingOwners.current.delete(index);setPressed([...playingOwners.current.keys()]);
    void request('note_off', { index, owner }).catch(() => {});
  }, []);
  const stopPointer=(id:number)=>{const index=pointerOwners.current.get(id);pointerOwners.current.delete(id);if(index!==undefined)stop(index,`pointer:${id}`);};

  useEffect(() => {
    const keydown = (e: KeyboardEvent) => {
      if(capture) {
        e.preventDefault();
        if(e.key === 'Escape') { setCapture(false); return; }
        if(![16,17,18,91,92].includes(e.keyCode) && e.keyCode > 0 && e.keyCode < 256) {
          if(draftRef.current)editDraft({...draftRef.current,keycode:e.keyCode,shortcut:e.key===' '?'SPACE':e.key.toUpperCase()},'keycode');
          setCapture(false);
        }
        return;
      }
      if(e.key === 'Escape') { releaseAll(); void run(() => request('panic')); return; }
      if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='s'&&page==='design'&&!help&&!confirm){e.preventDefault();saveRef.current(e.shiftKey);return;}
      if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'&&page==='design'&&!help&&!confirm&&!(e.target as HTMLElement).closest('input,textarea,[contenteditable="true"]')){e.preventDefault();undoRef.current(e.shiftKey);return;}
      if(!keyboard || page !== 'design' || help || confirm || e.ctrlKey || e.metaKey || e.altKey) return;
      if((e.target as HTMLElement).closest('input,textarea,select,[role="slider"],[role="dialog"],[contenteditable="true"]')) return;
      if(e.code==='Space'&&!(e.target as HTMLElement).closest('button')&&!stateRef.current?.config.keys.some(k=>k.keycode===32)) {e.preventDefault();if(!e.repeat){pedalDown.current=true;command('set_sustain',{down:true});}return;}
      const index = stateRef.current?.config.keys.findIndex(k => k.keycode === e.keyCode) ?? -1;
      if(index < 0) return;
      e.preventDefault();
      if(e.repeat || down.current.has(e.keyCode)) return;
      down.current.set(e.keyCode, index); play(index, 'keyboard');
    };
    const keyup = (e: KeyboardEvent) => {if(auditionKey.current?.code===e.code){stop(auditionKey.current.index,'audition');auditionKey.current=null;}if(e.code==='Space'&&pedalDown.current){pedalDown.current=false;command('set_sustain',{down:false});} const index = down.current.get(e.keyCode); if(index !== undefined) { down.current.delete(e.keyCode); stop(index, 'keyboard'); } };
    window.addEventListener('keydown', keydown, true); window.addEventListener('keyup', keyup, true);
    return () => { window.removeEventListener('keydown', keydown, true); window.removeEventListener('keyup', keyup, true); };
  }, [capture, keyboard, page, help, confirm, play, stop, releaseAll, run,command]);

  useEffect(() => {
    if(page !== 'waves' || !resources.length) return;
    let cancelled = false;
    const timer = setTimeout(() => { void request<PairPreview>('wave_preview', { resource_id: resourceId, position }).then(p => { if(!cancelled) setPair(p); }).catch(e => { if(!cancelled) setError(String(e)); }); }, 70);
    return () => { cancelled = true; clearTimeout(timer); };
  }, [page, resources, resourceId, position]);
  useEffect(() => {
    if(page !== 'surge') return;
    let mounted = true;
    const poll = () => { void request<Snapshot>('surge_data').then(s => { if(mounted) setSnapshot(s); }).catch(e => { if(mounted) setError(String(e)); }); };
    poll(); const timer = setInterval(poll, 1000);
    return () => { mounted = false; clearInterval(timer); };
  }, [page]);

  function guard(action: () => void) {
    releaseAll(); setCapture(false);
    if(dirty) setConfirm({ title: '保留当前修改？', description: '当前音键有尚未保存的修改。继续将放弃这些修改，并恢复该键已保存的硬件参数；也可以返回编辑后保存。', action:()=>void run(async()=>{await request('live_discard',{index:selected});action();}) });
    else action();
  }
  function navigate(next: Page) { guard(() => { setDraft(state ? structuredClone(state.config.keys[selected]) : null); setPage(next); }); }
  function editDraft(next:KeyPatch,group:string) {const current=draftRef.current;if(!current||JSON.stringify(current)===JSON.stringify(next))return;const h=history.current;if(h.group!==group||Date.now()-h.stamp>350){h.past.push(structuredClone(current));if(h.past.length>80)h.past.shift();}h.future=[];h.group=group;h.stamp=Date.now();draftRef.current=next;setDraft(next);setHistoryVersion(v=>v+1);}
  function updateProfile(name: keyof Profile, value: string | number) {const d=draftRef.current;if(!d)return;const synth={...d.synth,[name]:value};if(name==='mode'&&!['FM / PM','波表混合'].includes(String(value)))synth.depth=Math.min(1,synth.depth);editDraft({...d,synth},String(name));}
  undoRef.current=(redo=false)=>{if(savingBusy)return;const h=history.current;const next=(redo?h.future:h.past).pop();if(!next||!draftRef.current)return;(redo?h.past:h.future).push(structuredClone(draftRef.current));h.stamp=0;draftRef.current=next;setDraft(next);setHistoryVersion(v=>v+1);};
  function saveKey(sync = false) {
    const index = selected, key = draftRef.current;
    if(!key||savingBusy) return;
    if(sync||!state?.live.applied[String(index)])releaseAll();
    void run(async () => { if(dirty) await request('save_key', { index, key }); if(sync) await request('sync', { indices: [index] }); });
  }
  saveRef.current=saveKey;
  function loadPreset(timbre: Timbre) { guard(() => { void run(async () => { await request('load_preset', { index: selected, timbre_id: timbre.id }); setPage('design'); }); }); }
  function fileAction(method: string, title: string, extensions: string[], writing = false, extra: Record<string, unknown> = {}) {
    void run(async () => { const path = await chooseFile(title, extensions, writing); if(path) await request(method, { path, ...extra }); });
  }
  const currentPage = pages.find(p => p.id === page)!;
  const filtered = bank.filter(t => (category === '全部' || t.category === category) && (t.title + t.category + t.description).toLowerCase().includes(query.toLowerCase()));
  const profile = draft?.synth;
  const appliedProfile=state?.live.applied[String(selected)];
  const confirmedPreview=!!(profile&&appliedProfile&&(Object.keys({...profile,...appliedProfile}) as (keyof Profile)[]).every(k=>(profile[k]??(k==='frame_position'?0:undefined))===(appliedProfile[k]??(k==='frame_position'?0:undefined))));
  const syncable = !!state?.online && !savingBusy;
  const oscillatorData = (wave: string) => wave === '自定义波表' ? bank.find(t => t.id === state?.config.tauri_bindings?.[String(selected)])?.waveform : null;

  return <ParameterControls.Provider value={controlStyle}><div className="app-shell">
    <aside className="sidebar">
      <div className="brand"><span className="brand-mark"><AudioLines size={25}/></span><div>TANG<span>SYNTH STUDIO</span></div><b>32</b></div>
      <div className="sidebar-label">工作空间</div>
      <nav aria-label="工作空间">{pages.map(p => <button key={p.id} className={`nav-item ${page === p.id ? 'active' : ''}`} onClick={() => navigate(p.id)}><p.icon size={18}/>{p.title}{page === p.id && <span className="nav-dot"/>}</button>)}</nav>
      <div className="sidebar-label presets-label">快速载入 <span>01—06</span></div>
      <div className="quick-presets">{bank.slice(0,6).map(t => <button key={t.id} disabled={busy} onClick={() => loadPreset(t)}><span className={`preset-dot dot-${t.id % 3}`}/><span>{t.title}</span><ChevronRight size={13}/></button>)}</div>
      <div className="sidebar-bottom"><div className="device-tile"><Cpu size={24}/><div>Tang Mega 60K<span>{state?.online ? 'FPGA 在线' : '离线编辑模式'}</span></div><span className={`led ${state?.online ? 'on' : ''}`}/></div>
        <button className="help-button" onClick={() => { releaseAll(); setHelp(true); }}><CircleHelp size={16}/>使用指南<span>?</span></button></div>
    </aside>
    <div className="workspace">
      <header className="topbar"><div className="breadcrumb">工作空间<ChevronRight size={13}/><strong>{currentPage.title}</strong></div><div className="connection-tools"><span className={`connection-state ${state?.online ? 'connected' : ''}`}><i/>{state?.online ? '设备已连接' : state?.connecting ? '等待响应' : '设备未连接'}</span><select aria-label="串口" disabled={!!state?.online || !!state?.connecting} value={port} onChange={e => setPort(e.target.value)}><option value="">选择串口</option>{ports.map(p => <option key={p.device} value={p.device}>{p.device} · {p.description}</option>)}</select><button className="icon-button" aria-label="刷新串口" onClick={() => void run(refreshPorts)}><RefreshCw size={15}/></button><button className="button small" disabled={!state || working || (!state.online && !state.connecting && !port)} onClick={() => void run(() => request(state?.online || state?.connecting ? 'disconnect' : 'connect', { ...(state?.online || state?.connecting ? {} : { port }) }))}><Power size={14}/>{state?.online || state?.connecting ? '断开' : '连接'}</button></div></header>
      <main className="main">
        <div className="page-heading"><div><div className="eyebrow">{currentPage.subtitle} <span>/ TANG SYNTH 32</span></div><h1>{currentPage.title}</h1></div><div className="heading-actions">{page === 'design' && <><span className={`save-state ${dirty ? 'dirty' : ''}`}>{dirty ? '● 未保存的修改' : '所有修改已保存'}</span><button className="button" disabled={!draft || !dirty || savingBusy} onClick={() => saveKey()}><Save size={15}/>保存</button><button className="button primary" disabled={!syncable} onClick={() => saveKey(true)}><Upload size={15}/>{dirty ? '保存并同步' : '同步此键'}</button></>}{page === 'library' && <span className="pill">{bank.length} 个基础音色</span>}{page === 'waves' && <button className="button primary" onClick={() => void run(async () => { const path = await chooseFile('打开波表与资源库', ['wt','wav','tswt','jsn','bin','json','csv','txt']); if(path) { setResources(await request<Resource[]>('load_library_file', { path })); setResourceId(0); setPosition(0); } })}><FolderOpen size={16}/>导入波表</button>}{page === 'device' && <><button className="button" disabled={busy} onClick={() => guard(() => fileAction('import_config', '导入配置', ['json']))}><Download size={15}/>导入配置</button><button className="button" onClick={() => fileAction('export_config','导出配置',['json'],true)}><Upload size={15}/>导出配置</button></>}</div></div>
        {!state && <div className="empty-state"><LoaderCircle className="spin" size={34}/><h2>正在启动合成器工作台</h2><p>载入音色库与设备后台…</p></div>}
        {state && draft && profile && <>
          {page === 'design' && <><div className="edit-tools"><div className="segmented control-style" aria-label="参数控件样式"><button className={controlStyle==='knob'?'selected':''} onClick={()=>{setControlStyle('knob');localStorage.setItem('tang.controls','knob');}}>旋钮</button><button className={controlStyle==='slider'?'selected':''} onClick={()=>{setControlStyle('slider');localStorage.setItem('tang.controls','slider');}}>滑杆</button></div><span className="control-hint">拖动 · Shift 精调 · 双击复位</span><button className="button small" disabled={!history.current.past.length||savingBusy} onClick={()=>undoRef.current()}>撤销</button><button className="button small" disabled={!history.current.future.length||savingBusy} onClick={()=>undoRef.current(true)}>重做</button><div className="live-switch"><Toggle label="实时参数同步" checked={state.live.enabled} disabled={!state.online||busy} onChange={enabled=>command('live_mode',{enabled})}/><span className={`live-status ${liveBusy||state.live.pending.length?'pending':''}`}>{state.live.error?'同步中断':liveBusy||state.live.pending.length?'正在确认…':confirmedPreview?'预览已确认 · 下次起音':appliedProfile?'硬件保留上次确认的参数':'振荡器 / 包络：下次起音生效'}</span></div></div><div className="designer" key={selected}>
            <div className="sound-editor scroll-area">
              <div className="patch-heading"><div className="patch-emblem"><AudioLines size={27}/></div><div><span className="eyebrow">KEY {String(selected + 1).padStart(2,'0')} · {noteName(draft.note)}</span><h2>{draft.name}</h2></div><label className="mode-select"><span>合成引擎</span><select aria-label="合成模式" disabled={busy} value={profile.mode} onChange={e => updateProfile('mode', e.target.value)}>{MODES.map(m => <option key={m}>{m}</option>)}</select></label></div>
              <fieldset disabled={busy} inert={busy} className="editor-fields">
                <div className="oscillators">{(['a','b'] as const).map((osc, i) => <section className={`panel oscillator ${osc}`} key={osc}><div className="section-heading"><span className="section-number">0{i + 1}</span><h3>振荡器 {osc.toUpperCase()}</h3><span className="subtle">{i ? 'MODULATOR' : 'CARRIER'}</span></div><div className="wave-title"><select aria-label={`振荡器 ${osc.toUpperCase()} 波形`} value={profile[`wave_${osc}`]} disabled={profile.mode === '采样钢琴'} onChange={e => updateProfile(`wave_${osc}`, e.target.value)}>{WAVES.map(w => <option key={w}>{w}</option>)}</select><span>{i ? 'B' : 'A'}</span></div><div className="osc-graph"><Waveform wave={profile[`wave_${osc}`]} data={oscillatorData(profile[`wave_${osc}`])} color={i ? 'var(--violet)' : 'var(--accent)'}/><span className="graph-caption">{profile[`wave_${osc}`] === '自定义波表' && !oscillatorData(profile[`wave_${osc}`]) ? '请在波表工坊查看资源' : '单周期形状示意'}</span></div><Parameter label={i ? '混合 B 电平' : 'A 电平'} value={profile[`gain_${osc}`]} defaultValue={state.config.keys[selected].synth[`gain_${osc}`]} unit="%" onChange={v => updateProfile(`gain_${osc}`, v)} disabled={i === 1 && profile.mode !== '波表混合'}/></section>)}</div>
                <section className={`panel envelope-panel ${envelopeTab ? 'mod-envelope' : ''}`}><div className="section-heading"><Activity size={16}/><h3>包络</h3><div className="segmented"><button type="button" className={!envelopeTab && !modulationOpen ? 'selected' : ''} onClick={() => {setEnvelopeTab(false);setModulationOpen(false);}}>音量包络</button><button type="button" className={envelopeTab && !modulationOpen ? 'selected' : ''} onClick={() => {setEnvelopeTab(true);setModulationOpen(false);}}>调制包络</button><button type="button" className={modulationOpen ? 'selected' : ''} onClick={() => setModulationOpen(true)}>调制设置</button></div></div>{modulationOpen ? <div className="mod-settings"><div className="parameter-grid three"><Parameter label="B:A 频率比" value={profile.ratio} min={1/256} max={8} step={.01} onChange={v => updateProfile('ratio', v)}/><Parameter label="调制深度" value={profile.depth} max={['FM / PM','波表混合'].includes(profile.mode) ? 2 : 1} step={.01} onChange={v => updateProfile('depth',v)}/><Parameter label="B 固定频率" value={profile.mod_hz} max={1000} step={.1} unit="Hz" onChange={v => updateProfile('mod_hz',v)}/></div><div className="inline-note">固定频率为 0 时使用频率比。FM 深度以周期计。</div></div> : <><Envelope profile={profile} mod={envelopeTab}/><div className="parameter-grid four">{(['attack','decay','sustain','release'] as const).map((name, i) => { const key = `${envelopeTab ? 'm_' : ''}${name}` as keyof Profile; return <Parameter key={key} label={['A · 起音','D · 衰减','S · 持续','R · 释放'][i]} value={Number(profile[key])} defaultValue={Number(state.config.keys[selected].synth[key])} max={name === 'sustain' ? 100 : 5000} step={name === 'sustain' ? 1 : .1} unit={name === 'sustain' ? '%' : 'ms'} onChange={v => updateProfile(key,v)}/>; })}</div><div className="inline-note">线性阶段预览 · 持续段宽度仅用于展示，并非实际持键时长。</div></>}</section>
              </fieldset>
            </div>
            <aside className="inspector scroll-area"><div className="inspector-title"><span>音键配置</span><span className="key-badge">{String(selected+1).padStart(2,'0')}</span></div><fieldset disabled={busy} inert={busy}><label className="form-field">音色名称<input aria-label="音色名称" maxLength={24} value={draft.name} onChange={e => editDraft({ ...draft, name: e.target.value },"name")}/></label><div className="form-row"><label className="form-field">MIDI 音高<input aria-label="MIDI 音高" type="number" min={0} max={127} value={draft.note} onChange={e => setDraft({ ...draft, note: Math.min(127,Math.max(0,Math.round(Number(e.target.value)))) })}/></label><div className="note-display"><Music2 size={15}/>{noteName(draft.note)}</div></div><div className="mapping"><span>电脑键盘映射</span><button className={`keycap ${capture ? 'capture' : ''}`} onClick={() => { releaseAll(); setCapture(true); }}>{capture ? '请按键…' : draft.shortcut}</button></div><p className="microcopy">点击键帽重新绑定；Esc 取消。</p><div className="inspector-divider"/><Parameter label="演奏力度" value={draft.velocity} min={1} max={127} onChange={v => editDraft({ ...draft, velocity:v },"velocity")}/><Parameter label="力度 → 调制深度" value={profile.sensitivity} unit="%" onChange={v => updateProfile('sensitivity',v)}/><Parameter label="双帧位置" value={profile.frame_position ?? 0} unit="%" step={.1} onChange={v => updateProfile('frame_position',v)}/><p className="microcopy">双帧位置在下次起音生效。</p></fieldset><div className={`sync-card ${state.synced.includes(selected) && !dirty ? 'confirmed' : ''}`}><span>{state.synced.includes(selected) && !dirty ? <Check size={16}/> : <RefreshCw size={15}/>}</span><div><strong>{state.synced.includes(selected) && !dirty ? '硬件已确认' : dirty ? '修改尚未保存' : '等待同步'}</strong><p>{state.online ? '同步成功后可在下方演奏。' : '连接设备后将音色发送到 FPGA。'}</p></div></div><button className="button text-button" onClick={() => navigate('library')}><Library size={15}/>从音色库开始<ChevronRight size={14}/></button></aside>
          </div></>}
          {page === 'library' && <div className="library-page scroll-area"><div className="library-intro"><div><h2>找到声音的起点。</h2><p>16 个基础音色，涵盖减法波形、FM、AM 与单周期乐器素材。</p></div><div className="target-tag"><Keyboard size={16}/>载入到 <b>KEY {String(selected+1).padStart(2,'0')}</b></div></div><div className="library-toolbar"><div className="search-field"><Search size={16}/><input aria-label="搜索音色" placeholder="搜索音色、类别或描述…" value={query} onChange={e => setQuery(e.target.value)}/>{query && <button aria-label="清除搜索" onClick={() => setQuery('')}><X size={14}/></button>}</div><div className="category-tabs">{['全部',...new Set(bank.map(t=>t.category))].map(c => <button className={category === c ? 'selected' : ''} key={c} onClick={() => setCategory(c)}>{c}</button>)}</div></div><div className="preset-grid">{filtered.map((t,i) => <article className={`preset-card color-${t.id % 3}`} key={t.id}><div className="preset-art"><span>{String(t.id).padStart(2,'0')} / {t.resource_id ? 'SINGLE CYCLE' : 'SYNTHESIS'}</span><Waveform wave={t.profile.wave_a} data={t.waveform} color={['var(--accent)','var(--violet)','var(--amber)'][t.id % 3]} compact/><button className="preview-button" aria-label={`试听 ${t.title}`} onClick={() => void run(() => request('preview',{timbre_id:t.id}))}><Headphones size={17}/></button></div><div className="preset-body"><span className="preset-category">{t.category}</span><h3>{t.title}</h3><p>{t.description}</p><div className="preset-bottom"><span>{t.profile.mode}</span><button disabled={busy} onClick={() => loadPreset(t)}>载入音色<ChevronRight size={14}/></button></div></div></article>)}</div>{!filtered.length && <div className="empty-state"><Search size={30}/><h3>没有匹配的音色</h3><p>试试“FM”“钢琴”，或清除筛选条件。</p><button className="button" onClick={() => { setQuery(''); setCategory('全部'); }}>清除筛选</button></div>}<div className="library-footnote"><Headphones size={15}/>耳机按钮播放电脑参考音频，不会向 FPGA 发送音符。<button onClick={() => void run(() => request('preview_stop'))}><Square size={12}/>停止试听</button></div></div>}
          {page === 'waves' && <div className="wave-page scroll-area"><div className="notice"><Waves size={17}/><div>波表资源可包含多帧。当前 FPGA 每次驻留一对共享帧；换表会影响其他自定义波表音键。</div></div><div className="wave-lab"><section className="panel resource-list"><div className="section-heading"><h3>波表资源</h3><span className="pill">{resources.length}</span></div>{resources.map(r => <button key={r.id} className={`resource-item ${r.id === resourceId ? 'active' : ''}`} onClick={() => { setResourceId(r.id); setPosition(0); }}><Waves size={20}/><span><strong>{r.title}</strong><small>{r.frames} 帧 · REV {r.revision}</small></span><ChevronRight size={14}/></button>)}{!resources.length && <p className="microcopy">导入 WT、Surge WAV、TSWT 或资源库目录。</p>}</section><section className="panel wave-detail"><div className="section-heading"><span className="section-number">WT</span><h3>{resources.find(r=>r.id === resourceId)?.title ?? '选择波表'}</h3><span className="subtle">FRAME MORPH</span></div><div className="wave-morph-graph">{pair ? <><Waveform data={pair.frames[0]} color="var(--violet)"/><Waveform data={pair.frames[1]} color="var(--accent)"/><Waveform data={pair.frames[0].map((a,i)=>a+(pair.frames[1][i]-a)*pair.fraction/65536)} color="#edf3e8"/></> : <span>等待载入资源</span>}</div><div className="wave-legend"><span><i style={{background:'var(--violet)'}}/>前帧 {pair?.first ?? '—'}</span><span><i style={{background:'var(--accent)'}}/>后帧 {pair?.second ?? '—'}</span><span><i style={{background:'#edf3e8'}}/>混合预览</span></div><Parameter label="整张波表位置" value={position} unit="%" step={.1} onChange={setPosition}/><div className="wave-actions"><span>目标 KEY {String(selected+1).padStart(2,'0')}</span><button className="button" disabled={!syncable || !pair} onClick={() => void run(() => request('upload_wave',{index:selected,resource_id:resourceId,position,single:true}))}>仅上传前帧</button><button className="button primary" disabled={!syncable || !pair} onClick={() => void run(() => request('upload_wave',{index:selected,resource_id:resourceId,position}))}><Upload size={15}/>同步相邻双帧</button></div></section></div><section className="panel sample-strip"><div className="sample-icon"><Music2 size={27}/></div><div><h3>钢琴与采样</h3><p>使用谐波钢琴波表，或载入带起音与循环尾音的 PCM 采样包。</p></div><button className="button" disabled={!syncable} onClick={() => void run(() => request('upload_piano_wave',{index:selected}))}>谐波钢琴表</button><button className="button" disabled={!syncable} onClick={() => fileAction('upload_pcm','导入 PCM 采样包',['json'],false,{index:selected})}><FolderOpen size={15}/>导入 PCM</button></section></div>}
          {page === 'surge' && <div className="surge-page scroll-area"><div className="bridge-hero"><div className="bridge-logo">S<span>Surge XT</span></div><div className="bridge-connector"><span/><Link2 size={22}/><span/></div><div className="bridge-logo tang">T<span>Tang Synth</span></div><div className="bridge-copy"><h2>让软件音色，走向硬件。</h2><p>连接本机 OSC，检查参数，再将音量 ADSR 应用到当前音键。</p></div></div><section className="panel"><div className="surge-controls"><label className="form-field">Surge 输入端口<input aria-label="Surge 输入端口" type="number" value={surgePorts[0]} onChange={e=>setSurgePorts([Number(e.target.value),surgePorts[1]])}/></label><label className="form-field">本机接收端口<input aria-label="本机接收端口" type="number" value={surgePorts[1]} onChange={e=>setSurgePorts([surgePorts[0],Number(e.target.value)])}/></label><button className="button primary" onClick={() => void run(() => request(state.surge.connected ? 'surge_disconnect' : 'surge_connect',state.surge.connected ? {} : {input_port:surgePorts[0],output_port:surgePorts[1]}))}><Radio size={15}/>{state.surge.connected ? '停止读取' : '连接读取'}</button><span className="microcopy">{state.surge.message}</span></div><p className="inline-note">在 Surge 的 OSC Settings 开启输入与输出，输出地址设置为 127.0.0.1。</p></section><section className="panel surge-table"><div className="section-heading"><h3>参数快照</h3><span className="pill">{state.surge.count} 项</span><div className="spacer"/><button className="button small" onClick={() => fileAction('surge_import','载入 Surge 快照',['json'])}>载入快照</button><button className="button small" onClick={() => fileAction('surge_export','导出 Surge 快照',['json'],true)}>导出快照</button></div><div className="table-scroll"><table><thead><tr><th>参数地址</th><th>数值</th><th>软件显示</th></tr></thead><tbody>{Object.entries(snapshot?.parameters ?? {}).map(([address,p])=><tr key={address}><td>{address}</td><td>{p.value.toFixed(5)}</td><td>{p.display || '—'}</td></tr>)}</tbody></table>{!Object.keys(snapshot?.parameters ?? {}).length && <div className="empty-state"><Radio size={28}/><h3>尚未收到参数</h3><p>连接 Surge 或载入已有快照。</p></div>}</div><div className="surge-apply"><label>场景 <select aria-label="Surge 场景" value={scene} onChange={e=>setScene(e.target.value)}><option value="a">A</option><option value="b">B</option></select></label><p>映射目标：KEY {String(selected+1).padStart(2,'0')} · 保存后需同步</p><button className="button primary" disabled={busy || !state.surge.count} onClick={() => void run(() => request('surge_apply',{index:selected,scene}))}>应用 ADSR</button></div></section><p className="inline-note">目前仅转换音量 ADSR；振荡器、滤波器、效果器与调制矩阵不作自动转换。</p></div>}
          {page === 'device' && <div className="device-page scroll-area"><div className="device-overview panel"><div className="hardware-art"><Cpu size={55}/><span>GOWIN / 60K</span></div><div><span className="eyebrow">HARDWARE ENGINE</span><h2>Tang Mega 60K</h2><p>DEBUG USB · 115200 baud · 32 音键</p><span className={`pill ${state.online ? 'good' : ''}`}>{state.online ? `${state.port} 已连接` : '等待连接设备'}</span></div><div className="sync-overview"><strong>{state.synced.length}<span>/ 32</span></strong><p>已确认的音键参数</p><button className="button" disabled={!syncable} onClick={() => void run(() => request('sync',{indices:Array.from({length:32},(_,i)=>i)}))}><RefreshCw size={15}/>同步全部音键</button></div></div><div className="telemetry-grid">{[['活动声部',state.telemetry?.voices,'/ 32'],['振荡器',state.telemetry?.oscillators,''],['削波次数',state.telemetry?.clips,''],['帧周期',state.telemetry?.cycles,'cycles']].map(([label,value,unit])=><div className="telemetry" key={label}><span>{label}</span><strong>{value ?? '—'}<small>{unit}</small></strong></div>)}</div><div className="settings-grid"><section className="panel"><div className="section-heading"><Headphones size={17}/><h3>主输出</h3><span className="subtle">MASTER</span></div><Parameter label="总音量" value={output.volume} unit="%" onChange={v=>setOutput({...output,volume:v})}/><label className="form-field">输出增益<select aria-label="输出增益" value={output.boost} onChange={e=>setOutput({...output,boost:Number(e.target.value)})}>{[0,6,12,18,24].map((db,i)=><option key={db} value={i}>{db ? '+' : ''}{db} dB · ×{2**i}</option>)}</select></label><p className="microcopy">增益用于补偿混音余量。提高后请观察削波次数。</p><button className="button primary" disabled={busy} onClick={() => void run(() => request('set_output',{volume:output.volume,boost:output.boost}))}>应用输出设置</button></section><section className="panel template-panel"><div className="section-heading"><SlidersHorizontal size={17}/><h3>全键音色模板</h3><span className="pill amber">覆盖 32 键</span></div>{template && <><label className="form-field">基础波形<select aria-label="模板波形" value={template.wave} onChange={e=>setTemplate({...template,wave:e.target.value})}>{[...WAVES,'钢琴（合成）'].map(w=><option key={w}>{w}</option>)}</select></label><div className="parameter-grid two">{(['attack','decay','sustain','release'] as const).map((key,i)=><Parameter key={key} label={['模板起音','模板衰减','模板持续','模板释放'][i]} value={template[key]} max={key==='sustain'?100:5000} unit={key==='sustain'?'%':'ms'} onChange={v=>setTemplate({...template,[key]:v})}/>)}</div><button className="button warning" disabled={busy} onClick={() => setConfirm({title:'覆盖全部音键的音色？',description:'32 个音键的独立音色将替换为此模板，键盘映射保持不变。保存后还需要同步到硬件。',action:()=>void run(()=>request('apply_template',{sound:template}))})}>应用到全部音键</button></>}</section></div></div>}
        </>}
      </main>
      {page === 'design' && state && <section className="performance">
        <div className="performance-header"><div><Keyboard size={16}/><h3>演奏区</h3><span>32 KEYS</span></div><p>{state.online ? '持音不重触发 · 旋钮同步后用于下一次起音' : '连接并同步后演奏 · 音色库支持电脑参考试听'}</p><button className="performance-collapse" aria-expanded={showPerformance} aria-controls="performance-options" onClick={()=>setShowPerformance(v=>!v)}>{showPerformance?'收起控制':'展开控制'}<ChevronRight size={13} className={showPerformance?'expanded':''}/></button><Toggle label="键盘演奏" checked={keyboard} onChange={v => { releaseAll(); setKeyboard(v); }}/><button className="panic-button" onClick={() => { releaseAll(); void run(()=>request('panic')); }}><Square size={12}/>紧急停止<kbd>Esc</kbd></button></div>
        <div id="performance-options" hidden={!showPerformance}><PerformanceControls state={state} ports={midiPorts} midiId={midiId} setMidiId={setMidiId} refreshMidi={refreshMidi} command={command} volume={liveVolume} onVolume={v=>{volumeEdit.current=Date.now();setLiveVolume(v);volumePending.current=v;}} touchVelocity={touchVelocity} setTouchVelocity={setTouchVelocity} playMode={playMode} setPlayMode={v=>{releaseAll();setPlayMode(v);}}/></div>
        <div className="pad-toolbar"><span>{playMode?'演奏时保持当前编辑键；右键选择另一键':'左键选择并演奏，右键仅选择'} · {touchVelocity?'触点越靠下力度越大':'按各键或统一力度演奏'}</span><button className="button small audition-button" disabled={!pressed.includes(selected)&&(!state.online||!state.synced.includes(selected)||state.live.pending.includes(selected))} onPointerDown={e=>{if(e.button!==0)return;e.currentTarget.setPointerCapture(e.pointerId);pointerOwners.current.set(e.pointerId,selected);play(selected,`pointer:${e.pointerId}`);}} onPointerUp={e=>stopPointer(e.pointerId)} onPointerCancel={e=>stopPointer(e.pointerId)} onLostPointerCapture={e=>stopPointer(e.pointerId)} onKeyDown={e=>{if(!e.defaultPrevented&&(e.code==='Space'||e.key==='Enter')&&!e.repeat){e.preventDefault();auditionKey.current={code:e.code,index:selected};play(selected,'audition');}}}>按住演奏当前键</button></div>
        <div className="pads">{state.config.keys.map((k,i) => <button key={i} aria-label={`音键 ${i+1} ${noteName(k.note+state.performance.transpose)}`} title={`${k.name} · ${k.shortcut}`} className={`pad ${selected===i?'selected':''} ${pressed.includes(i)||state.held.includes(i)?'playing':''} ${state.synced.includes(i)?'synced':''}`} onContextMenu={e => { e.preventDefault(); guard(()=>setSelected(i)); }} onPointerDown={e=>{
          if(e.button!==0)return;e.currentTarget.setPointerCapture(e.pointerId);
          if(!playMode){if(dirty&&selected!==i){guard(()=>setSelected(i));return;}setSelected(i);}
          pointerOwners.current.set(e.pointerId,i);const rect=e.currentTarget.getBoundingClientRect();const velocity=touchVelocity?Math.max(1,Math.min(127,Math.round(1+(e.clientY-rect.top)/rect.height*126))):undefined;
          play(i,`pointer:${e.pointerId}`,velocity);
        }} onPointerUp={e=>{const index=pointerOwners.current.get(e.pointerId);pointerOwners.current.delete(e.pointerId);if(index!==undefined)stop(index,`pointer:${e.pointerId}`);}} onPointerCancel={e=>{const index=pointerOwners.current.get(e.pointerId);pointerOwners.current.delete(e.pointerId);if(index!==undefined)stop(index,`pointer:${e.pointerId}`);}} onLostPointerCapture={e=>{const index=pointerOwners.current.get(e.pointerId);pointerOwners.current.delete(e.pointerId);if(index!==undefined)stop(index,`pointer:${e.pointerId}`);}}><div><span>{String(i+1).padStart(2,'0')}</span><kbd>{k.shortcut}</kbd></div><strong>{noteName(k.note+state.performance.transpose)}</strong><i/></button>)}</div>
      </section>}
      <footer className="statusbar"><span className={`status-led ${state?.level ?? ''}`}/><p role="status">{state?.message ?? '等待后台启动…'}</p>{state?.transfer && <div className="transfer"><LoaderCircle className="spin" size={12}/><span>{state.progress} / {state.total}</span><progress value={state.progress} max={state.total}/></div>}<span className="status-meta">{state?.telemetry ? `${state.telemetry.voices} / 32 VOICES` : 'OFFLINE'}<span>STUDIO 0.4 · RUST</span></span></footer>
    </div>
    {error && <div className="error-toast" role="alert"><Activity size={18}/><div><strong>操作未完成</strong><p>{error}</p></div><button className="icon-button" aria-label="关闭错误提示" onClick={()=>setError('')}><X size={16}/></button></div>}
    <Modal open={help} onClose={()=>setHelp(false)} title="开始创造你的声音" description="从一个音色，到一颗独立的硬件音键。"><ol className="help-steps"><li><b>选择音色</b><p>打开音色浏览器，耳机按钮可直接电脑试听。点击“载入音色”将参数放到当前音键。</p></li><li><b>编辑与保存</b><p>在声音设计页调整振荡器、调制和包络。音键名称、音高、力度与键盘映射在右侧。</p></li><li><b>连接与同步</b><p>插入 DEBUG USB、刷新串口并连接。点击“同步此键”，等待硬件确认。</p></li><li><b>演奏</b><p>按住底部音键或对应电脑键盘按键。离开窗口自动释放音符，Esc 紧急停止。Space 延音（若已绑定音键则保留原映射）；可锁定编辑键、临时移调或按触点高度改变力度。</p></li><li><b>旋钮与实时控制</b><p>上下拖动旋钮，Shift 精调；聚焦后滚轮或方向键调整，双击复位。Ctrl+S 保存，Ctrl+Shift+S 保存并同步，Ctrl+Z / Ctrl+Shift+Z 撤销 / 重做。实时主音量立即发送；实时参数同步经硬件确认后，下次起音生效。点击保存才会保留到电脑。</p></li><li><b>MIDI 键盘</b><p>选择并连接 MIDI 输入，音符按已保存的音键音高匹配，重复音高使用第一个音键。支持原始力度、CC64 延音、CC7 主音量与通道选择。需要先连接 FPGA 并同步音键。</p></li></ol><div className="notice">自定义波表共用一对硬件帧；电脑试听是参考音频，不是 FPGA 录音。</div></Modal>
    <Modal open={!!confirm} onClose={()=>setConfirm(null)} title={confirm?.title ?? ''} description={confirm?.description ?? ''}><div className="modal-actions"><button className="button" onClick={()=>setConfirm(null)}>返回编辑</button><button className="button primary" onClick={()=>{ const action=confirm?.action; setConfirm(null); action?.(); }}>继续</button></div></Modal>
  </div></ParameterControls.Provider>;
}
