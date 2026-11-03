import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';

test('touch settings preserve hardware mode changes and show live performance without note commands',async({page})=>{
 const catalog=JSON.parse(await readFile('../../demo_test/desktop-tauri/src-tauri/assets/fm1-library.json','utf8'));
 const profile={mode:0,gain_percent:25,pitch_semitones:1.96875,cutoff_octaves:2,swap_axes:false,flip_x:false,flip_y:false};
 const view:any={connected:true,port:'TEST',abi:65543,pending:false,fx_available:false,slots:catalog.presets.slice(0,4).map((p:any)=>({...p,revision:1,native:null})),keys:Array.from({length:32},(_,i)=>({slot:0,note:48+i,velocity:100})),monitor:{available:true,samples:[],generation:0,capture_progress:512},volume:.35,sustain:false,held:['physical-held'],packets:0,retries:0,error:'',age_ms:0,telemetry:{flags:17,pressed:1,frames:1,active:1,cycles:300,underruns:0,bad_packets:0,overruns:0,pcm_dropped:0},touch:{available:true,profile,applied:true,mode:0,touching:false,pads:0,pad:0,x:512,y:512,errors:[0,0],strums:0,coalesced:0,gain:1,pitch_semitones:0,cutoff_octaves:0}};
 const actions:any[]=[];let fail=false;const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
 await page.exposeFunction('__STUDIO_TEST__',()=>[]);
 await page.exposeFunction('__VOICE_TEST__',async(command:string,args:any={})=>{
  if(command==='voice_catalog')return catalog;if(command==='voice_snapshot')return view;if(command==='list_ports')return [{name:'TEST'}];if(command==='synth_midi_ports')return [];
  if(command!=='voice_action')throw Error(command);const a=args.action;actions.push(a);
  if(a.kind==='touch_apply'){if(fail){fail=false;throw Error('模拟触摸配置拒绝');}view.touch.profile={...a.profile};view.touch.mode=a.profile.mode;view.touch.applied=true;}
  return view;
 });
 await page.goto('/');await expect(page.getByRole('region',{name:'触摸演奏状态'})).toContainText('强度 / 音量');
 await page.getByRole('button',{name:'设备与输出',exact:true}).click();
 const panel=page.getByRole('region',{name:'触摸板设置',exact:true});await expect(panel).toBeVisible();
 await panel.getByLabel('触摸音高范围',{exact:true}).fill('7.5');
 // A real joystick long press arrives while an unrelated sensitivity is edited.
 view.touch.mode=3;view.touch.profile.mode=3;
 await expect(panel.getByLabel('触摸演奏模式')).toHaveValue('3');
 await panel.getByRole('button',{name:'应用触摸设置'}).click();await expect.poll(()=>view.touch.profile.pitch_semitones).toBe(7.5);expect(view.touch.profile.mode).toBe(3);
 await panel.getByLabel('触摸音量范围',{exact:true}).fill('70');await panel.getByLabel('触摸 Cutoff 范围',{exact:true}).fill('3');await panel.getByRole('switch',{name:'反转触摸左右'}).click();
 fail=true;await panel.getByRole('button',{name:'应用触摸设置'}).click();await expect(page.getByRole('alert').first()).toContainText('模拟触摸配置拒绝');
 expect(view.touch.profile.gain_percent).toBe(25);await expect(panel.getByLabel('触摸音量范围',{exact:true})).toHaveValue('70');
 await panel.getByRole('button',{name:'应用触摸设置'}).click();await expect.poll(()=>view.touch.profile).toMatchObject({mode:3,gain_percent:70,pitch_semitones:7.5,cutoff_octaves:3,flip_x:true});
 view.touch.touching=true;view.touch.pads=1;view.touch.x=700;view.touch.y=800;view.touch.strums=7;
 await expect(panel).toContainText('700, 800');await expect(panel).toContainText('每行取最右侧');
 await panel.screenshot({path:'../voice-system/reports/touch-performance/app-touch-settings.png'});
 expect(actions.filter(a=>['panic','control','note','assign_key','load','filter_apply'].includes(a.kind))).toEqual([]);expect(view.held).toEqual(['physical-held']);expect(errors).toEqual([]);
});
