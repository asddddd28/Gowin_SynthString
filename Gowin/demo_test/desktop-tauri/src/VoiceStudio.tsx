import {useCallback, useEffect, useRef, useState} from 'react';
import {voiceCall as invoke} from './voice-api';
import {Activity, AudioLines, Cable, Library, Radio, RefreshCw, SlidersHorizontal, Square} from 'lucide-react';
import './voice-studio.css';
import {NativeEditor,nativeTemplate,modeNames,type NativePatch} from './native-voice';

type Operator = {output:number; rates:number[]; levels:number[]; ratio:number|null; fixed_hz:number|null};
type Slot = {program:number|null; revision:number; operators:Operator[];native?:NativePatch|null;snapshot?:{name:string;words:number[]}|null};
type Preset = {program:number; name:string; algorithm:number; operators:Operator[]};
export type Catalog = {presets:Preset[]; library:{program:number; name:string; algorithm:number; status:string; blocked_by:string[]}[]};
type Telemetry = {flags:number; pressed:number; frames:number; underruns:number; bad_packets:number; active:number; overruns:number; cycles:number; pcm_dropped:number; fx_clips:number; fx_dropped:number; fx_cycles:number};
type Port = {name:string;description?:string;recommended?:boolean};
export type View = {wave_morph?:number;wave_transfer?:{name:string;written:number;total:number;busy_recoveries?:number}|null;wave_name?:string|null;serial?:{last_wire_ms:number;max_wire_ms:number;last_request_ms:number;max_request_ms:number;timeout_attempts:number;corrupt_frames:number;unmatched_frames:number};connected:boolean; port:string|null; abi:number|null; pending:boolean; fx_available:boolean; slots:Slot[]; volume:number; sustain:boolean; held:string[]; telemetry:Telemetry; age_ms:number|null; packets:number; retries:number; error:string};
type Action = Record<string,unknown> & {kind:string};
const names=['C','C♯','D','D♯','E','F','F♯','G','G♯','A','A♯','B'];
const noteName=(n:number)=>`${names[n%12]}${Math.floor(n/12)-1}`;
const keys=['KeyA','KeyW','KeyS','KeyE','KeyD','KeyF','KeyT','KeyG','KeyY','KeyH','KeyU','KeyJ','KeyK','KeyO','KeyL','KeyP','Semicolon'];
const copyOps=(ops:Operator[])=>ops.map(o=>({...o,rates:[...o.rates],levels:[...o.levels]}));

function Dial({label,value,min=0,max=99,onChange,disabled=false,unit=''}:{label:string;value:number;min?:number;max?:number;onChange:(v:number)=>void;disabled?:boolean;unit?:string}) {
 const drag=useRef<{y:number;value:number}|null>(null);
 const set=(v:number)=>onChange(Math.max(min,Math.min(max,Math.round(v))));
 return <label className="vs-dial"><span>{label}</span><div className="vs-dial-face" role="slider" aria-label={label} aria-valuenow={value} aria-valuemin={min} aria-valuemax={max} aria-disabled={disabled} tabIndex={disabled?-1:0}
   onKeyDown={e=>{if(disabled)return;const delta=e.key==='ArrowUp'||e.key==='ArrowRight'?1:e.key==='ArrowDown'||e.key==='ArrowLeft'?-1:0;if(delta){e.preventDefault();set(value+delta*(e.shiftKey?10:1));}}}
   onPointerDown={e=>{if(disabled)return;e.currentTarget.setPointerCapture(e.pointerId);drag.current={y:e.clientY,value};}}
   onPointerMove={e=>{if(drag.current&&!disabled)set(drag.current.value+(drag.current.y-e.clientY)*(max-min)/(e.shiftKey?600:150));}}
   onPointerUp={()=>drag.current=null} onLostPointerCapture={()=>drag.current=null}
   onWheel={e=>{if(!disabled && document.activeElement===e.currentTarget)set(value+(e.deltaY<0?1:-1));}}>
   <i style={{transform:`rotate(${-135+270*(value-min)/(max-min)}deg)`}}/></div>
   <input aria-label={`${label} 数值`} type="number" min={min} max={max} value={value} disabled={disabled} onChange={e=>set(Number(e.target.value))}/><small>{unit}</small></label>;
}

