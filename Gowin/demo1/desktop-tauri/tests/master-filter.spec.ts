import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';

test('global filter live edits coalesce, preserve newer drafts and never stop voices',async({page})=>{
 const catalog=JSON.parse(await readFile('../../demo_test/desktop-tauri/src-tauri/assets/fm1-library.json','utf8'));
 const profile={enabled:false,cutoff_hz:2000,lfo_enabled:false,lfo_rate_hz:1,lfo_depth_oct:2,lfo_shape:0};
 const view:any={connected:true,port:'TEST',abi:65542,pending:false,fx_available:false,slots:catalog.presets.slice(0,4).map((p:any)=>({...p,revision:1,native:null})),keys:Array.from({length:32},(_,i)=>({slot:0,note:48+i,velocity:100})),monitor:{available:true,samples:[],generation:0,capture_progress:512},volume:.35,sustain:false,held:['physical-held'],packets:0,retries:0,error:'',age_ms:0,telemetry:{flags:17,pressed:1,frames:1,active:1,cycles:300,underruns:0,bad_packets:0,overruns:0,pcm_dropped:0},filter:{available:true,profile,applied:true,revision:1,actual_cutoff_hz:2000,enabled:false,lfo_active:false}};
 const actions:any[]=[];let fail=false;const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
 await page.exposeFunction('__STUDIO_TEST__',()=>[]);
 await page.exposeFunction('__VOICE_TEST__',async(command:string,args:any={})=>{
  if(command==='voice_catalog')return catalog;if(command==='voice_snapshot')return view;if(command==='list_ports')return [{name:'TEST'}];if(command==='synth_midi_ports')return [];
  if(command!=='voice_action')throw Error(command);const a=args.action;actions.push(a);
  if(a.kind==='filter_apply'){await new Promise(r=>setTimeout(r,250));if(fail){fail=false;throw Error('模拟滤波配置拒绝');}view.filter.profile={...a.profile};view.filter.enabled=a.profile.enabled;view.filter.lfo_active=a.profile.lfo_enabled;view.filter.actual_cutoff_hz=a.profile.cutoff_hz;view.filter.applied=true;}
  return view;
 });
 await page.goto('/');await page.getByRole('button',{name:'设备与输出',exact:true}).click();
 const panel=page.getByRole('region',{name:'全局低通滤波器',exact:true});await expect(panel).toBeVisible();
 await panel.getByRole('switch',{name:'启用低通',exact:true}).click();
 await expect.poll(()=>view.filter.enabled).toBe(true);
 const initial=actions.filter(a=>a.kind==='filter_apply').length;
 await panel.getByLabel('Cutoff',{exact:true}).fill('900');await panel.getByLabel('Cutoff',{exact:true}).fill('1200');await panel.getByLabel('Cutoff',{exact:true}).fill('3300');
 await expect.poll(()=>actions.filter(a=>a.kind==='filter_apply').length).toBe(initial+1);
 await panel.getByLabel('Cutoff',{exact:true}).fill('4500');
 await expect.poll(()=>view.filter.profile.cutoff_hz).toBe(4500);await expect(panel.getByLabel('Cutoff',{exact:true})).toHaveValue('4500');
 await panel.getByRole('switch',{name:'LFO 调制 Cutoff',exact:true}).click();await panel.getByLabel('滤波 LFO 波形',{exact:true}).selectOption('1');await panel.getByLabel('滤波 LFO 速率',{exact:true}).fill('3.5');await panel.getByLabel('滤波 LFO 深度',{exact:true}).fill('2.5');
 await expect.poll(()=>view.filter.profile).toMatchObject({lfo_enabled:true,lfo_shape:1,lfo_rate_hz:3.5,lfo_depth_oct:2.5});
 fail=true;await panel.getByLabel('Cutoff',{exact:true}).fill('700');await expect(panel).toContainText('同步失败');
 const rejected=actions.filter(a=>a.kind==='filter_apply').length;await page.waitForTimeout(700);expect(actions.filter(a=>a.kind==='filter_apply')).toHaveLength(rejected);
 await panel.getByRole('button',{name:'恢复滤波设置'}).click();await expect.poll(()=>view.filter.profile.cutoff_hz).toBe(700);
 expect(actions.filter(a=>['panic','control','note','assign_key','load'].includes(a.kind))).toEqual([]);expect(view.held).toEqual(['physical-held']);expect(errors).toEqual([]);
 await panel.screenshot({path:'../voice-system/reports/master-lowpass/app-filter.png'});
});
