import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
test('keyboard wizard, transactional cancel, threshold validation and velocity settings',async({page})=>{
 const catalog=JSON.parse(await readFile('../../demo_test/desktop-tauri/src-tauri/assets/fm1-library.json','utf8'));
 const profile={keys:Array.from({length:32},()=>({rest:3000,bottom:1000,noise:2})),release:.35,press:.5,sensitivity:500,velocity_enabled:false,velocity_ceiling:127,curve_version:2};
 const keyboard:any={available:true,profile,applied:true,raw:Array(32).fill(3000),scans:1,last_key:2,velocity:78,travel_ms:40,enabled:false,calibration:null,message:''};
 const view:any={connected:true,port:'TEST',abi:65541,pending:false,fx_available:false,slots:catalog.presets.slice(0,4).map((p:any)=>({...p,program:p.program,revision:1,native:null})),keys:Array.from({length:32},(_,i)=>({slot:0,note:48+i,velocity:100})),monitor:{available:true,samples:[],generation:0,latency_cycles:0,max_latency_cycles:0,observations:0,key:0,capture_progress:0},keyboard,volume:.5,sustain:false,held:[],packets:0,retries:0,error:'',age_ms:0,telemetry:{flags:17,pressed:0,frames:1,active:0,cycles:900,underruns:0,bad_packets:0,overruns:0,pcm_dropped:0}};
 const actions:any[]=[];
 await page.exposeFunction('__STUDIO_TEST__',()=>[]);
 await page.exposeFunction('__VOICE_TEST__',(command:string,args:any={})=>{
  if(command==='voice_catalog')return catalog;if(command==='voice_snapshot')return view;if(command==='list_ports')return [{name:'TEST'}];if(command==='synth_midi_ports')return [];
  if(command!=='voice_action')throw Error(command);const a=args.action;actions.push(a);
  if(a.kind==='keyboard_step'){keyboard.scans++;if(keyboard.calibration)keyboard.calibration.samples=10;}
  if(a.kind==='keyboard_begin')keyboard.calibration={stage:'rest',key:0,samples:0,completed:0};
  if(a.kind==='keyboard_capture'){const c=keyboard.calibration;if(c.stage==='rest')c.stage='bottom';else{c.completed++;if(c.completed===32)c.stage='review';else c.key++;}c.samples=0;}
  if(a.kind==='keyboard_previous'){const c=keyboard.calibration;if(c.stage==='review'){c.stage='bottom';c.key=31;c.completed=31;}else if(c.key===0)c.stage='rest';else{c.key--;c.completed=c.key;}c.samples=0;}
  if(a.kind==='keyboard_cancel')keyboard.calibration=null;
  if(a.kind==='keyboard_apply'){Object.assign(profile,{release:a.release,press:a.press,sensitivity:a.sensitivity,velocity_ceiling:a.velocity_ceiling,velocity_enabled:a.velocity_enabled});keyboard.calibration=null;keyboard.enabled=a.velocity_enabled;}
  return view;
 });
 await page.goto('/');await page.getByRole('button',{name:'设备与输出',exact:true}).click();
 const panel=page.getByRole('region',{name:'键盘设置',exact:true});await expect(panel).toBeVisible();
 await page.getByLabel('松开阈值',{exact:true}).fill('60');await expect(page.getByRole('button',{name:'应用键盘设置',exact:true})).toBeDisabled();
 await page.getByLabel('松开阈值',{exact:true}).fill('30');await page.getByLabel('力度灵敏度',{exact:true}).fill('850');await page.getByLabel('最大力度',{exact:true}).fill('96');await page.getByLabel('按压速度控制力度').check();
 await page.getByRole('button',{name:'应用键盘设置',exact:true}).click();expect(actions.findLast(a=>a.kind==='keyboard_apply')).toMatchObject({release:.3,press:.5,sensitivity:850,velocity_ceiling:96,velocity_enabled:true});
 await page.getByRole('button',{name:'开始校准 32 键'}).click();await expect(page.getByRole('region',{name:'键盘校准向导'})).toContainText('全部松开');
 await expect(page.getByRole('button',{name:'确认全部松开位置'})).toBeEnabled();await page.getByRole('button',{name:'确认全部松开位置'}).click();
 await expect(page.getByRole('region',{name:'键盘校准向导'})).toContainText('K01');await page.getByRole('button',{name:'取消校准，保留原配置'}).click();expect(profile.release).toBe(.3);expect(actions.filter(a=>a.kind==='keyboard_apply')).toHaveLength(1);
 await page.getByRole('button',{name:'开始校准 32 键'}).click();await page.getByRole('button',{name:'确认全部松开位置'}).click();
 for(let i=1;i<=32;i++){const next=page.getByRole('button',{name:`确认 K${String(i).padStart(2,'0')}，继续`,exact:true});await expect(next).toBeEnabled();await next.click();}
 await expect(page.getByRole('button',{name:'保存完整校准'})).toBeEnabled();await page.getByRole('button',{name:'重做上一步'}).click();await expect(page.getByRole('button',{name:'确认 K32，继续',exact:true})).toBeEnabled();await page.getByRole('button',{name:'确认 K32，继续',exact:true}).click();await page.getByRole('button',{name:'保存完整校准'}).click();await expect(page.getByRole('region',{name:'键盘校准向导'})).toHaveCount(0);
 await page.getByText('32 键实时行程与校准数据',{exact:true}).click();await expect(page.locator('.keyboard-readings>div')).toHaveCount(32);
 await page.setViewportSize({width:1080,height:800});await page.screenshot({path:'../voice-system/reports/keyboard-velocity/app-settings.png',fullPage:true});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