export default function VoiceStudio({embedded=false,active=true,selectedSlot=0,onSlotChange,onView}:{embedded?:boolean;active?:boolean;selectedSlot?:number;onSlotChange?:(slot:number)=>void;onView?:(view:View)=>void}){
 const [catalog,setCatalog]=useState<Catalog|null>(null),[view,setView]=useState<View|null>(null);
 const [ports,setPorts]=useState<Port[]>([]),[port,setPort]=useState(()=>localStorage.getItem('synthstring.voice.port')??''),[fresh,setFresh]=useState(false);
 const [slot,setSlot]=useState(selectedSlot),[velocity,setVelocity]=useState(100),[octave,setOctave]=useState(0),[volume,setVolume]=useState(50);
 useEffect(()=>{setSlot(selectedSlot);},[selectedSlot]);
 useEffect(()=>{onSlotChange?.(slot);},[slot,onSlotChange]);
 useEffect(()=>{if(view)onView?.(view);},[view,onView]);
 const [ops,setOps]=useState<Operator[]>([]),[dirty,setDirty]=useState(false),[search,setSearch]=useState('');
 const [nativeDraft,setNativeDraft]=useState<NativePatch|null>(null),[nativeDirty,setNativeDirty]=useState(false),[editorOpen,setEditorOpen]=useState(false);
 const dialog=useRef<HTMLDialogElement>(null);
 useEffect(()=>{if(editorOpen){dialog.current?.showModal();}else{dialog.current?.close();}},[editorOpen]);
 const [message,setMessage]=useState('连接板卡后，选择驻留音色并演奏。'),[busy,setBusy]=useState(0),[pressed,setPressed]=useState<Record<string,number>>({});
 const [midiPorts,setMidiPorts]=useState<string[]>([]),[midi,setMidi]=useState(''),[room,setRoom]=useState<boolean|null>(null);
 const queue=useRef(Promise.resolve()),pending=useRef(0),foregroundPending=useRef(0),current=useRef({view,slot,velocity,octave}),held=useRef<Record<string,number>>({});
 current.current={view,slot,velocity,octave};
 const run=useCallback((action:Action,success?:string)=>{
   const foreground=action.kind!=='poll';
   pending.current++;if(foreground)setBusy(++foregroundPending.current);
   const job=queue.current.then(async()=>{try{const next=await invoke<View>('voice_action',{action});setView(next);if(success)setMessage(success);return true;}catch(e){setMessage(String(e));try{setView(await invoke<View>('voice_snapshot'));}catch{}return false;}finally{pending.current--;if(foreground)setBusy(--foregroundPending.current);}});
   queue.current=job.then(()=>{});return job;
 },[]);
 const refresh=()=>{invoke<Port[]>('list_ports').then(next=>{setPorts(next);setPort(old=>next.some(p=>p.name===old)?old:next.find(p=>p.recommended)?.name??next[0]?.name??'');}).catch(e=>setMessage(String(e)));invoke<string[]>('synth_midi_ports').then(setMidiPorts).catch(e=>setMessage(String(e)));};
 useEffect(()=>{refresh();invoke<Catalog>('voice_catalog').then(setCatalog).catch(e=>setMessage(String(e)));let stop=false;
   const tick=async()=>{if(stop||pending.current)return;try{const next=await invoke<View>('voice_snapshot');if(stop)return;setView(next);if(next.connected&&!next.pending&&next.abi)void run({kind:'poll'});}catch(e){setMessage(String(e));}};
   void tick();const timer=setInterval(tick,150);return()=>{stop=true;clearInterval(timer);};
 },[run]);
 const connected=!!view?.connected&&!!view.abi&&!view.pending&&!view.wave_transfer;
 const selected=view?.slots[slot];
 const preset=catalog?.presets.find(p=>p.program===selected?.program);
 useEffect(()=>{setOps(copyOps(selected?.operators??[]));setDirty(false);},[slot,selected?.program,selected?.revision]);
 useEffect(()=>{setNativeDraft(selected?.native?structuredClone(selected.native):null);setNativeDirty(false);},[slot,selected?.program,selected?.revision]);
 useEffect(()=>{if(view)setVolume(Math.round(view.volume*100));},[view?.volume]);
 useEffect(()=>{if(view?.connected&&view.port){setPort(view.port);if(view.abi&&!view.pending)localStorage.setItem('synthstring.voice.port',view.port);}},[view?.connected,view?.port,view?.abi,view?.pending]);
 useEffect(()=>{if(view?.connected&&view.abi&&!view.pending)setFresh(false);},[view?.connected,view?.abi,view?.pending]);
 const note=useCallback((token:string,n:number,down:boolean,v?:number)=>{
   const c=current.current;
   if(down){if(!c.view?.connected||c.view.pending||c.view.wave_transfer||held.current[token]!==undefined)return;held.current[token]=n;}
   else {if(held.current[token]===undefined)return;n=held.current[token];delete held.current[token];}
   setPressed({...held.current});void run({kind:'note',token,note:n,velocity:v??c.velocity,slot:c.slot,pressed:down});
 },[run]);
 const release=useCallback(()=>{for(const [token,n] of Object.entries(held.current))note(token,n,false);},[note]);
 useEffect(()=>{if(editorOpen)release();},[editorOpen,release]);
 useEffect(()=>{if(!active)setEditorOpen(false);},[active]);
 useEffect(()=>{if(!active){release();setMidi('');void invoke('synth_midi_connect',{index:null}).catch(()=>{});const v=current.current.view;if(v?.connected&&v.sustain)void run({kind:'control',volume:v.volume,sustain:false});}},[active,release,run]);
 const panic=()=>{held.current={};setPressed({});void run({kind:'panic'},view?.fx_available?'已停止全部声部并清除效果尾音':'已停止全部声部');};
 useEffect(()=>{
   if(!active)return;
   const down=(e:KeyboardEvent)=>{if(e.repeat||e.ctrlKey||e.altKey||e.metaKey||(e.target as HTMLElement).closest('input,textarea,select,[role="slider"],dialog'))return;
    if(e.code==='Escape'){e.preventDefault();release();void run({kind:'panic'});return;}
    if(e.code==='Space'){e.preventDefault();const v=current.current.view;if(v?.connected)void run({kind:'control',volume:v.volume,sustain:true});return;}
    const i=keys.indexOf(e.code);if(i>=0){e.preventDefault();note(`pc:${e.code}`,60+current.current.octave*12+i,true);}};
   const up=(e:KeyboardEvent)=>{if(e.code==='Space'){const v=current.current.view;if(v?.connected)void run({kind:'control',volume:v.volume,sustain:false});}note(`pc:${e.code}`,0,false);};
   const blur=()=>{release();const v=current.current.view;if(v?.connected&&v.sustain)void run({kind:'control',volume:v.volume,sustain:false});};
   window.addEventListener('keydown',down);window.addEventListener('keyup',up);window.addEventListener('blur',blur);
   return()=>{window.removeEventListener('keydown',down);window.removeEventListener('keyup',up);window.removeEventListener('blur',blur);release();};
 },[note,release,run,active]);
 useEffect(()=>{if(!midi||!active)return;let reading=false;const timer=setInterval(async()=>{if(reading)return;reading=true;try{const events=await invoke<number[][]>('synth_midi_events');for(const [status,n,v] of events){const op=status&240,token=`midi:${status&15}:${n}`;if(op===144)note(token,n,v>0,v||1);else if(op===128)note(token,n,false);else if(op===176&&n===64){const state=current.current.view;if(state?.connected)void run({kind:'control',volume:state.volume,sustain:v>=64});}else if(op===176&&(n===123||n===120)){release();void run({kind:'panic'});}}}catch(e){setMessage(String(e));}finally{reading=false;}},8);return()=>clearInterval(timer);},[midi,note,release,run,active]);
 const volumeTimer=useRef<ReturnType<typeof setTimeout>|null>(null);
 useEffect(()=>()=>{if(volumeTimer.current)clearTimeout(volumeTimer.current);},[]);
 const changeVolume=(v:number)=>{setVolume(v);if(volumeTimer.current)clearTimeout(volumeTimer.current);volumeTimer.current=setTimeout(()=>{void run({kind:'control',volume:v/100,sustain:current.current.view?.sustain??false});},120);};
 const updateOp=(index:number,change:(o:Operator)=>void)=>{setOps(old=>{const next=copyOps(old);change(next[index]);return next;});setDirty(true);};
 const load=(program:number)=>{release();void run({kind:'load',program,slot,operators:null},`音色已装入槽 ${slot+1}`);};
 const telemetry=view?.telemetry;
 const activeVoices=(telemetry?.active??0).toString(2).replaceAll('0','').length;
 const stale=view?.age_ms==null||view.age_ms>2000;
 const whites=Array.from({length:25},(_,i)=>i).filter(i=>![1,3,6,8,10].includes(i%12));
 const blacks=Array.from({length:25},(_,i)=>i).filter(i=>[1,3,6,8,10].includes(i%12));
 const heldNotes=new Set(Object.values(pressed));
 const isPlaying=(n:number)=>heldNotes.has(n)||(n>=48&&n<80&&((telemetry?.pressed??0)>>> (n-48)&1)!==0);
 return <main className={`voice-studio ${embedded?'embedded':''}`}>
  <header className="vs-header"><div className="vs-brand"><AudioLines size={30}/><div><h1>SynthString <span>VOICE STUDIO</span></h1><p>FM1 音色实验室 · 6 算子 FM · 8 复音</p></div></div><div className={`vs-badge ${connected&&!stale?'online':''}`}><i/>{connected?(stale?'遥测已过期':'硬件已连接'):'等待连接'}<code>{view?.abi?`ABI ${view.abi.toString(16).padStart(8,'0')}`:'协议 5'}</code></div></header>
  <section className="vs-connection"><Cable size={18}/><select aria-label="串口" value={port} disabled={!!view?.connected} onChange={e=>setPort(e.target.value)}>{!ports.some(p=>p.name===port)&&<option>{port}</option>}{ports.map(p=><option key={p.name} value={p.name}>{p.name}{p.description?` · ${p.description}`:''}{p.recommended?'（FTDI 调试口）':''}</option>)}</select><button title="刷新设备" onClick={refresh}><RefreshCw size={15}/></button>
   <button className="primary" disabled={busy>0} onClick={()=>view?.connected?(release(),void run({kind:'disconnect'},'已断开连接')):void run({kind:'connect',port,fresh},'已连接并校验固件')}>{view?.connected?'停止并断开':'连接板卡'}</button>
   <label><input type="checkbox" checked={fresh} disabled={!!view?.connected} onChange={e=>setFresh(e.target.checked)}/>板卡刚烧录 / 复位，建立新会话</label><span className="vs-spacer"/><button className="danger" disabled={!connected} onClick={panic}><Square size={14}/>紧急停止 <kbd>Esc</kbd></button>
  </section>
  <div className={`vs-message ${view?.pending||view?.error?'warning':''}`} role="status">{view?.error||message}{view?.pending&&<button onClick={()=>void run({kind:'recover'},'已恢复未确认请求')}>原样恢复请求</button>}<small>{busy?'正在同步…':`${view?.packets??0} 包 · ${view?.retries??0} 次重试（本次连接）`}</small></div>
  <section className="vs-section"><div className="vs-title"><h2><Radio size={18}/>驻留音色</h2><span>4 个槽位 · 选择后用于 App / MIDI 新音符；实体键盘当前固定使用槽 1</span></div>
   <div className="vs-slots">{Array.from({length:4},(_,i)=>{const s=view?.slots[i],p=catalog?.presets.find(p=>p.program===s?.program);return <button key={i} className={`vs-slot ${slot===i?'selected':''}`} onClick={()=>setSlot(i)}><small>SLOT 0{i+1}{slot===i?' · 当前演奏':''}</small><strong>{s?.native?.name??p?.name??'等待板卡确认'}</strong><span>{s?.native?'Native · FM / AM / 波表':p?`算法 ${p.algorithm} · ${p.program+1} / 128`:'连接后读取本地会话'}<AudioLines size={22}/></span></button>;})}</div>
  </section>
  <section className="vs-section vs-config"><div className="vs-title"><h2><SlidersHorizontal size={18}/>音色配置</h2><div className="vs-buttons"><button onClick={()=>setEditorOpen(true)}>六算子配置</button>{nativeDraft&&<button className="primary" disabled={!connected||busy>0||!nativeDirty} onClick={()=>{release();held.current={};setPressed({});void run({kind:'load_native',slot,patch:nativeDraft},'音色已提交，请重新按键试听').then(ok=>{if(ok)setNativeDirty(false);});}}>提交音色至 FPGA</button>}</div></div>
   <div className="vs-config-toolbar"><label>合成方式<select aria-label="Voice 合成方式" value={nativeDraft?(nativeDraft.operators[1]?.wave==='wavetable'?'wavetable':nativeDraft.operators[1]?.mode??'pm'):'dx'} onChange={e=>{if(e.target.value==='dx'){setNativeDraft(null);setNativeDirty(false);}else{setNativeDraft(nativeTemplate(e.target.value));setNativeDirty(true);}}}>{!nativeDraft||selected?.program!=null?<option value="dx">FM1 / DX 六算子</option>:null}{Object.entries(modeNames).map(([id,name])=><option value={id} key={id}>{name}</option>)}</select></label>{nativeDraft&&<label>音色名称<input aria-label="Voice 音色名称" value={nativeDraft.name} maxLength={80} onChange={e=>{setNativeDraft({...nativeDraft,name:e.target.value});setNativeDirty(true);}}/></label>}<span className="vs-muted">目标槽 {slot+1} · {nativeDirty?'草稿未提交':'已确认配置'}</span></div>
   {nativeDraft?<><NativeEditor patch={nativeDraft} onChange={p=>{setNativeDraft(p);setNativeDirty(true);}}/><p className="vs-muted">提交会停止当前声部并更换此槽音色。PM/FM 深度以周期计，AM/Ring 深度为 0–1。共享波表：{view?.wave_name??'启动默认正弦'}；在波表工坊上传相邻两帧。</p></>:<p className="vs-muted">{preset?.name??'从音色浏览器选择 FM1 音色，或在上方创建 Native 音色'} · 六算子频率、电平及 DX 包络在弹窗中配置。</p>}
  </section>
  <section className="vs-section vs-perform"><div className="vs-title"><h2><AudioLines size={18}/>演奏</h2><span>拖动旋钮 · Shift 精调 · 聚焦后滚轮 / 方向键调整</span></div><div className="vs-performance-controls">
   <Dial label="主音量" value={volume} max={100} onChange={changeVolume} disabled={!connected} unit="%"/><Dial label="起音力度" value={velocity} min={1} max={127} onChange={setVelocity}/>
   <div className="vs-control-stack"><label>键盘八度<select value={octave} onChange={e=>{release();setOctave(Number(e.target.value));}}>{[-2,-1,0,1,2].map(n=><option value={n} key={n}>{n>0?'+':''}{n}</option>)}</select></label><label><input type="checkbox" disabled={!connected} checked={view?.sustain??false} onChange={e=>void run({kind:'control',volume:view?.volume??.5,sustain:e.target.checked})}/>延音 <kbd>Space</kbd></label></div>
   <div className="vs-control-stack"><label>MIDI 输入<select value={midi} onChange={async e=>{release();const v=e.target.value;try{await invoke('synth_midi_connect',{index:v===''?null:Number(v)});setMidi(v);}catch(error){setMessage(String(error));}}}><option value="">未连接</option>{midiPorts.map((p,i)=><option key={i} value={i}>{p}</option>)}</select></label><span className="vs-muted">原始 MIDI 音高 · CC64 延音</span></div>
   <div className="vs-control-stack"><span>和弦试听（按住）</span><div className="vs-buttons">{[['C 大调',[0,4,7]],['C 小调',[0,3,7]]].map(([label,intervals])=><button key={String(label)} disabled={!connected} onPointerDown={e=>{e.currentTarget.setPointerCapture(e.pointerId);(intervals as number[]).forEach(n=>note(`chord:${label}:${n}`,60+octave*12+n,true));}} onPointerUp={()=>{(intervals as number[]).forEach(n=>note(`chord:${label}:${n}`,0,false));}} onLostPointerCapture={()=>{(intervals as number[]).forEach(n=>note(`chord:${label}:${n}`,0,false));}}>{label}</button>)}</div></div>
   <div className="vs-control-stack"><span>{view?.fx_available?'共享效果':'干声固件 · FX 未编译'}</span><div className="vs-buttons"><button disabled={!connected||!view?.fx_available} className={room===false?'chosen':''} onClick={()=>void run({kind:'fx',room:false},'已切换干声').then(ok=>{if(ok)setRoom(false);})}>干声</button><button disabled={!connected||!view?.fx_available} className={room===true?'chosen':''} onClick={()=>void run({kind:'fx',room:true},'已启用空间效果').then(ok=>{if(ok)setRoom(true);})}>Delay + Reverb</button></div></div>
  </div><div className="vs-keyboard" aria-label="演奏键盘">{[...whites,...blacks].map(i=>{const n=60+octave*12+i,black=blacks.includes(i),before=whites.filter(v=>v<i).length;return <button key={i} aria-label={noteName(n)} disabled={!connected} className={`${black?'black':'white'} ${isPlaying(n)?'playing':''}`} style={black?{left:`${before/whites.length*100-2}%`,width:'4%'}:{left:`${whites.indexOf(i)/whites.length*100}%`,width:`${100/whites.length}%`}}
    onPointerDown={e=>{e.preventDefault();e.currentTarget.setPointerCapture(e.pointerId);note(`pointer:${e.pointerId}`,n,true);}}
    onPointerUp={e=>note(`pointer:${e.pointerId}`,n,false)} onLostPointerCapture={e=>note(`pointer:${e.pointerId}`,n,false)}><kbd>{keys[i]?.replace('Key','').replace('Semicolon',';')}</kbd><span>{noteName(n)}</span></button>;})}</div><p className="vs-muted">电脑键盘从 A = C{4+octave} 开始，W / E 等对应黑键。失去焦点会松开 App 音符；实体琴键独立工作。</p></section>
  <div className="vs-bottom">{!embedded&&<section className="vs-section"><div className="vs-title"><h2><Library size={18}/>音色库</h2><input placeholder="搜索 128 个原厂音色" aria-label="搜索音色" value={search} onChange={e=>setSearch(e.target.value)}/></div><p className="vs-muted">已验证 {catalog?.presets.length??0} 个音色，可替换装入 4 个驻留槽；其余条目展示兼容性限制，暂不装载。</p><div className="vs-library">{catalog?.library.filter(p=>`${p.name} ${p.program+1}`.toLowerCase().includes(search.toLowerCase())).map(p=>{const supported=catalog.presets.some(v=>v.program===p.program);return <div className="vs-library-row" key={p.program}><code>{String(p.program+1).padStart(3,'0')}</code><strong>{p.name}</strong><span>ALG {p.algorithm}</span><button disabled={!connected||!supported||busy>0} title={supported?'装入当前槽位':(p.blocked_by||[]).join('；')||'尚未验证'} onClick={()=>load(p.program)}>{supported?`装入槽 ${slot+1}`:'待适配'}</button></div>;})}</div></section>}
  <section className="vs-section"><div className="vs-title"><h2><Activity size={18}/>硬件遥测</h2><span className={stale?'vs-muted':'vs-live'}>{stale?'暂无新鲜数据':'实时'}</span></div><div className="vs-meters"><div><strong>{activeVoices}<small> / 8</small></strong><span>活动声部</span></div><div><strong>{telemetry?.cycles??'—'}<small> / 1024</small></strong><span>Voice 最近帧时钟数</span></div><div><strong>{telemetry?.frames?.toLocaleString()??'—'}</strong><span>PCM 帧计数</span></div><div><strong>{telemetry?.fx_cycles??'—'}</strong><span>FX 最近帧时钟数</span></div></div><dl className="vs-telemetry"><dt>音频欠载 / 丢帧</dt><dd>{telemetry?.underruns??'—'} / {telemetry?.pcm_dropped??'—'}</dd><dt>Voice 超时 / FX 丢帧</dt><dd>{telemetry?.overruns??'—'} / {telemetry?.fx_dropped??'—'}</dd><dt>FX 限幅 / 通信坏包</dt><dd>{telemetry?.fx_clips??'—'} / {telemetry?.bad_packets??'—'}</dd><dt>实体键状态位</dt><dd><code>{telemetry?`0x${(telemetry.pressed>>>0).toString(16).padStart(8,'0')}`:'—'}</code></dd><dt>串口往返 / 整次请求</dt><dd>{view?.serial?.last_wire_ms??'—'} / {view?.serial?.last_request_ms??'—'} ms</dd><dt>最慢请求 / 超时尝试</dt><dd>{view?.serial?.max_request_ms??'—'} ms / {view?.serial?.timeout_attempts??0}</dd><dt>回包校验失败 / 过期回包</dt><dd>{view?.serial?.corrupt_frames??0} / {view?.serial?.unmatched_frames??0}</dd><dt>本机未松开输入</dt><dd>{view?.held.length??0}</dd></dl><p className="vs-muted">板端：50 MHz / 1024 ≈ 48.828 kHz。状态取自串口回读；未提供硬件回读的音色参数由本机会话保存。请勿同时使用其他串口控制程序。</p></section></div>
  <dialog className="vs-dialog" ref={dialog} aria-label="六算子配置" onCancel={e=>{e.preventDefault();setEditorOpen(false);}} onClose={()=>setEditorOpen(false)}><div className="vs-dialog-header"><h2>六算子配置 · 槽 {slot+1}</h2><button aria-label="关闭六算子配置" onClick={()=>setEditorOpen(false)}>关闭 ×</button></div>{nativeDraft?<><NativeEditor advanced patch={nativeDraft} onChange={p=>{setNativeDraft(p);setNativeDirty(true);}}/><p className="vs-muted">关闭窗口保留本槽草稿，点击主界面的“提交音色至 FPGA”后生效。</p></>:<>
  <section className="vs-section"><div className="vs-title"><h2><SlidersHorizontal size={18}/>六算子编辑 <small>{preset?.name??'尚未载入'}</small></h2><div className="vs-buttons"><button disabled={!preset} onClick={()=>{setOps(copyOps(preset!.operators));setDirty(true);}}>恢复音色默认值</button><button className="primary" disabled={!connected||!dirty||busy>0||!preset} onClick={()=>void run({kind:'load',slot,program:selected?.program,operators:ops},'六算子参数已提交；重新按键试听')}>{dirty?'提交参数至 FPGA':'参数已同步'}</button></div></div>
   <p className="vs-muted">比率 / 固定频率、输出电平和 DX 四段包络可编辑；算法与路由沿用音色定义。释放目标 L4 当前为 0。请松键后提交并重新起音。</p>
   <div className="vs-operators">{ops.map((op,i)=><article className="vs-operator" key={i}><div className="vs-op-heading"><strong>OP {6-i}</strong><span>{op.fixed_hz==null?'比率模式':'固定频率'}</span></div><div className="vs-op-top"><Dial label={`OP${6-i} 电平`} value={op.output} onChange={v=>updateOp(i,o=>o.output=v)}/><label>{op.fixed_hz==null?'频率比':'频率 Hz'}<input type="number" step={op.fixed_hz==null?.01:1} min="0" max={op.fixed_hz==null?64:24414} value={op.fixed_hz??op.ratio??0} onChange={e=>updateOp(i,o=>{if(o.fixed_hz==null)o.ratio=Number(e.target.value);else o.fixed_hz=Number(e.target.value);})}/></label></div><div className="vs-eg-grid"><span>段</span><span>速率 R</span><span>电平 L</span>{op.rates.map((r,k)=><div className="vs-eg-row" key={k}><b>{k+1}</b><input aria-label={`OP${6-i} R${k+1}`} type="number" min="0" max="99" value={r} onChange={e=>updateOp(i,o=>o.rates[k]=Number(e.target.value))}/><input aria-label={`OP${6-i} L${k+1}`} type="number" min="0" max="99" disabled={k===3} value={op.levels[k]} onChange={e=>updateOp(i,o=>o.levels[k]=Number(e.target.value))}/></div>)}</div></article>)}</div>
  </section>
</>}</dialog>
  <footer>原厂素材：M-VAVE FM1 · 当前为功能子集适配，不等同于完整 DX7 / FM1 声音复刻。</footer>
 </main>;
}
