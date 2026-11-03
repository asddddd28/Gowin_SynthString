import {useState} from 'react';
import {request} from './api';
import {nativeTemplate} from '../../../demo_test/desktop-tauri/src/native-voice';
import type {PairPreview} from './types';
import type {Action,StudioView} from './useStudioEngine';
import type {WaveController} from './useWaveTransfer';

export function VoiceWaveUpload({view,selectedKey,scope,resourceId,position,title,transfer,run,onDesign}:{view:StudioView|null;selectedKey:number;scope:string;resourceId:number;position:number;title:string;transfer:WaveController;run:(a:Action)=>Promise<StudioView>;onDesign:()=>void}){
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 const upload=async()=>{
  if(view?.wave_transfer){await transfer.resume();return;}
  setBusy(true);setError('');
  try{const pair=await request<PairPreview>('voice_wave_pair',{resource_id:resourceId,position});await transfer.start({name:`${title.slice(0,90)} [${pair.first}, ${pair.second}]`,samples:pair.frames.flat(),morph:pair.fraction/65536});}
  catch(e){setError(String(e));}finally{setBusy(false);}
 };
 const useWave=async()=>{
  setBusy(true);setError('');
  try{const patch=nativeTemplate('wavetable');patch.name=(view?.wave_name??'共享波表').slice(0,80);patch.operators[1].morph=view?.wave_morph??0;await run({kind:'assign_key',key:selectedKey,scope,patch,program:null,operators:null});onDesign();}
  catch(e){setError(String(e));}finally{setBusy(false);}
 };
 return <section className="panel voice-wave-transfer"><div className="section-heading"><h3>Voice 共享波表</h3><span className="pill">2 × 1024 点</span></div>
  <p>上传替换共享双帧，期间全引擎停音。可以自由切页，顶部始终显示进度和暂停/继续按钮；完整确认后恢复演奏。</p>
  <div className="wave-actions"><span>已装载：{view?.wave_name??'默认正弦'}</span><button className="button primary" disabled={!view?.connected||!view.abi||busy||transfer.running||(!view.wave_transfer&&!title)} onClick={()=>void upload()}>{view?.wave_transfer?'继续双帧上传':'上传当前相邻双帧'}</button><button className="button" disabled={!view?.connected||!!view.wave_transfer||view.pending||busy||transfer.running||!view.wave_name} onClick={()=>void useWave()}>用于当前键 · KEY {selectedKey+1}</button></div>
  <p role="status">{error||transfer.message}</p>
 </section>;
}
