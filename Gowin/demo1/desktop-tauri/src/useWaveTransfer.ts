import {useRef,useState} from 'react';
import type {Action,StudioView} from './useStudioEngine';
import type {NativePatch} from '../../../demo_test/desktop-tauri/src/native-voice';

type Intent={port:string;wave:string;key:number;scope:string;patch:NativePatch;title:string};
const storage='tang.wave.intent';
function readIntent():Intent|null{try{return JSON.parse(localStorage.getItem(storage)??'null');}catch{return null;}}

// Owned by App, not a tool page. Navigation cannot destroy the transfer loop.
export function useWaveTransfer(view:StudioView|null,run:(a:Action,background?:boolean)=>Promise<StudioView>,onApplied:(key:number,title:string)=>void){
 const [running,setRunning]=useState(false),[message,setMessage]=useState(''),[intent,setIntent]=useState<Intent|null>(readIntent);
 const current=useRef(view);current.current=view;
 const intentRef=useRef(intent),active=useRef(false),paused=useRef(false),applied=useRef(onApplied);applied.current=onApplied;
 const remember=(value:Intent|null)=>{intentRef.current=value;setIntent(value);value?localStorage.setItem(storage,JSON.stringify(value)):localStorage.removeItem(storage);};
 const drive=async(initial?:{name:string;samples:number[];morph:number},target?:Omit<Intent,'port'|'wave'>)=>{
  if(active.current)return;
  active.current=true;paused.current=false;setRunning(true);setMessage('正在传输；可以切换页面，暂停后保留已确认位置。');
  try{
   let next=current.current;if(!next?.connected)throw Error('请先连接板卡');
   if(initial){
    if(next.wave_transfer)throw Error('请先继续完成当前波表');
    remember(target?{...target,port:next.port!,wave:initial.name}:null);
    next=await run({kind:'wave_begin',...initial},true);
   }else if(next.pending){next=await run({kind:'recover'},true);}
   while(next.wave_transfer&&next.wave_transfer.written<next.wave_transfer.total&&!paused.current){next=await run({kind:'wave_step'},true);}
   if(paused.current){setMessage('已暂停。硬件保持停音，点击继续即可接着传。');return;}
   if(next.wave_transfer)next=await run({kind:'wave_finish'},true);
   const pending=intentRef.current;
   if(pending&&pending.port===next.port&&pending.wave===next.wave_name){
    await run({kind:'assign_key',key:pending.key,scope:pending.scope,patch:pending.patch,program:null,operators:null});
    remember(null);applied.current(pending.key,pending.title);
   }
   setMessage('波表已完整确认，演奏已恢复。');
  }catch(e){setMessage(`上传已暂停：${String(e).replace(/^Error: /,'')}。已确认进度会保留，排除问题后点击继续。`);}
  finally{active.current=false;setRunning(false);}
 };
 return {running,message,intent,start:(data:{name:string;samples:number[];morph:number},target?:Omit<Intent,'port'|'wave'>)=>drive(data,target),resume:()=>drive(),pause:()=>{paused.current=true;setMessage('正在完成本批确认，随后暂停…');}};
}

export type WaveController=ReturnType<typeof useWaveTransfer>;
