import {TouchSettings,TouchStatus} from './TouchSettings';
import {SequencerPanel} from './SequencerPanel';
import {MasterFilter} from './MasterFilter';
import {useCallback,useEffect,useRef,useState} from 'react';
import {Activity,AudioLines,ChevronRight,Cpu,Library,Link2,LoaderCircle,Power,RefreshCw,Settings2,SlidersHorizontal,Square,Waves,X} from 'lucide-react';
import {request} from './api';
import {Modal,Parameter,ParameterControls,Toggle} from './components';
import {noteName,type Timbre,type NativePreset} from './types';
import {voiceCall} from '../../../demo_test/desktop-tauri/src/voice-api';
import {nativeTemplate} from '../../../demo_test/desktop-tauri/src/native-voice';
import {useStudioEngine,defaultKeys} from './useStudioEngine';
import {useWaveTransfer} from './useWaveTransfer';
import {SoundDesigner} from './SoundDesigner';
import {StatusDashboard,codes,type Held} from './StatusDashboard';
import {WaveTools,SurgeTools} from './StudioTools';
import {basicPatch,type Draft} from './patches';
import {PresetBrowser} from './PresetBrowser';
import {KeyboardSettings} from './KeyboardSettings';
import {HdmiControl} from './HdmiControl';
import {StorageStatus} from './StorageStatus';
import '../../../demo_test/desktop-tauri/src/voice-studio.css';
import './fm-studio.css';

type Page='status'|'design'|'library'|'waves'|'surge'|'device';
const pages=[{id:'status',title:'状态显示',subtitle:'LIVE MONITOR',icon:Activity},{id:'design',title:'声音设计',subtitle:'SOUND DESIGN',icon:SlidersHorizontal},{id:'library',title:'音色浏览器',subtitle:'PRESET LIBRARY',icon:Library},{id:'waves',title:'波表工坊',subtitle:'WAVETABLE LAB',icon:Waves},{id:'surge',title:'Surge 桥接',subtitle:'SURGE BRIDGE',icon:Link2},{id:'device',title:'设备与输出',subtitle:'DEVICE & OUTPUT',icon:Settings2}] as const;
function loadDrafts():Record<number,Draft>{try{return JSON.parse(localStorage.getItem('tang.unified.drafts')??'{}');}catch{return {};}}

