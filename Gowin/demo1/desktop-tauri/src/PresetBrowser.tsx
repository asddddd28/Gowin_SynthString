import {useState} from 'react';
import {AudioLines,ChevronRight,Headphones,Keyboard,Search,Square,X} from 'lucide-react';
import {Waveform,Modal} from './components';
import type {Timbre,NativePreset} from './types';
import type {Catalog,View} from '../../../demo_test/desktop-tauri/src/VoiceStudio';

const reasons:Record<string,string>={
 'pitch EG':'音高包络尚未适配','DX LFO pitch modulation/delay':'DX LFO 音高调制 / 延迟尚未适配',
 'DX LFO amplitude modulation/delay':'DX LFO 振幅调制 / 延迟尚未适配','multi-operator feedback loop':'跨算子反馈环路尚未适配',
 'global transpose':'全局移调转换尚未适配','free-running oscillator phase':'自由运行相位尚未适配',
 'invalid global parameter range':'原厂全局参数越界，需要明确的兼容规则',
};
function reasonText(value:string){return reasons[value]??value.replace(/^op(\d): nonzero release level$/,'算子 $1 的释放终点非零，生命周期尚未适配').replace(/^op(\d): invalid parameter range$/,'算子 $1 原厂参数越界').replace(/^op(\d): invalid rates >99$/,'算子 $1 原厂包络速率超过 99').replace(/^op(\d): invalid levels >99$/,'算子 $1 原厂包络电平超过 99');}
export function PresetBrowser({bank,nativeBank,catalog,view,query,setQuery,category,setCategory,selected,busy,onLegacy,onNative,onFm,onPreview,onStop,onOpenFm}:{
 bank:Timbre[];catalog:Catalog|null;view:View|null;query:string;setQuery:(v:string)=>void;category:string;setCategory:(v:string)=>void;
 nativeBank:NativePreset[];selected:number;busy:boolean;onLegacy:(t:Timbre)=>void;onNative:(t:NativePreset)=>void;onFm:(program:number)=>void;
 onPreview:(id:number)=>void;onStop:()=>void;onOpenFm:()=>void;
}){
 const [detail,setDetail]=useState<Catalog['library'][number]|null>(null);
 const [nativeDetail,setNativeDetail]=useState<NativePreset|null>(null);
 const [loadableOnly,setLoadableOnly]=useState(true);
 const text=query.trim().toLowerCase();
 const native=nativeBank.filter(t=>(category==='全部'||category===t.category)&&`${t.title} ${t.category} ${t.description} ${t.source}`.toLowerCase().includes(text));
 const legacy=bank.filter(t=>(category==='全部'||t.category===category)&&(t.title+t.category+t.description).toLowerCase().includes(text));
 const fm=(catalog?.library??[]).filter(p=>(!loadableOnly||catalog?.presets.some(q=>q.program===p.program))&&(category==='全部'||category==='FM1 Convert')&&`${p.name} FM1 Convert ${p.program+1} ${p.algorithm}`.toLowerCase().includes(text));
 const ready=!!view?.connected&&!!view.abi&&!view.pending&&!view.wave_transfer;
 const supported=(program:number)=>!!catalog?.presets.some(p=>p.program===program);
 const describe=(p:Catalog['library'][number])=>p.blocked_by.length?p.blocked_by.map(reasonText).join('；'):'参数可转换，尚未完成数值与上板验证';
 return <div className="library-page scroll-area">
  <div className="library-intro"><div><h2>找到声音的起点。</h2><p>{bank.length} 个基础音色 · {nativeBank.length} 个 AM / PM / Drum 原生预设 · FM1 Convert {catalog?.presets.length??0} / {catalog?.library.length??0} 个可载入。</p></div><div className="target-tag"><Keyboard size={16}/>当前目标 → <b>KEY {String(selected+1).padStart(2,'0')}</b></div></div>
  <div className="library-toolbar"><div className="search-field"><Search size={16}/><input aria-label="搜索音色" placeholder="搜索音色、类别或描述…" value={query} onChange={e=>setQuery(e.target.value)}/>{query&&<button aria-label="清除搜索" onClick={()=>setQuery('')}><X size={14}/></button>}</div><div className="category-tabs">{['全部','AM','PM','Drum',...new Set(bank.map(t=>t.category)),'FM1 Convert'].map(c=><button key={c} className={category===c?'selected':''} onClick={()=>setCategory(c)}>{c}</button>)}</div></div>
  <div className="fm-library-controls"><div><b>载入至 KEY {String(selected+1).padStart(2,'0')}</b><span>基础预设与 FM1 预设使用同一条硬件通路；确认成功后返回声音设计。</span></div><button className="button small" onClick={onOpenFm}>返回当前音色<ChevronRight size={14}/></button></div>
  {(category==='全部'||category==='FM1 Convert')&&<label className="check fm-library-filter"><input type="checkbox" checked={loadableOnly} onChange={e=>setLoadableOnly(e.target.checked)}/>仅显示可载入的 FM1 音色<span>取消勾选可查看全部 128 条及具体缺项。</span></label>}
  {category==='Drum'&&<p className="notice">鼓音色固定音高，按住也会自然衰减。建议先载入到一个键试听；可同时分配最多 4 种鼓。共享低通开启时，镲片和军鼓的高频会变暗。</p>}
  <div className="preset-grid">{native.map((t,i)=><article className={`preset-card native-preset color-${i%3}`} key={t.id} data-native={t.id}><div className="fm-art"><span>{t.category} / NATIVE</span><div><AudioLines size={40}/><strong>{t.patch.operators.filter(o=>o.enabled).length} OP</strong></div><small>{t.percussive?'固定音高 · 自然衰减':'跟随琴键 · 独立算子包络'}</small></div><div className="preset-body"><span className="preset-category">{t.category} · {t.source.startsWith('Tone')?'开源参数改编':'原创'}</span><h3>{t.title}</h3><p>{t.description}</p><div className="preset-bottom"><button onClick={()=>setNativeDetail(t)}>适配说明</button><button disabled={busy||!ready} onClick={()=>onNative(t)}>载入此键<ChevronRight size={14}/></button></div></div></article>)}{legacy.map(t=><article className={`preset-card color-${t.id%3}`} key={`base:${t.id}`}><div className="preset-art"><span>{String(t.id).padStart(2,'0')} / {t.resource_id?'SINGLE CYCLE':'SYNTHESIS'}</span><Waveform wave={t.profile.wave_a} data={t.waveform} color={['var(--accent)','var(--violet)','var(--amber)'][t.id%3]} compact/><button className="preview-button" aria-label={`试听 ${t.title}`} onClick={()=>onPreview(t.id)}><Headphones size={17}/></button></div><div className="preset-body"><span className="preset-category">{t.category}</span><h3>{t.title}</h3><p>{t.description}</p><div className="preset-bottom"><span>{t.profile.mode}</span><button disabled={busy||!ready} onClick={()=>onLegacy(t)}>载入音色<ChevronRight size={14}/></button></div></div></article>)}
  {fm.map(p=><article className="preset-card fm-preset" key={`fm:${p.program}`} data-program={p.program}><div className="fm-art"><span>{String(p.program+1).padStart(3,'0')} / FM1 CONVERT</span><div><AudioLines size={40}/><strong>ALG {String(p.algorithm).padStart(2,'0')}</strong></div><small>OP 6 · OP 5 · OP 4 · OP 3 · OP 2 · OP 1</small></div><div className="preset-body"><span className={`preset-category ${supported(p.program)?'fm-qualified':'fm-blocked'}`}>{supported(p.program)?'已验证 · 可装载':p.blocked_by.length?'有待适配参数':'待验证'}</span><h3>{p.name}</h3><p>{supported(p.program)?'六算子 FM · 独立 DX 四段包络':describe(p)}</p><div className="preset-bottom"><button onClick={()=>setDetail(p)}>兼容详情</button><button disabled={busy||!ready||!supported(p.program)} title={!supported(p.program)?describe(p):!ready?'先连接 FM 固件':'松键后装载'} onClick={()=>onFm(p.program)}>{supported(p.program)?`载入此键`:'待适配'}<ChevronRight size={14}/></button></div></div></article>)}
  </div>
  {!native.length&&!legacy.length&&!fm.length&&<div className="empty-state"><Search size={30}/><h3>没有匹配的音色</h3><p>试试“AM”“PM”“鼓”，或清除筛选条件。</p><button className="button" onClick={()=>{setQuery('');setCategory('全部');}}>清除筛选</button></div>}
  <div className="library-footnote"><Headphones size={15}/>AM / PM / Drum 与 FM1 Convert 载入后从 FPGA 试听。基础音色耳机按钮仅播放电脑参考音频。<button onClick={onStop}><Square size={12}/>停止试听</button></div>
  <Modal open={!!nativeDetail} onClose={()=>setNativeDetail(null)} title={nativeDetail?.title??''} description="音色来源与硬件适配"><p>{nativeDetail?.source}</p>{nativeDetail?.source_url&&<p className="preset-source-url">{nativeDetail.source_url}</p>}<ul>{nativeDetail?.adaptation.map(note=><li key={note}>{note}</li>)}</ul><p>不需要传输波表；载入不会修改主音量、共享低通或按键音高。最多同时使用 4 种音色。</p></Modal>
  <Modal open={!!detail} onClose={()=>setDetail(null)} title={detail?.name??''} description="FM1 Convert · 原厂参数转换兼容性"><div className="fm-detail">{detail&&<><p>原厂编号 {detail.program+1} · Program ID {detail.program} · 算法 {detail.algorithm}</p><p>{supported(detail.program)?'此音色已通过整数模型、RTL 逐帧比对及实板装载；可分配至当前按键。':describe(detail)}</p><p>保留原厂 VMEM 数据；未支持的调制和反馈不会被静默忽略。当前转换属于定点硬件子集，不能等同完整 FM1 / DX7 复刻。</p></>}</div></Modal>
 </div>;
}
