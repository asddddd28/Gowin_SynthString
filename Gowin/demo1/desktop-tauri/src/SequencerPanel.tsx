import {useState} from 'react';
import type {Action,StudioView} from './useStudioEngine';
import './sequencer.css';

export type SequencerView={available:boolean;recording:boolean;playing:boolean;finalizing:boolean;full:boolean;fault:boolean;locked_slots:number;buttons:number;bpm:number;events:number;capacity:number;ppq:number;loop_ticks:number;position:number;archive_available?:boolean;archive_busy?:boolean;button_layout?:number;library_message?:string;waiting_first_note?:boolean};

export function SequencerPanel({view,run,busy,onError}:{view:StudioView|null;run:(a:Action)=>Promise<StudioView>;busy:boolean;onError:(e:unknown)=>void}){
 const s=view?.sequencer;
 const [tempo,setTempo]=useState<number|null>(null),[confirmClear,setConfirmClear]=useState(false);
 if(!s?.available)return null;
 const ready=!!view?.connected&&!view.pending&&!view.wave_transfer&&!view.keyboard?.calibration&&!busy&&!s.finalizing&&!s.archive_busy;
 const bars=s.ppq?s.loop_ticks/(s.ppq*4):0,beat=s.ppq?Math.floor(s.position/s.ppq)%4:0;
 const send=(action:number,bpm?:number)=>void run({kind:'sequencer_control',action,bpm:bpm??null}).catch(onError);
 return <section className="panel sequencer" aria-label="四拍循环音序器">
  <div className="section-heading"><h3>循环音序器</h3><span className={`badge ${s.recording?'recording':''}`}>{s.fault?'回放异常，请清空后重试':s.archive_busy?'正在传输音序快照…':s.finalizing?'正在截取完整小节…':s.waiting_first_note?'等待首音 · 节拍已开始':s.recording?(bars?'正在叠录':'正在录制'):s.playing?'循环播放':bars?'已暂停':'等待录制'}</span></div>
  <div className="sequencer-transport">
   <button className={`button ${s.recording?'recording':'primary'}`} disabled={!ready||s.fault} onClick={()=>send(1)}>{s.recording?'停止录制':bars?'追加一层':'开始录制'} <small>SW1</small></button>
   <button className="button" disabled={!ready||!bars||s.recording||s.fault} onClick={()=>send(3)}>{s.playing?'暂停':'播放'} <small>{(s.button_layout??1)>=2?'SW4':'SW5'}</small></button>
   <button className="button" disabled={!ready||(!bars&&!s.events&&!s.recording&&!s.fault)} onClick={()=>setConfirmClear(true)}>清空 <small>SW2</small></button>
   <label>BPM <input aria-label="音序器 BPM" type="number" min={20} max={300} step={1} value={tempo??s.bpm} disabled={!ready} onChange={e=>setTempo(Number(e.target.value))}/></label>
   <button className="button" disabled={!ready||tempo===null||!Number.isInteger(tempo)||tempo<20||tempo>300} onClick={()=>{if(tempo!==null)void run({kind:'sequencer_control',action:4,bpm:tempo}).then(()=>setTempo(null)).catch(onError);}}>设置速度</button>
   <div className="sequencer-beats" aria-label={`第 ${beat+1} 拍`}>{[0,1,2,3].map(b=><span key={b} className={(s.recording||s.playing)&&beat===b?'active':''}>{b+1}</span>)}</div>
  </div>
  {confirmClear&&<div className="sequencer-confirm" role="alert">清空所有录音层并释放保留的音色？<button className="button" onClick={()=>{send(2);setConfirmClear(false);}}>确认清空</button><button className="button" onClick={()=>setConfirmClear(false)}>取消</button></div>}
  <div className="sequencer-readout"><span>{bars?`${bars} 小节循环`:'第一遍录制定长度'}</span><span>{s.events} / {s.capacity} 个音符事件</span><span>保留音色：{[0,1,2,3].filter(i=>s.locked_slots&(1<<i)).map(i=>`槽 ${i+1}`).join('、')||'无'}</span></div>
  <p className="microcopy">SW1 开始 / 停止录制；停止时丢弃未完成的小节，随后循环播放。之后按同样长度叠录，已有层音色保持不变。{(s.button_layout??1)>=2?'SW3 保存、SW5 / SW6 前后切换音序的按键事件已接入，等待 SD 存取服务；BPM 在上方设置。':'SW3 / SW4 调整速度。'}录制时每小节第一拍为重音。当前录制实体琴键与触摸拨弦事件。</p>
  {s.library_message&&<p role="status">{s.library_message}</p>}
  {(s.button_layout??1)>=3&&<p className="microcopy">首次录音窗口提前约 20 ms，稍早于强拍的首音归入下一小节。自动去除首尾纯空小节，保留中间休止和长音；叠录沿用原循环长度。</p>}
  {s.full&&<p role="alert">事件存储已满，已保留最后一个完整小节；请清空后重新录制。</p>}
  <p className="microcopy">最多保留 4 个驻留音色，回放与现场演奏共用 8 个声部；主滤波、触摸调制仍作用于整体输出。SD 持久保存尚未启用，当前录音在断电后会丢失。</p>
 </section>;
}
