import {useEffect,useState} from 'react';
import {Parameter,Toggle} from './components';
import type {StudioView,Action} from './useStudioEngine';
export type FilterProfile={enabled:boolean;cutoff_hz:number;lfo_enabled:boolean;lfo_rate_hz:number;lfo_depth_oct:number;lfo_shape:number};
export type FilterView={available:boolean;profile:FilterProfile;applied:boolean;revision:number;actual_cutoff_hz:number;enabled:boolean;lfo_active:boolean};
const defaults:FilterProfile={enabled:false,cutoff_hz:2000,lfo_enabled:false,lfo_rate_hz:1,lfo_depth_oct:2,lfo_shape:0};
const signature=(p:FilterProfile)=>JSON.stringify([p.enabled,p.cutoff_hz,p.lfo_enabled,p.lfo_rate_hz,p.lfo_depth_oct,p.lfo_shape]);
export function MasterFilter({view,run,busy,onError}:{view:StudioView|null;run:(a:Action,b?:boolean)=>Promise<StudioView>;busy:boolean;onError:(e:unknown)=>void}){
 const f=view?.filter,profile=f?.profile??defaults;
 const [draft,setDraft]=useState<FilterProfile|null>(null),[saving,setSaving]=useState(false),[failed,setFailed]=useState(false);
 const current=draft??profile,draftKey=draft?signature(draft):'',savedKey=signature(profile);
 const ready=!!view?.connected&&!!f?.available&&!view.pending&&!view.wave_transfer&&!view.keyboard?.calibration;
 const change=(update:Partial<FilterProfile>)=>{setFailed(false);setDraft(old=>({...old??profile,...update}));};
 const commit=async(next:FilterProfile)=>{
  if(!ready||saving)return;setSaving(true);setFailed(false);
  try{await run({kind:'filter_apply',profile:next},true);setDraft(old=>old&&signature(old)!==signature(next)?old:null);}
  catch(e){setFailed(true);onError(e);}finally{setSaving(false);}
 };
 useEffect(()=>{
  if(!draft||!ready||busy||saving||failed||draftKey===savedKey&&f?.applied)return;
  const timer=setTimeout(()=>void commit(draft),180);return()=>clearTimeout(timer);
 },[draftKey,savedKey,ready,busy,saving,failed,f?.applied]);
 return <section className="panel master-filter" aria-label="全局低通滤波器"><div className="section-heading"><h3>全局低通 · Cutoff LFO</h3><span className="badge">共享双声道 · 12 dB/oct</span></div>
 <p>作用于全部音色混音后的输出。旋钮自动同步，播放中即可调节；LFO 在 FPGA 上持续运行。</p>
 {!f?.available&&<p className="microcopy">{view?.connected?'当前固件尚未提供全局低通，请更新固件。':'连接板卡后启用滤波控制。'}</p>}
 <div className="master-filter-toggles"><Toggle label="启用低通" checked={current.enabled} disabled={!ready} onChange={enabled=>change({enabled})}/><Toggle label="LFO 调制 Cutoff" checked={current.lfo_enabled} disabled={!ready} onChange={lfo_enabled=>change({lfo_enabled})}/><label>LFO 波形<select aria-label="滤波 LFO 波形" disabled={!ready} value={current.lfo_shape} onChange={e=>change({lfo_shape:Number(e.target.value)})}><option value={0}>正弦</option><option value={1}>三角</option></select></label></div>
 <div className="master-filter-parameters"><Parameter label="Cutoff" value={current.cutoff_hz} min={20} max={18000} step={1} unit="Hz" logarithmic disabled={!ready} onChange={cutoff_hz=>change({cutoff_hz})}/><Parameter label="滤波 LFO 速率" value={current.lfo_rate_hz} min={.05} max={20} step={.05} unit="Hz" logarithmic disabled={!ready} onChange={lfo_rate_hz=>change({lfo_rate_hz})}/><Parameter label="滤波 LFO 深度" value={current.lfo_depth_oct} min={0} max={6} step={.1} unit="oct" disabled={!ready} onChange={lfo_depth_oct=>change({lfo_depth_oct})}/></div>
 <p className="microcopy">深度 1 oct 表示围绕基础 Cutoff 上下各扫一个倍频程；频率限制在 20～18000 Hz。首版无共振，开关与频率变化均平滑过渡。</p>
 <div className="keyboard-actions"><span role="status">{saving?'正在同步…':failed?'同步失败，请重试':draftKey&&draftKey!==savedKey?'等待同步…':f?.applied?'硬件已确认':'本机配置尚未恢复到板卡'}</span><span>当前 {f?.enabled?`${Math.round(f.actual_cutoff_hz)} Hz${f.lfo_active?' · LFO 扫频':''}`:'旁路'}</span>{(!f?.applied||failed)&&<button className="button" disabled={!ready||busy||saving} onClick={()=>void commit(current)}>恢复滤波设置</button>}</div>
 </section>;
}
