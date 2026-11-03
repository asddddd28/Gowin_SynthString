import type {TouchView} from './TouchSettings';
import type {StorageView} from './StorageStatus';
import type {SequencerView} from './SequencerPanel';
import type {FilterView} from './MasterFilter';
import type {KeyboardView} from './KeyboardSettings';
import {useCallback,useEffect,useRef,useState} from 'react';
import {voiceCall} from '../../../demo_test/desktop-tauri/src/voice-api';
import type {View,Catalog} from '../../../demo_test/desktop-tauri/src/VoiceStudio';
export type KeyMapping={slot:number;note:number;velocity:number};
export type Monitor={available:boolean;samples:number[];captured_at_ms:number|null;generation:number;latency_cycles:number;max_latency_cycles:number;observations:number;key:number;capture_progress:number};
export type Hdmi={available:boolean|null;page:number;page_count?:number;slot:number;operator:number;dirty:boolean;message:string;encoder_counts?:number[]|null;draft_slots?:number[];rgb_available?:boolean|null;rgb_mode?:number;rgb_direction?:boolean};
export type StudioView=View&{keys:KeyMapping[];monitor:Monitor;hdmi?:Hdmi;keyboard?:KeyboardView;filter?:FilterView;touch?:TouchView;sequencer?:SequencerView;storage?:StorageView};
export type Action=Record<string,unknown>&{kind:string};
export const defaultKeys=()=>Array.from({length:32},(_,i)=>({slot:0,note:48+i,velocity:100}));
export function useStudioEngine(monitorVisible:boolean,keyboardVisible=false,filterVisible=false){
 const [view,setView]=useState<StudioView|null>(null),[catalog,setCatalog]=useState<Catalog|null>(null);
 const [ports,setPorts]=useState<{name:string;description?:string;recommended?:boolean}[]>([]),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const current=useRef(view);current.current=view;
 const queue=useRef(Promise.resolve()),pending=useRef(0),foreground=useRef(0),visible=useRef(monitorVisible);visible.current=monitorVisible;
 const lastPoll=useRef(0),lastCapture=useRef(0),lastHdmi=useRef(0),lastKeyboard=useRef(0),closed=useRef(false);
 const filterPanel=useRef(filterVisible),lastFilter=useRef(0),lastTouch=useRef(0),lastSequencer=useRef(0);filterPanel.current=filterVisible;
 const lastStorage=useRef(0);
 const keyboardPanel=useRef(keyboardVisible);keyboardPanel.current=keyboardVisible;
 const run=useCallback((action:Action,background=false):Promise<StudioView>=>{
  pending.current++;if(!background){foreground.current++;setBusy(true);setError('');}
  else if(['wave_begin','wave_finish','recover'].includes(action.kind))setError('');
  const job=queue.current.then(async()=>{
   try{const next=await voiceCall<StudioView>('voice_action',{action});if(!closed.current)setView(next);return next;}
   catch(e){if(!closed.current){setError(String(e));try{setView(await voiceCall<StudioView>('voice_snapshot'));}catch{}}throw e;}
   finally{pending.current--;if(!background){foreground.current--;if(!closed.current)setBusy(foreground.current>0);}}
  });queue.current=job.then(()=>{},()=>{});return job;
 },[]);
 const refreshPorts=useCallback(async()=>{setPorts(await voiceCall('list_ports'));},[]);
 useEffect(()=>{closed.current=false;void refreshPorts().catch(e=>setError(String(e)));void voiceCall<Catalog>('voice_catalog').then(setCatalog).catch(e=>setError(String(e)));
  void voiceCall<StudioView>('voice_snapshot').then(setView).catch(e=>setError(String(e)));
  const timer=setInterval(()=>{const v=current.current;if(pending.current)return;
   if(!v?.connected){if(Date.now()-lastPoll.current>750){lastPoll.current=Date.now();void voiceCall<StudioView>('voice_snapshot').then(setView).catch(()=>{});}return;}
   if(v.pending||!v.abi)return;
   const now=Date.now();
   if(!v.keyboard?.calibration&&!v.wave_transfer&&v.storage?.available!==false&&now-lastStorage.current>(v.storage?.service?(v.storage.busy||v.storage.syncing?150:700):3000)){lastStorage.current=now;void run({kind:'storage_step'},true).catch(()=>{});return;}
   if(v.storage?.service&&(v.storage.busy||v.storage.syncing))return;
   if(v.keyboard?.available&&(keyboardPanel.current||v.keyboard.calibration)&&!v.wave_transfer&&now-lastKeyboard.current>150){lastKeyboard.current=now;void run({kind:'keyboard_step'},true).catch(()=>{});}
   else if(filterPanel.current&&v.filter?.available&&!v.keyboard?.calibration&&!v.wave_transfer&&now-lastFilter.current>450){lastFilter.current=now;void run({kind:'filter_step'},true).catch(()=>{});}
   else if(v.sequencer?.available&&!v.keyboard?.calibration&&!v.wave_transfer&&now-lastSequencer.current>500){lastSequencer.current=now;void run({kind:'sequencer_step'},true).catch(()=>{});}
   else if(v.touch?.available&&!v.keyboard?.calibration&&!v.wave_transfer&&now-lastTouch.current>350){lastTouch.current=now;void run({kind:'touch_step'},true).catch(()=>{});}
   else if(now-lastPoll.current>220){lastPoll.current=now;void run({kind:'poll'},true).catch(()=>{});}
   else if(!v.keyboard?.calibration&&v.hdmi&&v.hdmi.available!==false&&!v.wave_transfer&&now-lastHdmi.current>70){
    lastHdmi.current=now;void run({kind:'hdmi_step'},true).catch(()=>{});
   }
   else if(visible.current&&v.monitor?.available&&!v.wave_transfer&&(v.monitor.capture_progress!==512||now-lastCapture.current>250)){
    lastCapture.current=now;void run({kind:'monitor_step'},true).catch(()=>{});
   }
  },20);
  return()=>{closed.current=true;clearInterval(timer);};
 },[run,refreshPorts]);
 return{view,setView,catalog,ports,refreshPorts,run,busy,error,setError,current};
}