export default function App(){
 const [page,setPage]=useState<Page>('status'),[selected,setSelected]=useState(()=>Math.max(0,Math.min(31,Number(localStorage.getItem('tang.unified.key')??0)||0)));
 const engine=useStudioEngine(page==='status',page==='device',page==='device'||page==='design'),{view,catalog,run,ports,refreshPorts,setError}=engine;
 const [bank,setBank]=useState<Timbre[]>([]),[nativeBank,setNativeBank]=useState<NativePreset[]>([]),[drafts,setDrafts]=useState<Record<number,Draft>>(loadDrafts);
 const [scope,setScope]=useState('key'),[working,setWorking]=useState(false),[message,setMessage]=useState('选择音键，配置音色，然后演奏。');
 const [port,setPort]=useState(''),[fresh,setFresh]=useState(false),[controlStyle,setControlStyle]=useState<'knob'|'slider'>(()=>localStorage.getItem('tang.controls')==='slider'?'slider':'knob');
 const [query,setQuery]=useState(''),[category,setCategory]=useState('全部'),[help,setHelp]=useState(false);
 const [keyboard,setKeyboard]=useState(true),[transpose,setTranspose]=useState(0),[velocity,setVelocity]=useState(100),[volume,setVolume]=useState(50),[autoSync,setAutoSync]=useState(false);
 const [midiPorts,setMidiPorts]=useState<string[]>([]),[midi,setMidi]=useState(''),[held,setHeld]=useState<Held>({});
 const heldRef=useRef(held),volumeTimer=useRef<ReturnType<typeof setTimeout>|null>(null),runtime=useRef({view,selected,transpose,velocity,page,keyboard,working});
 runtime.current={view,selected,transpose,velocity,page,keyboard,working};
 const keys=view?.keys?.length===32?view.keys:defaultKeys(),mapping=keys[selected],slot=view?.slots[mapping.slot];
 const preset=catalog?.presets.find(p=>p.program===slot?.program),soundName=slot?.snapshot?.name??slot?.native?.name??preset?.name??'等待连接';
 const base:Draft={patch:slot?.native?structuredClone(slot.native):slot?.program!=null?null:nativeTemplate('pm'),program:slot?.program??null,operators:slot?.operators?structuredClone(slot.operators):[],note:mapping.note,velocity:mapping.velocity,dirty:false,revision:slot?.revision??0};
 const draft=drafts[selected]?.dirty?drafts[selected]:base;
 const draftConflict=draft.dirty&&draft.revision!==base.revision;
 const snapshotOnly=!!slot?.snapshot&&!slot.native&&slot.program==null;
 const wave=useWaveTransfer(view,run,(key,title)=>{setDrafts(old=>{const next={...old};delete next[key];return next;});setSelected(key);setPage('design');setMessage(`「${title}」已装入 KEY ${key+1}`);});
 const busy=working||engine.busy||wave.running,ready=!!view?.connected&&!!view.abi&&!view.pending&&!view.wave_transfer&&!view.keyboard?.calibration&&!(view.storage?.service&&(view.storage.busy||view.storage.syncing)),stale=!view?.connected||view.age_ms===null||view.age_ms>1500;
 const shared=keys.filter(k=>k.slot===mapping.slot).length;
 const updateDraft=(d:Draft)=>setDrafts(old=>({...old,[selected]:d}));
 const clearDraft=(key:number)=>setDrafts(old=>{const next={...old};delete next[key];return next;});
 const catchError=useCallback((e:unknown)=>setError(String(e).replace(/^Error: /,'')),[setError]);
 useEffect(()=>{void request<Timbre[]>('bank_catalog').then(setBank).catch(catchError);void request<NativePreset[]>('native_preset_catalog').then(setNativeBank).catch(catchError);void voiceCall<string[]>('synth_midi_ports').then(setMidiPorts).catch(catchError);},[catchError]);
 useEffect(()=>{localStorage.setItem('tang.unified.drafts',JSON.stringify(drafts));},[drafts]);
 useEffect(()=>{localStorage.setItem('tang.unified.key',String(selected));},[selected]);
 useEffect(()=>{setPort(old=>ports.some(p=>p.name===old)?old:ports.find(p=>p.recommended)?.name??ports[0]?.name??'');},[ports]);
 useEffect(()=>{if(view?.connected){setPort(view.port??'');if(view.abi&&!view.pending)setFresh(false);}},[view?.connected,view?.port,view?.abi,view?.pending]);
 useEffect(()=>{if(view)setVolume(Math.round(view.volume*100));},[view?.volume]);
 const note=useCallback((token:string,key:number,down:boolean,midiNote?:number,midiVelocity?:number)=>{
  const c=runtime.current,v=c.view;
  if(down){if(!v?.connected||!v.abi||v.pending||v.wave_transfer||v.keyboard?.calibration||(v.storage?.service&&(v.storage.busy||v.storage.syncing))||c.working||heldRef.current[token])return;
   const map=v.keys?.[key]??defaultKeys()[key],pitch=midiNote??map.note+c.transpose;
   if(pitch<0||pitch>127)return;heldRef.current={...heldRef.current,[token]:{key,note:pitch,slot:map.slot}};setHeld(heldRef.current);
   void run({kind:'note',token,note:pitch,velocity:midiVelocity??c.velocity,slot:map.slot,pressed:true}).catch(catchError);
  }else{const old=heldRef.current[token];if(!old)return;const next={...heldRef.current};delete next[token];heldRef.current=next;setHeld(next);void run({kind:'note',token,note:old.note,velocity:100,slot:old.slot,pressed:false}).catch(catchError);}
 },[run,catchError]);
 const release=useCallback(()=>{Object.keys(heldRef.current).forEach(token=>note(token,0,false));},[note]);
 const navigate=(next:Page)=>{release();setPage(next);};
 const chooseKey=(key:number)=>{release();setSelected(key);setPage('design');};
 const panic=()=>{heldRef.current={};setHeld({});void run({kind:'panic'}).then(()=>setMessage('全部声部已停止')).catch(catchError);};
 useEffect(()=>{
  const down=(e:KeyboardEvent)=>{if(e.repeat||e.ctrlKey||e.metaKey||e.altKey||(e.target as HTMLElement).closest('input,textarea,select,[role="slider"],[role="dialog"]'))return;
   const c=runtime.current;if(e.code==='Escape'){e.preventDefault();release();if(c.view?.connected)void run({kind:'panic'}).catch(catchError);return;}
   if(!c.keyboard||c.page!=='status')return;
   if(e.code==='Space'){e.preventDefault();if(c.view?.connected)void run({kind:'control',volume:c.view.volume,sustain:true}).catch(catchError);return;}
   const key=codes.indexOf(e.code);if(key>=0){e.preventDefault();note(`pc:${e.code}`,key,true);}
  };
  const up=(e:KeyboardEvent)=>{note(`pc:${e.code}`,0,false);const v=runtime.current.view;if(e.code==='Space'&&v?.connected&&v.sustain)void run({kind:'control',volume:v.volume,sustain:false}).catch(catchError);};
  const blur=()=>{release();const v=runtime.current.view;if(v?.connected&&v.sustain)void run({kind:'control',volume:v.volume,sustain:false}).catch(catchError);};
  window.addEventListener('keydown',down);window.addEventListener('keyup',up);window.addEventListener('blur',blur);
  return()=>{window.removeEventListener('keydown',down);window.removeEventListener('keyup',up);window.removeEventListener('blur',blur);};
 },[run,note,release,catchError]);
 useEffect(()=>{if(!midi)return;let reading=false;const timer=setInterval(async()=>{if(reading)return;reading=true;try{for(const [s,n,v] of await voiceCall<number[][]>('synth_midi_events')){const op=s&240,token=`midi:${s&15}:${n}`,c=runtime.current;
  if(op===144||op===128){const match=c.view?.keys?.findIndex(k=>k.note===n)??-1;note(token,match>=0?match:c.selected,op===144&&v>0,n,v||1);}
  else if(op===176&&n===64&&c.view?.connected)void run({kind:'control',volume:c.view.volume,sustain:v>=64}).catch(catchError);
  else if(op===176&&(n===120||n===123)){release();void run({kind:'panic'}).catch(catchError);}
 }}catch(e){catchError(e);}finally{reading=false;}},12);return()=>clearInterval(timer);},[midi,note,release,run,catchError]);
 const setOutput=(value:number)=>{setVolume(value);if(volumeTimer.current)clearTimeout(volumeTimer.current);volumeTimer.current=setTimeout(()=>{const v=runtime.current.view;if(v?.connected)void run({kind:'control',volume:value/100,sustain:v.sustain}).catch(catchError);},100);};
 useEffect(()=>()=>{if(volumeTimer.current)clearTimeout(volumeTimer.current);},[]);
 async function perform(work:()=>Promise<void>){setWorking(true);setError('');try{await work();}catch(e){setAutoSync(false);catchError(e);}finally{setWorking(false);}}
 async function applyDraft(d=draft,key=selected){if(!ready||busy||draftConflict||snapshotOnly)return;await perform(async()=>{release();await run({kind:'assign_key',key,scope,program:d.program,patch:d.patch,operators:d.patch?null:d.operators});await run({kind:'configure_key',key,note:d.note,velocity:d.velocity});clearDraft(key);setMessage(`KEY ${String(key+1).padStart(2,'0')} 的音色与按键配置已由 FPGA 确认`);});}
 const applyRef=useRef(applyDraft);applyRef.current=applyDraft;
 useEffect(()=>{if(!autoSync||!draft.dirty||draftConflict||snapshotOnly||!ready||busy||view?.telemetry.pressed||Object.keys(held).length)return;const timer=setTimeout(()=>void applyRef.current(),650);return()=>clearTimeout(timer);},[autoSync,draft,draftConflict,snapshotOnly,ready,busy,view?.telemetry.pressed,held]);
 async function loadPreset(t:Timbre){if(!ready||busy)return;const key=selected;await perform(async()=>{
  const patch=basicPatch(t);await run({kind:'validate_key',key,scope,patch,program:null,operators:null});release();
  if(t.resource_id!=null){const asset=await request<{name:string;samples:number[]}>('voice_preset_wave',{timbre_id:t.id});if(view?.wave_name!==asset.name){await wave.start({...asset,morph:0},{key,scope,patch,title:t.title});return;}}
  await run({kind:'assign_key',key,scope,patch,program:null,operators:null});clearDraft(key);setPage('design');setMessage(`「${t.title}」已装入 KEY ${key+1}，现在可以从实体键或状态页试听`);
 });}
 async function loadNativePreset(preset:NativePreset){if(!ready||busy)return;const key=selected;await perform(async()=>{
  const patch=structuredClone(preset.patch);await run({kind:'validate_key',key,scope,patch,program:null,operators:null});release();
  await run({kind:'assign_key',key,scope,patch,program:null,operators:null});clearDraft(key);setPage('design');
  setMessage(`「${preset.title}」已装入 KEY ${key+1}${preset.percussive?' · 固定音高，按住自然衰减；共享低通也会影响鼓声':''}`);
 });}
 async function loadFm(program:number){if(!ready||busy)return;const key=selected;await perform(async()=>{release();await run({kind:'assign_key',key,scope,program,patch:null,operators:null});clearDraft(key);setPage('design');setMessage(`FM1 音色已装入 KEY ${key+1}`);});}
 const currentPage=pages.find(p=>p.id===page)!;
 const soundFor=(i:number)=>{const s=view?.slots[keys[i].slot];return s?.snapshot?.name??s?.native?.name??catalog?.presets.find(p=>p.program===s?.program)?.name??'待连接';};
 const m=view?.monitor;
 const connection=<><select aria-label="串口" disabled={!!view?.connected||busy} value={port} onChange={e=>setPort(e.target.value)}><option value="">选择调试口</option>{ports.map(p=><option key={p.name} value={p.name}>{p.name}{p.recommended?' · Tang 调试口':''}</option>)}</select><button className="icon-button" aria-label="刷新串口" onClick={()=>void refreshPorts().catch(catchError)}><RefreshCw size={15}/></button><button className="button small" disabled={busy||(!view?.connected&&!port)} onClick={()=>{release();void run(view?.connected?{kind:'disconnect'}:{kind:'connect',port,fresh}).then(()=>setMessage(view?.connected?'已停止并断开':'连接成功，按键映射已回读')).catch(catchError);}}><Power size={14}/>{view?.connected?'断开':'连接板卡'}</button></>;
 return <ParameterControls.Provider value={controlStyle}><div className="app-shell unified-studio"><aside className="sidebar"><div className="brand"><span className="brand-mark"><AudioLines size={25}/></span><div>TANG<span>SYNTH STUDIO</span></div><b>32</b></div><div className="sidebar-label">工作空间</div><nav aria-label="工作空间">{pages.map(p=><button key={p.id} className={`nav-item ${page===p.id?'active':''}`} onClick={()=>navigate(p.id)}><p.icon size={18}/>{p.title}{page===p.id&&<span className="nav-dot"/>}</button>)}</nav><div className="sidebar-label presets-label">快速载入<span>KEY {String(selected+1).padStart(2,'0')}</span></div><div className="quick-presets">{bank.slice(0,6).map(b=><button key={b.id} disabled={!ready||busy} onClick={()=>void loadPreset(b)}><span className={`preset-dot dot-${b.id%3}`}/><span>{b.title}</span><ChevronRight size={13}/></button>)}</div><div className="sidebar-bottom"><div className="device-tile"><Cpu size={24}/><div>Tang Mega 60K<span>{view?.connected?`${view.port} · ${stale?'遥测过期':'已连接'}`:'等待连接'}</span></div><span className={`led ${!stale?'on':''}`}/></div><button className="help-button" onClick={()=>setHelp(true)}>操作指南<span>?</span></button></div></aside>
 <div className="workspace"><header className="topbar"><div className="breadcrumb">工作空间<ChevronRight size={13}/><strong>{currentPage.title}</strong></div><div className="connection-tools"><span className={`connection-state ${!stale?'connected':''}`}><i/>{view?.connected?'硬件在线':'未连接'}</span>{connection}</div></header><main className="main unified-main"><div className="page-heading"><div><div className="eyebrow">{currentPage.subtitle}<span>/ TANG SYNTH 32</span></div><h1>{currentPage.title}</h1></div><div className="heading-actions">{page==='design'?<><select aria-label="当前编辑键" value={selected} onChange={e=>setSelected(Number(e.target.value))}>{keys.map((k,i)=><option key={i} value={i}>KEY {String(i+1).padStart(2,'0')} · {noteName(k.note)}</option>)}</select><button className="button" onClick={()=>navigate('status')}>返回状态显示</button></>:<button className="panic-button" disabled={!ready} onClick={panic}><Square size={13}/>全部松键<kbd>Esc</kbd></button>}</div></div>
 <div className={`workspace-message ${view?.pending?'warning':''}`} role="status"><span>{working?<><LoaderCircle size={15} className="spin"/>正在确认硬件操作… </>:null}{message}</span><span>{view?.retries??0} 次重试 · {view?.packets??0} 个已确认请求</span>{view?.pending&&<button className="button small" onClick={()=>void run({kind:'recover'}).catch(catchError)}>恢复未确认请求</button>}</div>
 {(view?.wave_transfer||(wave.intent&&wave.intent.port===view?.port&&wave.intent.wave===view?.wave_name))&&<section className="panel wave-task" aria-label="波表传输任务"><div><strong>{wave.running?'正在上传波表':'波表任务待继续'} · {view?.wave_transfer?.name??wave.intent?.title}</strong><span>{view?.wave_transfer?.written??2048} / {view?.wave_transfer?.total??2048} 点 · {Math.floor(100*(view?.wave_transfer?.written??2048)/2048)}%</span></div><progress max={2048} value={view?.wave_transfer?.written??2048}/><p>{wave.message||'上次传输未完成，已保留位置。点击继续后恢复演奏。'}{view?.wave_transfer?.busy_recoveries?` 已自动处理 ${view.wave_transfer.busy_recoveries} 次按键占用。`:''}</p><div><span>{view?.wave_transfer?'硬件暂时停音 · 115200 串口上传通常需数十秒':'波表已就绪，等待应用预设'}</span>{wave.running?<button className="button" onClick={wave.pause}>暂停传输</button>:<button className="button primary" disabled={!view?.connected||engine.busy||working} onClick={()=>void wave.resume()}>继续传输并完成</button>}</div></section>}
 {view?.keyboard?.calibration&&page!=='device'&&<div className="notice">键盘正在校准，已记录 {view.keyboard.calibration.completed} / 32 键，演奏暂时停止。<button className="button small" onClick={()=>navigate('device')}>返回键盘校准</button></div>}
 {view?.connected&&!m?.available&&<div className="notice">当前固件不支持逐键映射与 PCM 监测。请更新固件后再使用音色分配；界面不会显示伪造的波形。</div>}
 {page==='status'&&<SequencerPanel view={view} run={run} busy={busy} onError={catchError}/>}
 {page==='status'&&<TouchStatus view={view}/>}
 {page==='status'&&<StatusDashboard view={view} keys={keys} selected={selected} busy={busy} ready={ready} held={held} soundFor={soundFor} chooseKey={chooseKey} note={note} volume={volume} setVolume={setOutput} velocity={velocity} setVelocity={setVelocity} keyboard={keyboard} setKeyboard={v=>{release();setKeyboard(v);}} transpose={transpose} setTranspose={v=>{release();setTranspose(v);}} sustain={v=>void run({kind:'control',volume:view?.volume??.5,sustain:v}).catch(catchError)} midi={midi} midiPorts={midiPorts} setMidi={v=>{release();void voiceCall('synth_midi_connect',{index:v===''?null:Number(v)}).then(()=>setMidi(v)).catch(catchError);}}/>}
 {page==='design'&&<>{draftConflict&&<div className="notice">板上音色已更新，当前草稿尚未覆盖它。<button className="button small" onClick={()=>clearDraft(selected)}>使用板上音色</button><button className="button small" onClick={()=>{setAutoSync(false);updateDraft({...draft,revision:base.revision});}}>保留草稿继续编辑</button></div>}{snapshotOnly&&<div className="notice">已读取板上完整音色。此自定义算法暂不能还原成编辑面板；可以继续演奏、保存至 SD，或选择预设替换。<button className="button small" onClick={()=>navigate('library')}>选择预设</button></div>}<div className="edit-tools"><div className="segmented"><button className={controlStyle==='knob'?'selected':''} onClick={()=>{setControlStyle('knob');localStorage.setItem('tang.controls','knob');}}>旋钮</button><button className={controlStyle==='slider'?'selected':''} onClick={()=>{setControlStyle('slider');localStorage.setItem('tang.controls','slider');}}>滑杆</button></div><span className="control-hint">拖动 · Shift 精调 · 双击复位</span><Toggle label="松键后自动同步" checked={autoSync} onChange={setAutoSync}/><span className={`save-state ${draft.dirty?'dirty':''}`}>{draft.dirty?'● 草稿已保留，尚未应用':'硬件配置已确认'}</span>{draft.dirty&&<button className="button small" onClick={()=>clearDraft(selected)}>撤销本键草稿</button>}</div><SoundDesigner draft={draft} setDraft={updateDraft} selected={selected} name={soundName} busy={busy} ready={ready&&!!m?.available&&!draftConflict&&!snapshotOnly} shared={shared} onLibrary={()=>navigate('library')} onApply={()=>void applyDraft()} scope={scope} setScope={setScope}/></>}
 {page==='library'&&<><div className="design-context"><label>载入范围<select aria-label="预设应用范围" value={scope} onChange={e=>setScope(e.target.value)}><option value="key">当前 KEY {selected+1}</option><option value="sound">共享此音色的 {shared} 个键</option><option value="all">全部 32 键</option></select></label><span>基础音色经过 Native 参数转换；FM 深度按当前定点范围缩放，不保证与旧引擎逐样本一致。</span></div><PresetBrowser bank={bank} nativeBank={nativeBank} onNative={p=>void loadNativePreset(p)} catalog={catalog} view={view} query={query} setQuery={setQuery} category={category} setCategory={setCategory} selected={selected} busy={busy||!m?.available} onLegacy={t=>void loadPreset(t)} onFm={p=>void loadFm(p)} onPreview={id=>void request('preview',{timbre_id:id}).catch(catchError)} onStop={()=>void request('preview_stop').catch(catchError)} onOpenFm={()=>navigate('design')}/></>}
 {page==='waves'&&<WaveTools view={view} selected={selected} scope={scope} transfer={wave} run={run} onDesign={()=>{clearDraft(selected);navigate('design');}} onError={catchError}/>}
 {page==='surge'&&<SurgeTools selected={selected} draft={draft} onDraft={d=>{updateDraft(d);setPage('design');setMessage('Surge 包络已提取到草稿，应用到硬件后生效。');}} onError={catchError}/>}
 {page==='device'&&<div className="device-page"><section className="panel device-overview"><div className="hardware-art"><Cpu size={55}/><span>GOWIN / 60K</span></div><div><span className="eyebrow">HARDWARE ENGINE</span><h2>Tang Mega 60K</h2><p>50 MHz · 8 复音 · 每声部 6 算子 · 32 键音色映射</p><p>当前固件：{view?.fx_available?'FX 可用':view?.filter?.available?'低通可用 · Delay/Reverb 未启用':'干声，未编译 FX'}</p></div></section><section className="panel"><div className="section-heading"><h3>连接与会话</h3></div><div className="device-connection">{connection}</div><label className="check"><input type="checkbox" disabled={!!view?.connected} checked={fresh} onChange={e=>setFresh(e.target.checked)}/>板卡刚烧录 / 复位，建立新会话</label><p className="microcopy">普通断线重连沿用原序号。仅板卡复位后才建立新会话；未确认命令可原样恢复。音色参数和按键映射在每次确认后保存到本机。</p><p>监测接口：{m?.available?'已连接，支持逐键映射、PCM 快照与数字输出延迟':'未检测到'}</p></section><section className="panel"><div className="section-heading"><h3>主输出</h3></div><Parameter label="总音量" value={volume} unit="%" disabled={!ready} onChange={setOutput}/><p>底板 3.5 mm 耳机输出 · PT8211 · 16-bit 双声道</p></section></div>}
 {page==='device'&&<StorageStatus view={view} run={run} busy={busy} onError={catchError}/>}
 {(page==='design'||page==='device')&&<MasterFilter view={view} run={run} busy={busy} onError={catchError}/>}
 {page==='device'&&<TouchSettings view={view} run={run} busy={busy} onError={catchError}/>}
 {page==='device'&&<KeyboardSettings view={view} run={run} busy={busy} onError={catchError}/>}
 {page==='device'&&<HdmiControl view={view} run={run} busy={busy} onError={catchError}/>}
 </main><footer className="statusbar"><span className={`status-led ${!stale?'good':''}`}/><p>{view?.connected?`${view.port} · ${stale?'遥测已过期':'已连接'} · KEY ${selected+1} · ${soundName}`:'离线 · 连接板卡后载入与演奏'}</p><span className="status-meta">{busy?'操作进行中':draft.dirty?'草稿已保留':'READY'}<span>STUDIO · RUST</span></span></footer></div>
 {engine.error&&<div className="error-toast" role="alert"><Activity size={18}/><div><strong>操作未完成</strong><p>{engine.error}</p></div><button className="icon-button" aria-label="关闭错误提示" onClick={()=>setError('')}><X size={16}/></button></div>}
 <Modal open={help} onClose={()=>setHelp(false)} title="从选键到声音" description="一个按键，一份明确的配置。"><ol className="help-steps"><li><b>状态显示</b><p>32 键实时状态；点键名进入设计，按住 ▶ 或电脑快捷键试听。波形和频谱来自真实 FPGA PCM 快照。</p></li><li><b>声音设计</b><p>旋钮、双振荡器和包络统一编辑。六算子通过弹窗配置，草稿切页不会丢失。选择应用范围后提交。</p></li><li><b>选择预设</b><p>基础音色与 FM1 Convert 都会发送至当前键，成功后返回设计。尚未适配的 FM1 条目明确禁用。</p></li><li><b>音色容量</b><p>同时保留 4 种音色，可分配到任意多个键，共享 8 复音。新音色优先使用空闲资源，不会悄悄改掉其他键。</p></li><li><b>实时控制</b><p>主音量即时同步；音色参数可在松键后自动同步。提交参数会停止声部，重新起音试听。</p></li></ol></Modal>
 </div></ParameterControls.Provider>;
}
