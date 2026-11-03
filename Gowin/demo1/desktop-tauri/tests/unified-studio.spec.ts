import {test,expect} from '@playwright/test';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';

test('unified keys, real preset conversion, hardware routing, retained drafts and passive monitoring',async({page})=>{
 const temp=await mkdtemp(join(tmpdir(),'tang-unified-'));
 const child=spawn(resolve('src-tauri/target/debug/studio-test-harness.exe'),[resolve('src-tauri/assets'),join(temp,'config.json')],{windowsHide:true,stdio:['pipe','pipe','pipe']});
 const pending:{resolve:(v:any)=>void;reject:(e:Error)=>void}[]=[];
 createInterface({input:child.stdout}).on('line',line=>{const p=pending.shift();if(p){const r=JSON.parse(line);r.ok?p.resolve(r.result):p.reject(new Error(r.error));}});
 const call=(method:string,params:any={})=>new Promise<any>((resolve,reject)=>{pending.push({resolve,reject});child.stdin.write(JSON.stringify({method,params})+'\n');});
 const catalog=JSON.parse(await readFile('../../demo_test/desktop-tauri/src-tauri/assets/fm1-library.json','utf8'));
 const view:any={connected:false,port:null,abi:null,pending:false,fx_available:false,slots:catalog.presets.slice(0,4).map((p:any)=>({program:p.program,revision:1,operators:p.operators,native:null})),keys:Array.from({length:32},(_,i)=>({slot:0,note:48+i,velocity:100})),monitor:{available:true,samples:[],captured_at_ms:null,generation:0,latency_cycles:1234,max_latency_cycles:1400,observations:3,key:0,capture_progress:0},volume:.5,sustain:false,held:[],packets:0,retries:0,error:'',age_ms:0,serial:{last_wire_ms:8,last_request_ms:11,timeout_attempts:0},telemetry:{flags:17,pressed:0,frames:1,active:0,cycles:878,underruns:0,bad_packets:0,overruns:0,pcm_dropped:0,fx_clips:0,fx_dropped:0,fx_cycles:0}};
 const actions:any[]=[];let capacityError=false,interruptWave=true;let uploaded:number[]=[];
 const browserErrors:string[]=[];page.on('pageerror',e=>browserErrors.push(e.message));
 try{
  await page.exposeFunction('__STUDIO_TEST__',call);
  await page.exposeFunction('__VOICE_TEST__',async(command:string,args:any={})=>{
   if(command==='voice_catalog')return catalog;if(command==='voice_snapshot')return view;if(command==='list_ports')return [{name:'TEST-FM',recommended:true}];
   if(command==='synth_midi_ports'||command==='synth_midi_events')return [];if(command==='synth_midi_connect')return null;
   if(command!=='voice_action')throw Error(command);const a=args.action;actions.push(a);
   if(a.kind==='connect'){view.connected=true;view.port=a.port;view.abi=65541;}
   if(a.kind==='disconnect'){view.connected=false;view.abi=null;}
   if(a.kind==='monitor_step'){view.monitor.samples=Array.from({length:512},(_,i)=>Math.round(8000*Math.sin(2*Math.PI*5*i/512)));view.monitor.capture_progress=512;view.monitor.captured_at_ms=Date.now();}
   if(a.kind==='assign_key'||a.kind==='validate_key'){
    if(capacityError)throw Error('当前已有 4 种不同音色在使用；不会覆盖其他键。');
    if(a.patch)await call('voice_validate_patch',{patch:a.patch});
    if(a.kind==='assign_key'){
     const old=view.keys[a.key].slot,used=view.keys.filter((k:any)=>k.slot===old).length;let slot=used===1||a.scope!=='key'?old:[0,1,2,3].find(s=>!view.keys.some((k:any)=>k.slot===s));if(slot===undefined)throw Error('capacity');
     const p=catalog.presets.find((p:any)=>p.program===a.program);view.slots[slot]={program:a.program,revision:view.slots[slot].revision+1,native:a.patch,operators:a.operators??p?.operators??[]};
     view.keys=view.keys.map((k:any,i:number)=>a.scope==='all'||(a.scope==='sound'&&k.slot===old)||i===a.key?{...k,slot}:k);
    }
   }
   if(a.kind==='wave_begin'){uploaded=a.samples;expect(uploaded.length).toBe(2048);view.wave_transfer={name:a.name,written:0,total:2048,busy_recoveries:0};view.wave_morph=a.morph;}
   if(a.kind==='wave_step'){await new Promise(r=>setTimeout(r,18));if(interruptWave&&view.wave_transfer.written>=64){interruptWave=false;view.pending=true;throw Error('模拟连接中断，原包保留');}view.wave_transfer.written=Math.min(2048,view.wave_transfer.written+16);}
   if(a.kind==='recover'){view.pending=false;}
   if(a.kind==='wave_finish'){expect(view.wave_transfer.written).toBe(2048);view.wave_name=view.wave_transfer.name;view.wave_transfer=null;}
   if(a.kind==='configure_key')view.keys[a.key]={...view.keys[a.key],note:a.note,velocity:a.velocity};
   if(a.kind==='note')view.held=a.pressed?[...view.held,a.token]:view.held.filter((t:string)=>t!==a.token);
   if(a.kind==='control'){view.volume=a.volume;view.sustain=a.sustain;}
   if(a.kind==='panic')view.held=[];view.packets++;return view;
  });
  await page.goto('/');await expect(page.getByRole('heading',{name:'状态显示',exact:true})).toBeVisible();
  await expect(page.locator('.status-key')).toHaveCount(32);
  await expect(page.getByText('驻留音色',{exact:true})).toHaveCount(0);await expect(page.getByRole('button',{name:'旧版工程',exact:true})).toHaveCount(0);
  await page.getByRole('button',{name:'连接板卡',exact:true}).click();await expect(page.getByText('连接成功，按键映射已回读')).toBeVisible();
  await expect.poll(()=>view.monitor.samples.length).toBe(512);
  await expect(page.getByRole('img',{name:'硬件输出波形'}).locator('path[stroke="var(--accent)"]')).toHaveCount(1);
  const all=await call('bank_catalog');
  // All 16 legacy bank entries must compile through the actual Rust Native validator.
  for(const t of all){const patch=await page.evaluate(async t=>{const mod=await import('/src/patches.ts');return mod.basicPatch(t);},t);expect((await call('voice_validate_patch',{patch})).commands).toBe(14);if(t.resource_id!=null)expect((await call('voice_preset_wave',{timbre_id:t.id})).samples.length).toBe(2048);}
  const fft=await page.evaluate(async()=>{const mod=await import('/src/AudioMonitor.tsx');const bins=mod.spectrum(Array.from({length:512},(_,i)=>16384*Math.sin(2*Math.PI*5*i/512)));return {peak:bins.indexOf(Math.max(...bins)),db:Math.max(...bins)};});expect(fft.peak).toBe(5);expect(fft.db).toBeCloseTo(-6.02,1);
  const trigger=await page.evaluate(async()=>{
   const {triggerWave}=await import('/src/AudioMonitor.tsx');
   const first=triggerWave(Array.from({length:512},(_,i)=>Math.round(1000*Math.sin(2*Math.PI*(i+3)/32))));
   const second=triggerWave(Array.from({length:512},(_,i)=>Math.round(1000*Math.sin(2*Math.PI*(i+19)/32))));
   const dc=triggerWave(Array(512).fill(300));const silence=triggerWave(Array(512).fill(0));
   return {locked:first.triggered&&second.triggered,same:JSON.stringify(first.samples)===JSON.stringify(second.samples),count:first.samples.length,start:Math.abs(first.samples[0]),dc:dc.triggered,silence:silence.triggered};
  });expect(trigger).toEqual({locked:true,same:true,count:256,start:0,dc:false,silence:false});
  await expect(page.getByLabel('触发稳定',{exact:false})).toBeChecked();await page.getByLabel('触发稳定',{exact:false}).uncheck();await expect(page.getByText('512 点 · 左声道 · 16 bit',{exact:true})).toBeVisible();await page.getByLabel('触发稳定',{exact:false}).check();
  await page.screenshot({path:'../voice-system/reports/fm1-wave-repair/status-1440.png',fullPage:false});
  await page.getByRole('button',{name:'配置音键 1',exact:true}).click();await expect(page.getByRole('heading',{name:'声音设计',exact:true})).toBeVisible();
  await page.locator('.quick-presets').getByRole('button',{name:'正弦贝斯',exact:true}).click();await expect(page.getByLabel('音色名称',{exact:true})).toHaveValue('正弦贝斯');
  expect(view.keys[0].slot).toBe(1);expect(view.keys[1].slot).toBe(0);expect(actions.some(a=>a.kind==='assign_key'&&a.patch?.name==='正弦贝斯')).toBe(true);
  await page.getByLabel('音色名称',{exact:true}).fill('保留的音色草稿');
  await page.getByRole('button',{name:'状态显示',exact:true}).click();await page.getByRole('button',{name:'配置音键 2',exact:true}).click();
  await page.getByRole('button',{name:'状态显示',exact:true}).click();await page.getByRole('button',{name:'配置音键 1',exact:true}).click();
  await expect(page.getByLabel('音色名称',{exact:true})).toHaveValue('保留的音色草稿');
  await page.getByRole('button',{name:'六算子配置',exact:true}).click();await expect(page.getByRole('dialog',{name:'六算子配置'})).toBeVisible();await page.getByLabel('OP2 来源 OP1').check();await page.getByRole('button',{name:'完成编辑',exact:true}).click();
  await page.getByLabel('MIDI 音高',{exact:true}).fill('60');await page.getByRole('button',{name:'应用到硬件',exact:true}).click();await expect.poll(()=>view.keys[0].note).toBe(60);
  await page.getByRole('button',{name:'选择预设音色',exact:true}).click();await page.getByRole('button',{name:'FM1 Convert',exact:true}).click();await expect(page.locator('.fm-preset')).toHaveCount(21);await page.getByLabel('仅显示可载入的 FM1 音色',{exact:false}).uncheck();await expect(page.locator('.fm-preset')).toHaveCount(128);
  await expect(page.locator('.fm-preset[data-program="0"]').getByRole('button',{name:'待适配',exact:true})).toBeDisabled();
  await page.locator('.fm-preset[data-program="32"]').getByRole('button',{name:'载入此键',exact:true}).click();await expect(page.getByLabel('音色名称',{exact:true})).toHaveValue('GUITAR 1');
  await page.getByRole('button',{name:'六算子配置',exact:true}).click();await expect(page.getByLabel('OP6 R1',{exact:true})).toBeVisible();await page.keyboard.press('Escape');
  await page.getByRole('button',{name:'状态显示',exact:true}).click();await page.getByRole('heading',{name:'状态显示',exact:true}).click();
  await page.keyboard.down('1');await page.keyboard.down('1');await expect.poll(()=>view.held).toContain('pc:Digit1');expect(actions.filter(a=>a.kind==='note'&&a.token==='pc:Digit1'&&a.pressed).length).toBe(1);
  const event=actions.findLast(a=>a.kind==='note'&&a.pressed);expect(event.slot).toBe(1);expect(event.note).toBe(60);
  await page.getByRole('button',{name:'声音设计',exact:true}).click();await expect.poll(()=>view.held).toEqual([]);await page.keyboard.up('1');
  await page.getByLabel('合成模式',{exact:true}).selectOption('am');await page.getByLabel('B → A 调制深度',{exact:true}).fill('0.6');
  capacityError=true;await page.getByRole('button',{name:'应用到硬件',exact:true}).click();await expect(page.getByRole('alert')).toContainText('4 种');expect(view.slots[1].program).toBe(32);capacityError=false;
  await page.getByLabel('关闭错误提示').click();await page.getByRole('button',{name:'应用到硬件',exact:true}).click();await expect.poll(()=>view.slots[1].native?.operators[1].depth).toBe(.6);
  await page.screenshot({path:'../voice-system/reports/fm1-wave-repair/design-1440.png',fullPage:false});
  // A preset upload survives route changes, interruption, pause and app reload.
  const wavePreset=all.find((t:any)=>t.resource_id!=null);
  await page.getByRole('button',{name:'音色浏览器',exact:true}).click();await page.getByRole('button',{name:'全部',exact:true}).click();
  await page.locator('.preset-card').filter({has:page.getByRole('heading',{name:wavePreset.title,exact:true})}).getByRole('button',{name:'载入音色',exact:true}).click();
  await expect(page.getByRole('region',{name:'波表传输任务'})).toBeVisible();
  await page.getByRole('button',{name:'设备与输出',exact:true}).click();
  await expect.poll(()=>view.pending).toBe(true);await expect(page.getByRole('button',{name:'继续传输并完成'})).toBeEnabled();
  expect(view.wave_transfer.written).toBe(64);
  await page.getByRole('button',{name:'继续传输并完成'}).click();await expect.poll(()=>view.wave_transfer.written).toBeGreaterThan(64);
  await page.getByRole('button',{name:'暂停传输'}).click();await expect(page.getByRole('button',{name:'继续传输并完成'})).toBeVisible();
  const checkpoint=view.wave_transfer.written;expect(checkpoint).toBeLessThan(2048);
  await page.reload();await expect(page.getByRole('region',{name:'波表传输任务'})).toContainText(String(checkpoint));
  await page.getByRole('button',{name:'继续传输并完成'}).click();await expect(page.getByLabel('音色名称',{exact:true})).toHaveValue(wavePreset.title,{timeout:15000});
  expect(view.wave_transfer).toBeNull();expect(uploaded.length).toBe(2048);expect(actions.filter(a=>a.kind==='wave_begin').length).toBe(1);
  expect(actions.some(a=>a.kind==='recover')).toBe(true);expect(view.slots[1].native.name).toBe(wavePreset.title);
  await page.setViewportSize({width:1080,height:800});await page.getByRole('button',{name:'状态显示',exact:true}).click();await page.locator('.unified-main').evaluate(e=>e.scrollTop=e.scrollHeight);await expect(page.getByRole('heading',{name:'链路诊断',exact:true})).toBeInViewport();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);await page.screenshot({path:'../voice-system/reports/fm1-wave-repair/status-1080-bottom.png'});
  expect(browserErrors).toEqual([]);
 }finally{child.kill();await new Promise(r=>child.once('exit',r));await rm(temp,{recursive:true,force:true});}
});
