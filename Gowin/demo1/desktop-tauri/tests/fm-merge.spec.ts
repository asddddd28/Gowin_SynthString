import {test,expect} from '@playwright/test';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve,sep} from 'node:path';

test('merged library keeps 128 FM entries, gates unsupported patches, routes slots and releases hidden-page notes',async({page})=>{
 const temp=await mkdtemp(join(tmpdir(),'tang-fm-merge-'));
 const child=spawn(resolve('src-tauri/target/debug/studio-test-harness.exe'),[resolve('src-tauri/assets'),join(temp,'config.json')],{windowsHide:true,stdio:['pipe','pipe','pipe']});
 const pending:{resolve:(v:unknown)=>void;reject:(e:Error)=>void}[]=[];
 createInterface({input:child.stdout}).on('line',line=>{const p=pending.shift();if(!p)return;const x=JSON.parse(line);x.ok?p.resolve(x.result):p.reject(new Error(x.error));});
 const call=(method:string,params:unknown={})=>new Promise((resolve,reject)=>{pending.push({resolve,reject});child.stdin.write(JSON.stringify({method,params})+'\n');});
 const catalog=JSON.parse(await readFile('../../demo_test/desktop-tauri/src-tauri/assets/fm1-library.json','utf8'));
 const view:any={connected:false,port:null,abi:null,pending:false,fx_available:false,slots:catalog.presets.slice(0,4).map((p:any)=>({program:p.program,revision:1,operators:p.operators})),volume:.5,sustain:false,held:[],packets:0,retries:0,error:'',age_ms:0,telemetry:{flags:17,pressed:0,frames:1,active:0,cycles:53,underruns:0,bad_packets:0,overruns:0,pcm_dropped:0,fx_clips:0,fx_dropped:0,fx_cycles:0}};
 const actions:any[]=[];
 let blockPoll=false;let releasePoll:(()=>void)|undefined;
 try{
  await page.exposeFunction('__STUDIO_TEST__',call);
  await page.exposeFunction('__VOICE_TEST__',async(command:string,args:any={})=>{
   if(command==='voice_catalog')return catalog;
   if(command==='voice_snapshot')return view;
   if(command==='list_ports')return [{name:'TEST-FM'}];
   if(command==='synth_midi_ports'||command==='synth_midi_events')return [];
   if(command==='synth_midi_connect')return null;
   if(command!=='voice_action')throw Error(command);
   const a=args.action;actions.push(a);
   if(a.kind==='poll'&&blockPoll)await new Promise<void>(resolve=>{releasePoll=resolve;});
   if(a.kind==='connect'){view.connected=true;view.port=a.port;view.abi=65541;}
   if(a.kind==='load'){const p=catalog.presets.find((p:any)=>p.program===a.program);if(!p)throw Error('unqualified');view.slots[a.slot]={program:p.program,revision:2,operators:p.operators};}
   if(a.kind==='load_native'){view.slots[a.slot]={program:null,revision:view.slots[a.slot].revision+1,operators:[],native:a.patch};}
   if(a.kind==='wave_begin'){view.wave_transfer={name:a.name,written:0,total:a.samples.length};}
   if(a.kind==='wave_step'){view.wave_transfer.written=Math.min(view.wave_transfer.total,view.wave_transfer.written+16);}
   if(a.kind==='wave_finish'){view.wave_name=view.wave_transfer.name;view.wave_transfer=null;}
   if(a.kind==='note'){view.held=a.pressed?[...view.held,a.token]:view.held.filter((t:string)=>t!==a.token);}
   if(a.kind==='control'){view.volume=a.volume;view.sustain=a.sustain;}
   if(a.kind==='panic')view.held=[];
   return view;
  });
  await page.goto('/');
  await expect(page.getByRole('heading',{name:'声音设计',exact:true})).toBeVisible();
  await page.getByRole('button',{name:'音色浏览器',exact:true}).click();
  await page.getByRole('button',{name:'FM1 Convert',exact:true}).click();
  await expect(page.locator('.fm-preset')).toHaveCount(128);
  await expect(page.locator('.preset-card:not(.fm-preset)')).toHaveCount(0);
  await expect(page.locator('.fm-preset[data-program="32"]').getByRole('button',{name:'装入槽 1'})).toBeDisabled();
  await page.getByRole('button',{name:'声音设计',exact:true}).click();await page.getByRole('button',{name:'Voice 硬件',exact:true}).click();
  await page.locator('.vs-connection').getByRole('combobox').selectOption('TEST-FM');
  await page.getByLabel('板卡刚烧录 / 复位，建立新会话').check();
  await page.getByRole('button',{name:'连接板卡',exact:true}).click();
  await expect(page.getByText('Voice 在线 · TEST-FM')).toBeVisible();
  await expect(page.getByLabel('板卡刚烧录 / 复位，建立新会话')).not.toBeChecked();
  // A slow background read must neither flash "syncing" nor disable controls.
  blockPoll=true;await expect.poll(()=>!!releasePoll).toBe(true);
  await expect(page.locator('.vs-message')).toContainText('0 次重试（本次连接）');
  await expect(page.locator('.vs-message')).not.toContainText('正在同步');
  await expect(page.getByRole('button',{name:'停止并断开',exact:true})).toBeEnabled();
  blockPoll=false;releasePoll?.();
  await page.getByRole('button',{name:'音色浏览器',exact:true}).click();
  await page.getByLabel('FM 目标槽').selectOption('2');
  const piano=page.locator('.fm-preset[data-program="0"]');
  await expect(piano.getByRole('button',{name:'待适配',exact:true})).toBeDisabled();
  await piano.getByRole('button',{name:'兼容详情'}).click();
  await expect(page.getByRole('dialog')).toContainText('自由运行相位');
  await page.keyboard.press('Escape');
  await page.screenshot({path:'../voice-system/reports/voice-app-integration/fm-library.png'});
  await page.locator('.fm-preset[data-program="32"]').getByRole('button',{name:'装入槽 3'}).click();
  await expect(page.getByRole('heading',{name:'声音设计',exact:true})).toBeVisible();
  await expect(page.locator('.vs-slot.selected')).toContainText('GUITAR 1');
  expect(actions.some(a=>a.kind==='load'&&a.program===32&&a.slot===2)).toBe(true);
  await page.getByRole('heading',{name:'声音设计',exact:true}).click();
  await page.keyboard.down('a');await expect.poll(()=>view.held).toContain('pc:KeyA');
  await page.getByRole('button',{name:'波表工坊',exact:true}).click();await expect.poll(()=>view.held).toEqual([]);await page.keyboard.up('a');
  await expect(page.getByRole('img',{name:'资源波形预览'})).toHaveCount(3);
  await page.getByRole('button',{name:'声音设计',exact:true}).click();await page.getByRole('button',{name:'Voice 硬件',exact:true}).click();
  await expect(page.getByRole('navigation').getByRole('button',{name:'FM 六算子',exact:true})).toHaveCount(0);
  await page.getByRole('button',{name:'六算子配置',exact:true}).click();
  await expect(page.getByRole('dialog',{name:'六算子配置',exact:true})).toBeVisible();
  await expect(page.getByLabel('OP6 R1',{exact:true})).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog',{name:'六算子配置',exact:true})).toBeHidden();
  await page.getByLabel('Voice 合成方式').selectOption('am');
  await page.locator('.vs-config').getByLabel('OP2 调制深度',{exact:true}).fill('0.6');
  await page.getByRole('button',{name:'提交音色至 FPGA',exact:true}).click();
  await expect.poll(()=>view.slots[2].native?.operators[1].depth).toBe(.6);
  await page.getByRole('button',{name:'六算子配置',exact:true}).click();
  await expect(page.getByRole('dialog')).toContainText('OP6');
  await page.getByRole('dialog').getByLabel('OP2 来源 OP1').uncheck();
  await page.getByRole('button',{name:'关闭六算子配置'}).click();
  await page.getByRole('button',{name:'提交音色至 FPGA',exact:true}).click();
  await expect.poll(()=>view.slots[2].native?.operators[1].sources).toEqual([]);
  await page.getByRole('button',{name:'波表工坊',exact:true}).click();
  await page.getByRole('button',{name:'上传当前相邻双帧',exact:true}).click();
  await expect.poll(()=>view.wave_name,{timeout:15000}).toBeTruthy();
  const upload=actions.find(a=>a.kind==='wave_begin');expect(upload.samples).toHaveLength(2048);
  await page.getByRole('button',{name:'使用已上传波表 · 槽 3',exact:true}).click();
  await expect.poll(()=>view.slots[2].native?.operators[1].wave).toBe('wavetable');
  for(const size of [{width:1080,height:720},{width:1440,height:940}]){
   await page.setViewportSize(size);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
   await expect(page.getByRole('button',{name:'Delay + Reverb'})).toBeDisabled();
   await page.screenshot({path:`../voice-system/reports/voice-app-integration/fm-editor-${size.width}.png`});
  }
 }finally{
  child.stdin.end();await new Promise<void>(done=>{child.once('exit',()=>done());setTimeout(()=>{child.kill();done();},3000).unref();});
  if(!resolve(temp).startsWith(resolve(tmpdir())+sep+'tang-fm-merge-'))throw Error('Unsafe test cleanup');
  await rm(temp,{recursive:true,force:true});
 }
});
