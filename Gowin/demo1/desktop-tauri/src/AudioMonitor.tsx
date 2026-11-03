import {useMemo,useState} from 'react';
import type {StudioView} from './useStudioEngine';

// Radix-2 FFT of a Hann-windowed, DC-removed real hardware capture. dBFS scale.
export function spectrum(samples:number[]){
 const n=samples.length;if(n<2||(n&(n-1)))return [];
 const mean=samples.reduce((a,b)=>a+b,0)/n,re=new Float64Array(n),im=new Float64Array(n);
 let sumWindow=0;
 for(let i=0;i<n;i++){const w=.5-.5*Math.cos(2*Math.PI*i/(n-1));sumWindow+=w;re[i]=(samples[i]-mean)/32768*w;}
 for(let i=1,j=0;i<n;i++){let bit=n>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j)[re[i],re[j]]=[re[j],re[i]];}
 for(let size=2;size<=n;size<<=1){const step=-2*Math.PI/size;for(let start=0;start<n;start+=size)for(let j=0;j<size/2;j++){
  const a=start+j,b=a+size/2,c=Math.cos(step*j),s=Math.sin(step*j),tr=re[b]*c-im[b]*s,ti=re[b]*s+im[b]*c;
  re[b]=re[a]-tr;im[b]=im[a]-ti;re[a]+=tr;im[a]+=ti;
 }}
 return Array.from({length:n/2},(_,i)=>Math.max(-96,20*Math.log10(Math.max(1e-9,2*Math.hypot(re[i],im[i])/sumWindow))));
}
// A contiguous half-window leaves room to find a real rising crossing. Never
// circularly rotate the capture: that would splice unrelated endpoints.
export function triggerWave(samples:number[]){
 const count=Math.min(256,samples.length),peak=samples.reduce((p,v)=>Math.max(p,Math.abs(v)),0),threshold=Math.max(4,Math.floor(peak/16));
 let armed=false;
 for(let i=0;i<=samples.length-count;i++){
  if(armed&&samples[i]>=0)return {samples:samples.slice(i,i+count),start:i,triggered:true};
  if(samples[i]<=-threshold)armed=true;
 }
 return {samples:samples.slice(0,count),start:0,triggered:false};
}
export function AudioMonitor({view}:{view:StudioView|null}){
 const [autoRange,setAutoRange]=useState(true),[triggerEnabled,setTriggerEnabled]=useState(true);
 const m=view?.monitor,samples=m?.samples??[],fft=useMemo(()=>spectrum(samples),[samples]);
 const aligned=useMemo(()=>triggerWave(samples),[samples]),wave=triggerEnabled?aligned.samples:samples;
 const fresh=!!view?.connected&&view.age_ms!==null&&view.age_ms<1500&&!!m?.captured_at_ms&&Date.now()-m.captured_at_ms<5000;
 const peak=samples.length?Math.max(...samples.map(Math.abs))/32768:0;
 const scale=autoRange&&peak>0?Math.max(1,Math.min(64,2**Math.floor(Math.log2(.9/peak)))):1;
 const path=wave.map((v,i)=>`${i?'L':'M'}${i/Math.max(1,wave.length-1)*700},${90-v/32768*75*scale}`).join(' ');
 const bins=fft.slice(1).map((db,i)=>{const hz=(i+1)*48828.125/512,x=(Math.log10(hz)-Math.log10(95.367))/(Math.log10(24414)-Math.log10(95.367))*700;return `${i?'L':'M'}${x},${165-(db+96)/96*150}`;}).join(' ');
 return <div className="monitor-plots"><section className="panel"><div className="section-heading"><h3>输出波形</h3><span className={`pill ${fresh?'good':''}`}>{fresh?'硬件 PCM':'暂无新鲜采样'}</span><label className="check" style={{marginLeft:'auto'}}><input type="checkbox" checked={autoRange} onChange={e=>setAutoRange(e.target.checked)}/>自动范围 · ×{scale}</label></div><div className="plot"><svg viewBox="0 0 700 180" preserveAspectRatio="none" role="img" aria-label="硬件输出波形"><g className="wave-grid">{[15,52.5,90,127.5,165].map(y=><path key={y} d={`M0 ${y}H700`}/>)}</g>{wave.length>0&&<path d={path} fill="none" stroke="var(--accent)" strokeWidth="1.5"/>}</svg>{!samples.length&&<div className="plot-empty">{m?.available?'正在读取第一帧 PCM…':'连接监测版固件后显示真实波形'}</div>}</div><div className="plot-labels"><span>0 ms</span><span>{triggerEnabled?256:512} 点 · 左声道 · 16 bit</span><span>{triggerEnabled?'5.24':'10.49'} ms</span></div><label className="check"><input type="checkbox" checked={triggerEnabled} onChange={e=>setTriggerEnabled(e.target.checked)}/>触发稳定 · {triggerEnabled?(aligned.triggered?'上升沿对齐':'自由运行，等待过零'):'原始快照'}</label></section>
 <section className="panel"><div className="section-heading"><h3>输出频谱</h3><span className="subtle">HANN · dBFS</span></div><div className="plot"><svg viewBox="0 0 700 180" preserveAspectRatio="none" role="img" aria-label="硬件输出频谱"><g className="wave-grid">{[15,65,115,165].map(y=><path key={y} d={`M0 ${y}H700`}/>)}</g>{fft.length>0&&<path d={bins} fill="none" stroke="var(--violet)" strokeWidth="1.5"/>}<text x="4" y="12">0 dB</text><text x="4" y="178">−96 dB</text></svg>{!fft.length&&<div className="plot-empty">频谱由同一份硬件采样计算</div>}</div><div className="plot-labels"><span>95 Hz</span><span>1 kHz</span><span>24.4 kHz</span></div></section>
 <div className="monitor-caption"><span>真实数字输出快照 · 48.828 kHz · 频率分辨率 95.37 Hz · 串口带宽限制，非连续录音</span><span>{samples.length?`峰值 ${peak?20*Math.log10(peak)>-96?(20*Math.log10(peak)).toFixed(1):'＜−96':'−∞'} dBFS`:'等待采样'} · {m?.captured_at_ms?`${Math.max(0,(Date.now()-m.captured_at_ms)/1000).toFixed(1)} s 前更新`:'未更新'}</span></div></div>;
}
