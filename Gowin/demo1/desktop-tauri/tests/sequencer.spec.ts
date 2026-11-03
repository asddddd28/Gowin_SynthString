import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';

test('sequencer transport reflects FPGA state, validates BPM and confirms clearing',async({page})=>{
 const catalog=JSON.parse(await readFile('../../demo_test/desktop-tauri/src-tauri/assets/fm1-library.json','utf8'));
 const s={available:true,recording:false,playing:false,finalizing:false,full:false,fault:false,locked_slots:0,buttons:0,bpm:120,events:0,capacity:1024,ppq:960,loop_ticks:0,position:0,button_layout:3,waiting_first_note:false};
 const view:any={connected:true,port:'TEST',abi:65543,pending:false,fx_available:false,slots:catalog.presets.slice(0,4).map((p:any)=>({...p,revision:1,native:null})),keys:Array.from({length:32},(_,i)=>({slot:0,note:48+i,velocity:100})),monitor:{available:true,samples:[],generation:0,capture_progress:512},volume:.35,sustain:false,held:['physical-held'],packets:0,retries:0,error:'',age_ms:0,telemetry:{flags:17,pressed:1,frames:1,active:1,cycles:300,underruns:0,bad_packets:0,overruns:0,pcm_dropped:0},sequencer:s};
 const actions:any[]=[];let fail=false;
 await page.exposeFunction('__STUDIO_TEST__',()=>[]);
 await page.exposeFunction('__VOICE_TEST__',async(command:string,args:any={})=>{
  if(command==='voice_catalog')return catalog;if(command==='voice_snapshot')return view;if(command==='list_ports')return [{name:'TEST'}];if(command==='synth_midi_ports')return [];
  if(command!=='voice_action')throw Error(command);const a=args.action;actions.push(a);
  if(a.kind==='sequencer_control'){
   if(fail){fail=false;throw Error('音序器忙，请稍后重试');}
   if(a.action===1){s.recording=!s.recording;s.waiting_first_note=s.recording&&!s.loop_ticks;if(!s.recording){s.playing=true;s.loop_ticks=7680;s.events=8;s.locked_slots=3;}}
   if(a.action===2){Object.assign(s,{recording:false,playing:false,loop_ticks:0,events:0,locked_slots:0});}
   if(a.action===3)s.playing=!s.playing;
   if(a.action===4)s.bpm=a.bpm;
  }
  return view;
 });
 await page.goto('/');const panel=page.getByRole('region',{name:'四拍循环音序器'});
 await panel.getByRole('button',{name:/开始录制/}).click();await expect(panel).toContainText('等待首音 · 节拍已开始');
 await expect(panel).toContainText('20 ms');s.waiting_first_note=false;await expect(panel).toContainText('正在录制');
 await panel.getByRole('button',{name:/停止录制/}).click();await expect(panel).toContainText('2 小节循环');await expect(panel).toContainText('槽 1、槽 2');
 await panel.getByRole('button',{name:/追加一层/}).click();await expect(panel).toContainText('正在叠录');await expect(panel.getByRole('button',{name:/暂停/})).toBeDisabled();
 await panel.getByRole('button',{name:/停止录制/}).click();await panel.getByLabel('音序器 BPM').fill('301');await expect(panel.getByRole('button',{name:'设置速度'})).toBeDisabled();
 await panel.getByLabel('音序器 BPM').fill('95');await panel.getByRole('button',{name:'设置速度'}).click();expect(s.bpm).toBe(95);
 fail=true;await panel.getByRole('button',{name:/暂停/}).click();await expect(page.getByRole('alert').first()).toContainText('音序器忙');expect(s.playing).toBe(true);
 await panel.getByRole('button',{name:/清空 SW2/}).click();await panel.getByRole('button',{name:'取消',exact:true}).click();expect(s.events).toBe(8);
 await panel.getByRole('button',{name:/清空 SW2/}).click();await panel.getByRole('button',{name:'确认清空',exact:true}).click();await expect(panel).toContainText('等待录制');
 expect(view.held).toEqual(['physical-held']);expect(actions.some(a=>a.kind==='panic')).toBe(false);
 expect(actions.filter(a=>a.kind==='sequencer_control'&&a.action===2)).toHaveLength(1);
 // A silent complete bar still has a loop length and must remain clearable.
 Object.assign(s,{loop_ticks:3840,events:0,playing:true});
 await expect(panel).toContainText('1 小节循环');
 await expect(panel.getByRole('button',{name:/清空 SW2/})).toBeEnabled();
 await panel.screenshot({path:'../voice-system/reports/sequencer/app-panel.png'});
});
