import {useEffect,useState} from 'react';
import {invoke} from '@tauri-apps/api/core';
import './synth-debug.css';
import StudioEditor from './StudioEditor';
import LatencyPanel,{type Latency} from './LatencyPanel';
type Frame={frames:number;pressed:number;delivered:number;nonzero:number;events:number;cycles:number;flags:number;key:number;raw:number;volume:number;active:number;gain:number;input_peak:number;output_peak:number;clips:number;envelope_peak:number;wave_peak:number;modulation_peak:number;stages:number;version:number;latency?:Latency|null};
type View={connected:boolean;packets:number;bad:number;age_ms:number|null;frame:Frame|null};
const db=(v:number)=>v?`${(20*Math.log10(v/8388608)).toFixed(1)} dBFS`:'−∞ dBFS';
export default function SynthDebug(){
 const [view,setView]=useState<View|null>(null),[ports,setPorts]=useState<{name:string}[]>([]),[port,setPort]=useState('COM4'),[message,setMessage]=useState('请选择 FPGA 调试串口'),[volume,setVolume]=useState(6);
 const f=view?.frame,live=!!view?.connected&&view.age_ms!==null&&view.age_ms<1000;
 useEffect(()=>{invoke<{name:string}[]>('list_ports').then(setPorts).catch(e=>setMessage(String(e)));let stop=false;let timer:ReturnType<typeof setTimeout>;
 const poll=async()=>{try{const s=await invoke<View>('synth_snapshot');if(!stop)setView(s);}catch(e){if(!stop)setMessage(String(e));}if(!stop)timer=setTimeout(poll,80);};poll();return()=>{stop=true;clearTimeout(timer);};},[]);
 useEffect(()=>{if((f?.version??0)>=2)setVolume(f?.volume??6);},[f?.volume,f?.version]);
 const connect=async()=>{try{await invoke('synth_connect',{port:view?.connected?null:port});setMessage(view?.connected?'已断开串口':'已连接，等待 FPGA 遥测');}catch(e){setMessage(String(e));}};
 const command=async(c:string)=>{try{await invoke('synth_command',{command:c});setMessage(c==='T'?'C4 一秒试音已发送':c==='P'?'串口试音已结束，实体键继续有效':c==='L'?'延迟统计清零已发送，等待回读':`音量 ${Number(c)*12.5}% 已发送，等待回读`);}catch(e){setMessage(String(e));}};
 const stages=[['振荡器',f?.wave_peak?'有波形':'等待',f?.stages?((f.stages&15)===15):false],['合成 / AM',f?.modulation_peak?'有结果':'等待',!!(f&&f.stages&32)],['ADSR 包络',`${f?.active??0} 个发声/释音声部`,!!(f&&f.stages&16)],['SVF / VCA',db(f?.input_peak??0),!!(f&&f.stages&64)],['响度与输出',db(f?.output_peak??0),!!(f&&f.nonzero)]];
 return <main className="synth-debug"><header><div><small>TANG SYNTH / FPGA LIVE LAB</small><h1>Tang Synth Studio</h1><p>32 声部 · 板载 PT8211 · 48.828 kHz · 声音由 FPGA 合成</p></div><span className={live?'live':'offline'}>{live?'● 实时连接':'○ 等待数据'}</span></header>
 <section className="synth-toolbar"><select aria-label="串口" value={port} onChange={e=>setPort(e.target.value)}>{ports.map(p=><option key={p.name}>{p.name}</option>)}</select><button onClick={connect}>{view?.connected?'断开串口':'连接 FPGA'}</button><button disabled={!live} onClick={()=>command('T')}>C4 一秒试音</button><button disabled={!live} onClick={()=>command('P')}>结束试音</button><span>{live&&f?.version===1?'旧固件已连接，电平和音量控制需新版固件':live&&message==='已连接，等待 FPGA 遥测'?'正在接收 FPGA 实时遥测':message}</span></section>
 <LatencyPanel value={f?.latency} live={live} onClear={()=>void command('L')}/>
 <StudioEditor connected={live} version={f?.version??0} pressed={f?.pressed??0} onMessage={setMessage}/><div className="synth-flow">{stages.map(([name,value,ok])=><section key={String(name)}><small>{live&&ok?'● 已观测':'○ 等待'}</small><h2>{name}</h2><strong>{value}</strong></section>)}</div>
 <div className="synth-columns"><section className="synth-panel"><h2>实体键盘 <small>亮起表示按下</small></h2><div className="synth-keys">{Array.from({length:32},(_,i)=><div key={i} className={f&&((f.pressed>>>i)&1)?'pressed':''}><b>K{String(i+1).padStart(2,'0')}</b><small>MIDI {48+i}</small></div>)}</div><p>最近采样 K{(f?.key??0)+1}：{f?.raw??'—'} · 已提交事件 {f?.events??0}</p><p>阶段标志为启动后累计观测；音色参数在上方工作台编辑，硬件状态在此核对。</p></section>
 <section className="synth-panel"><h2>响度控制</h2><label>主音量 <strong>{volume*12.5}%</strong><input aria-label="主音量" type="range" min="0" max="8" step="1" value={volume} disabled={!live||(f?.version??0)<2} onChange={e=>{setVolume(+e.target.value);void command(e.target.value);}}/></label><p>当前增益 {((f?.gain??0)/65536).toFixed(3)}× · 包括释音的声部 {f?.active??0}</p><label>输出采样峰值 <strong>{db(f?.output_peak??0)}</strong><meter min="0" max="8388608" value={f?.output_peak??0}/></label><p className={f?.clips?'synth-warning':''}>保护限幅：{f?.clips??0} 次</p><button disabled={!live} onClick={()=>command('0')}>渐变静音</button><p>复音补偿采用 1/√N，快速减小、缓慢恢复增益。电平表显示采样峰值，不是 LUFS。</p></section></div>
 <footer>帧 {f?.frames??0} · 计算 {f?.cycles??0}/1024 拍 · 状态 {f?`0x${f.flags.toString(16)}`:'—'} · 校验错误 {view?.bad??0} · {f&&(f.flags&7)?'音频异常，请停止测试':'无已报告音频错误'} · 有效遥测 {view?.packets??0}</footer></main>;
}

