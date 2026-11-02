import {useEffect, useRef, useState} from 'react';
import './latency-panel.css';

export type Latency = {
 records:number;key:number;flags:number;total:number;qualify:number;queue:number;compute:number;
 output:number;mix:number;minimum:number;maximum:number;sum:number;late:number;timeouts:number;
 overwritten:number;scan_period:number;physical_records:number;remote_records:number;tick:number;
 start:number;dac:number;budget:number;pending:number;onset_wait:number;canceled:number;
};
const milliseconds=(cycles:number)=>cycles/50000;
const duration=(cycles:number)=>`${milliseconds(cycles).toFixed(3)} ms`;

export default function LatencyPanel({value,live,onClear}:{value:Latency|null|undefined;live:boolean;onClear:()=>void}){
 const [history,setHistory]=useState<{sequence:number;total:number;key:number;physical:boolean}[]>([]);
 const previous=useRef(0);
 useEffect(()=>{
  if(!value){previous.current=0;setHistory([]);return;}
  if(value.records<previous.current)setHistory([]);
  if(value.records&&value.records!==previous.current){
   setHistory(h=>[...h.slice(-79),{sequence:value.records,total:value.total,key:value.key,physical:!!(value.flags&1)}]);
  }
  previous.current=value.records;
 },[value]);
 const has=!!value?.records;
 const scale=Math.max(value?.budget??500000,...history.map(h=>h.total),1);
 const points=history.map((h,i)=>`${8+i*584/Math.max(1,history.length-1)},${96-h.total/scale*80}`).join(' ');
 const parts=value?[
  ['扫描确认',value.qualify],['事件排队',value.queue],['首轮计算',value.compute],
  ['非零起音等待',value.onset_wait],['混音及 DAC 等待',value.output],
 ] as const:[];
 const pending=value?Array.from({length:32},(_,i)=>(value.pending>>>i)&1).reduce((a,b)=>a+b,0):0;
 const exportCsv=()=>{
  const rows=['sequence,key,source,total_ms',...history.map(h=>`${h.sequence},${h.key+1},${h.physical?'keyboard':'remote'},${milliseconds(h.total).toFixed(6)}`)];
  const url=URL.createObjectURL(new Blob(['\ufeff'+rows.join('\r\n')],{type:'text/csv;charset=utf-8'}));
  const link=document.createElement('a');link.href=url;link.download='TangSynth-latency.csv';link.click();URL.revokeObjectURL(url);
 };
 return <section className="synth-panel latency-panel" aria-label="延迟监督器">
  <div className="latency-heading"><div><h2>延迟监督器 <small>{value?'FPGA 硬件计时 · 20 ns 分辨率':'需要协议 4 固件'}</small></h2>
   <p>首次越过门限的 ADC 样本 → 首个非零声部参与的非零 DAC 帧</p></div>
   <div><button disabled={!history.length} onClick={exportCsv}>导出曲线 CSV</button><button disabled={!live||!value} onClick={onClear}>清零统计</button></div></div>
  <div className="latency-summary">
   <div className={has&&value.total>value.budget?'latency-over':''}><small>最近一次</small><strong>{has?duration(value.total):'—'}</strong><span>{has?`K${String(value.key+1).padStart(2,'0')} · ${value.flags&1?'实体键盘':'远程 / 自测'}`:'按一个实体键开始测量'}</span></div>
   <div><small>最小 / 平均 / 最大</small><strong>{has?`${milliseconds(value.minimum).toFixed(3)} / ${milliseconds(value.sum/value.records).toFixed(3)} / ${milliseconds(value.maximum).toFixed(3)}`:'—'}</strong><span>毫秒 · {value?.records??0} 个已完成事件</span></div>
   <div><small>预算与异常</small><strong>{duration(value?.budget??500000)}</strong><span>超预算 {value?.late??0} · 超时 {value?.timeouts??0} · 被新事件覆盖 {value?.overwritten??0}</span></div>
  </div>
  <div className="latency-body"><div><svg viewBox="0 0 600 112" role="img" aria-label="最近延迟遥测曲线">
   <path d="M8 96 H592" className="latency-axis"/>
   <path d={`M8 ${96-(value?.budget??500000)/scale*80} H592`} className="latency-budget"/>
   <polyline points={points} fill="none" className="latency-line"/>
  </svg><p>曲线记录最近 {history.length} 次有效回传；连奏时明细可能跳过，FPGA 累计统计仍覆盖全部完成事件。</p></div>
  <dl>{parts.map(([name,cycles])=><div key={name}><dt>{name}</dt><dd>{has?duration(cycles):'—'}</dd></div>)}</dl></div>
  <p>实体键 {value?.physical_records??0} · 远程 / 自测 {value?.remote_records??0} · 等待中 {pending} · 未通过确认 {value?.canceled??0}。
   {has&&!!(value.flags&1)&&`该键扫描周期 ${duration(value.scan_period)}；按下到首次采样还可能额外等待一个扫描周期。`}</p>
  <p className="latency-boundary">终点为 PT8211 左声道数据锁存，不包含 DAC、功放及声学延迟。非零数据不代表已经达到可闻响度；远程测量从 FPGA 接受演奏状态开始，不包含电脑与串口传输。</p>
 </section>;
}
