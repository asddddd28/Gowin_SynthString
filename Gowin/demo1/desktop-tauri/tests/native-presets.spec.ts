import {test,expect} from '@playwright/test';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';

test('native AM/PM/drums retain complete patches and respect key scope and capacity',async({page})=>{
 const temp=await mkdtemp(join(tmpdir(),'tang-native-'));
 const child=spawn(resolve('src-tauri/target/debug/studio-test-harness.exe'),[resolve('src-tauri/assets'),join(temp,'config.json')],{windowsHide:true,stdio:['pipe','pipe','pipe']});
 const pending:{resolve:(v:any)=>void;reject:(e:Error)=>void}[]=[];
 createInterface({input:child.stdout}).on('line',line=>{const p=pending.shift();if(p){const r=JSON.parse(line);r.ok?p.resolve(r.result):p.reject(new Error(r.error));}});
 const call=(method:string,params:any={})=>new Promise<any>((resolve,reject)=>{pending.push({resolve,reject});child.stdin.write(JSON.stringify({method,params})+'\n');});
 const catalog=JSON.parse(await readFile('../../demo_test/desktop-tauri/src-tauri/assets/fm1-library.json','utf8'));
 const view:any={connected:false,port:null,abi:null,pending:false,fx_available:false,slots:catalog.presets.slice(0,4).map((p:any)=>({program:p.program,revision:1,operators:p.operators,native:null})),keys:Array.from({length:32},(_,i)=>({slot:0,note:48+i,velocity:100})),monitor:{available:true,samples:[],captured_at_ms:null,generation:0,latency_cycles:0,max_latency_cycles:0,observations:0,key:0,capture_progress:0},volume:.35,sustain:false,held:[],packets:0,retries:0,error:'',age_ms:0,wave_name:'user wave',filter:{available:true,profile:{enabled:true,cutoff_hz:2000,lfo_enabled:true,lfo_rate_hz:1,lfo_depth_oct:2,lfo_shape:0}},serial:{last_wire_ms:8,last_request_ms:11,timeout_attempts:0},telemetry:{flags:17,pressed:0,frames:1,active:0,cycles:878,underruns:0,bad_packets:0,overruns:0,pcm_dropped:0,fx_clips:0,fx_dropped:0,fx_cycles:0}};
 const actions:any[]=[];const errors:string[]=[];let capacity=false;
 page.on('pageerror',e=>errors.push(e.message));
 try{
  const bank=await call('native_preset_catalog');expect(bank).toHaveLength(20);
  for(const p of bank)expect((await call('voice_validate_patch',{patch:p.patch})).commands).toBe(14);
  await page.exposeFunction('__STUDIO_TEST__',call);
  await page.exposeFunction('__VOICE_TEST__',async(command:string,args:any={})=>{
   if(command==='voice_catalog')return catalog;if(command==='voice_snapshot')return view;if(command==='list_ports')return [{name:'TEST',recommended:true}];
   if(command==='synth_midi_ports'||command==='synth_midi_events')return [];if(command==='synth_midi_connect')return null;
   if(command!=='voice_action')throw Error(command);const a=args.action;actions.push(a);
   if(a.kind==='connect'){view.connected=true;view.port=a.port;view.abi=65542;}
   if(a.kind==='validate_key'||a.kind==='assign_key'){
    if(capacity)throw Error('当前已有 4 种不同音色在使用；不会覆盖其他键。');
    await call('voice_validate_patch',{patch:a.patch});
    if(a.kind==='assign_key'){view.slots[1]={program:null,revision:2,native:a.patch,operators:[]};view.keys[a.key]={...view.keys[a.key],slot:1};}
   }
   if(a.kind==='panic')view.held=[];
   if(a.kind==='note')view.held=a.pressed?[a.token]:[];
   return view;
  });
  await page.goto('/');await page.getByRole('button',{name:'连接板卡',exact:true}).click();
  await expect(page.getByText('连接成功，按键映射已回读')).toBeVisible();
  await page.getByRole('button',{name:'配置音键 1',exact:true}).click();
  await page.getByRole('button',{name:'选择预设音色',exact:true}).click();
  for(const [cat,count] of [['AM',6],['PM',6],['Drum',8]] as const){await page.getByRole('button',{name:cat,exact:true}).click();await expect(page.locator('.native-preset')).toHaveCount(count);}
  await expect(page.getByText('鼓音色固定音高',{exact:false})).toBeVisible();
  await page.locator('[data-native="drum-hat-closed"]').getByRole('button',{name:'适配说明'}).click();
  await expect(page.getByRole('dialog')).toContainText('未实现开/闭镲互斥组');await page.keyboard.press('Escape');
  await page.screenshot({path:'../voice-system/reports/native-presets/drum-library.png',fullPage:true});
  const before=structuredClone(view);const hat=bank.find((p:any)=>p.id==='drum-hat-closed');
  await page.locator('[data-native="drum-hat-closed"]').getByRole('button',{name:'载入此键'}).click();
  await expect(page.getByLabel('音色名称',{exact:true})).toHaveValue(hat.title);
  expect(view.slots[1].native).toEqual(hat.patch);expect(view.slots[1].native.operators.filter((o:any)=>o.enabled)).toHaveLength(6);
  await expect(page.getByLabel('合成模式',{exact:true})).toBeDisabled();
  expect(view.keys[0]).toEqual({...before.keys[0],slot:1});expect(view.keys.slice(1)).toEqual(before.keys.slice(1));
  expect(view.slots[0]).toEqual(before.slots[0]);expect(view.filter).toEqual(before.filter);expect(view.wave_name).toBe(before.wave_name);expect(view.volume).toBe(before.volume);
  await page.getByRole('button',{name:'六算子配置',exact:true}).click();await expect(page.getByLabel('OP6 频率 Hz',{exact:true})).toHaveValue('7910');await expect(page.getByLabel('OP6 来源 OP5',{exact:true})).toBeChecked();await page.keyboard.press('Escape');
  await page.getByRole('button',{name:'选择预设音色',exact:true}).click();await page.getByRole('button',{name:'AM',exact:true}).click();
  await page.locator('[data-native="am-tone-basic"]').getByRole('button',{name:'适配说明'}).click();await expect(page.getByRole('dialog')).toContainText('Tone.js');await expect(page.getByRole('dialog')).toContainText('非逐样本复刻');await page.keyboard.press('Escape');
  capacity=true;const assigns=actions.filter(a=>a.kind==='assign_key').length;
  await page.locator('[data-native="am-tone-basic"]').getByRole('button',{name:'载入此键'}).click();await expect(page.getByRole('alert')).toContainText('4 种');
  expect(actions.filter(a=>a.kind==='assign_key')).toHaveLength(assigns);expect(view.slots[1].native).toEqual(hat.patch);
  expect(actions.some(a=>a.kind.startsWith('wave_'))).toBe(false);expect(errors).toEqual([]);
 }finally{child.kill();await new Promise(r=>child.once('exit',r));await rm(temp,{recursive:true,force:true});}
});
