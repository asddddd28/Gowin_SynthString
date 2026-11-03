import {useState} from 'react';
import type {Action,StudioView} from './useStudioEngine';
import presets from './sd-presets.json';

export type StorageView={available:boolean|null;initialized:boolean;catalog_ready:boolean;busy:boolean;sector_error:number;catalog_error:number;sectors:number;state:string;message:string;
 service?:boolean;library_ready?:boolean;dirty?:boolean;error?:number;generation?:number;sequence?:number;preset?:number;sequence_count?:number;preset_count?:number;syncing?:boolean};
export function StorageStatus({view,run,busy,onError}:{view:StudioView|null;run:(a:Action)=>Promise<StudioView>;busy:boolean;onError:(e:unknown)=>void}){
 const s=view?.storage,connected=!!view?.connected;
 const [sequence,setSequence]=useState(0),[preset,setPreset]=useState(1),[slot,setSlot]=useState(0);
 const ready=connected&&!view?.pending&&!view?.wave_transfer&&!view?.keyboard?.calibration&&!busy;
 const available=ready&&s?.service&&s.library_ready&&!s.busy&&!s.syncing;
 const act=(operation:number,number:number)=>{void run({kind:'storage_action',operation,number,slot}).catch(onError);};
 const chosenSequence=sequence||s?.sequence||0;
 if(connected&&s?.available===false)return null;
 return <section className="panel" aria-label="SD 卡与文件库"><div className="section-heading"><h3>SD 卡与存储</h3><button className="button small" disabled={!ready} onClick={()=>void run({kind:'storage_step'}).catch(onError)}>刷新状态</button></div>
  <p role="status">{!connected?'连接板卡后读取 SD 卡状态':s?.message||'正在读取板卡 SD 状态…'}</p>
  {connected&&s?.initialized&&<p>容量 {(s.sectors*512/1e9).toFixed(1)} GB · {s.catalog_ready?'文件目录校验通过':'文件目录未就绪'}</p>}
  {s?.service?<>
   <div className="device-connection"><strong>音序存档</strong><span>{s.sequence_count??0} 段已保存{s.dirty?' · 当前录音有未保存修改':''}</span>
    <button className="button" disabled={!available} onClick={()=>act(1,0)}>保存当前录音为新编号</button>
    <label>编号<input aria-label="SD 音序编号" type="number" min={1} max={64} value={chosenSequence||''} onChange={e=>{setSequence(Math.max(1,Math.min(64,Number(e.target.value))));}}/></label>
    <button className="button" disabled={!available||!chosenSequence||s.dirty} onClick={()=>act(2,chosenSequence)}>加载并循环回放</button>
   </div>
   <div className="device-connection"><strong>SD 音色预设</strong>
    <label>预设<select aria-label="SD 预设音色" value={preset} onChange={e=>setPreset(Number(e.target.value))}>{presets.map(p=><option key={p.number} value={p.number}>{String(p.number).padStart(3,'0')} · {p.name} / {p.category}</option>)}</select></label>
    <label>文件编号<input aria-label="SD 预设编号" type="number" min={1} max={128} value={preset} onChange={e=>setPreset(Math.max(1,Math.min(128,Number(e.target.value))))}/></label>
    <label>目标音色槽<select aria-label="SD 目标音色槽" value={slot} onChange={e=>setSlot(Number(e.target.value))}>{[0,1,2,3].map(n=><option key={n} value={n}>Slot {n+1}{view?.sequencer?.locked_slots&&(view.sequencer.locked_slots&(1<<n))?' · 录音正在使用':''}</option>)}</select></label>
    <button className="button" disabled={!available} onClick={()=>act(3,preset)}>加载到 Slot {slot+1}</button>
   </div>
   <p className="microcopy">SW3 保存新音序；SW5 / SW6 切换已保存音序。HDMI 页中上下选择、按摇杆加载；未保存的录音必须先保存或用 SW2 清空。SD 操作由 FPGA 执行，退出 App 后仍可使用。</p>
   <p className="microcopy">预设加载会更新该 Slot 所有绑定琴键；录音正在使用的槽受保护。预设可通过读卡器提前放入 PRESETS 文件夹；音序保存包含各层音色与所需波表。</p>
  </>:<p className="microcopy">此固件仅提供 SD 诊断，需要更新独立存取固件后才能保存和加载。</p>}
  {connected&&s?.available&&<p className="microcopy">SD I/O 0x{s.sector_error.toString(16).padStart(2,'0')} · 目录 0x{s.catalog_error.toString(16).padStart(2,'0')} · 文件操作 0x{(s.error??0).toString(16).padStart(2,'0')}</p>}
 </section>;
}
