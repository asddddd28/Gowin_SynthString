import { test as base, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join, sep } from 'node:path';

type Backend = { call: (method: string, params?: object) => Promise<any>; config: string };
const test = base.extend<{ backend: Backend }>({
  backend: async ({}, use) => {
    const temp = await mkdtemp(join(tmpdir(), 'tang-studio-test-'));
    const config = join(temp,'settings.json');
    const child = spawn(resolve('src-tauri/target/debug/studio-test-harness.exe'), [resolve('src-tauri/assets'),config], { windowsHide:true, stdio:['pipe','pipe','pipe'] });
    const pending: { resolve: (v:any)=>void; reject:(e:Error)=>void }[]=[];
    createInterface({input:child.stdout}).on('line',line=>{ const wait=pending.shift();if(!wait)return;const result=JSON.parse(line);result.ok?wait.resolve(result.result):wait.reject(new Error(result.error)); });
    child.stderr.on('data',data=>process.stderr.write(data));
    child.on('exit',()=>{ for(const p of pending.splice(0))p.reject(new Error('Test engine stopped')); });
    const call=(method:string,params:object={})=>new Promise((resolve,reject)=>{pending.push({resolve,reject});child.stdin.write(JSON.stringify({method,params})+'\n');});
    await use({call,config});
    child.stdin.end(); await new Promise<void>(resolve=>{child.once('exit',()=>resolve());setTimeout(()=>{child.kill();resolve();},3000).unref();});
    if(!resolve(temp).startsWith(resolve(tmpdir())+sep+'tang-studio-test-'))throw new Error('Unexpected test cleanup path');
    await rm(temp,{recursive:true,force:true});
  },
  page: async ({page,backend},use)=>{
    await page.exposeFunction('__STUDIO_TEST__',backend.call);
    await page.goto('/');await expect(page.getByRole('heading',{name:'声音设计',exact:true})).toBeVisible();
    await expect(page.getByLabel('音色名称')).toHaveValue('KEY 01');
    await use(page);
  },
});

test('real service startup, responsive layout and wave workspace',async({page})=>{
  await expect(page.getByRole('alert')).toHaveCount(0);
  await expect(page.getByRole('button',{name:/音键 \d+ /})).toHaveCount(32);
  await page.screenshot({path:'../reports/performance-design.png'});
  for(const viewport of [{width:1080,height:720},{width:1440,height:940}]){
    await page.setViewportSize(viewport);
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
    const pad=await page.getByRole('button',{name:'音键 32 G5',exact:true}).boundingBox();
    expect(pad!.y+pad!.height).toBeLessThan(viewport.height);
    await page.screenshot({path:`../reports/performance-design-${viewport.width}.png`});
    await expect(page.getByRole('button',{name:'同步此键',exact:true})).toBeDisabled();
  }
  await page.setViewportSize({width:1080,height:720});await page.getByRole('button',{name:'收起控制',exact:true}).click();
  await expect(page.getByLabel('MIDI 输入设备')).not.toBeVisible();
  await page.screenshot({path:'../reports/performance-design-compact.png'});
  await page.getByRole('button',{name:'展开控制',exact:true}).click();await expect(page.getByLabel('MIDI 输入设备')).toBeVisible();
  await page.setViewportSize({width:1440,height:940});
  await page.getByRole('button',{name:'波表工坊',exact:true}).click();
  await expect(page.getByRole('heading',{name:'波表工坊',exact:true})).toBeVisible();
  await expect(page.getByRole('img',{name:'资源波形预览'})).toHaveCount(3);
  await page.getByRole('spinbutton',{name:'整张波表位置',exact:true}).fill('75');
  await expect(page.getByRole('button',{name:'同步相邻双帧'})).toBeDisabled();
  await page.screenshot({path:'../reports/performance-wavetable.png'});
});

test('rotary drag, shift precision, focused wheel, reset, text input and undo',async({page})=>{
  const input=page.getByRole('spinbutton',{name:'A 电平',exact:true}),knob=page.getByRole('slider',{name:'A 电平旋钮',exact:true});
  const initial=Number(await input.inputValue());await input.fill('50');await input.press('Enter');
  const b=(await knob.boundingBox())!;await page.mouse.move(b.x+b.width/2,b.y+b.height/2);await page.mouse.down();
  await page.mouse.move(b.x+b.width/2,b.y+b.height/2-15);await expect(input).toHaveValue('60');
  await page.keyboard.down('Shift');await page.mouse.move(b.x+b.width/2,b.y+b.height/2-30);await page.keyboard.up('Shift');await page.mouse.up();await expect(input).toHaveValue('61');
  await knob.press('ArrowUp');await expect(input).toHaveValue('66');await knob.press('Shift+ArrowDown');await expect(input).toHaveValue('65');
  await knob.hover();await page.mouse.wheel(0,100);await expect(input).toHaveValue('60');
  await page.getByRole('heading',{name:'声音设计',exact:true}).click();await knob.hover();await page.mouse.wheel(0,-100);await expect(input).toHaveValue('60');
  await knob.dblclick();await expect(input).toHaveValue(String(initial));
  await input.fill('');await input.press('Tab');await expect(input).toHaveValue(String(initial));
  await input.fill('999');await input.press('Enter');await expect(input).toHaveValue('100');
  await page.getByRole('button',{name:'滑杆',exact:true}).click();await expect(page.getByRole('slider',{name:'A 电平滑杆'})).toBeVisible();
  await page.getByRole('button',{name:'旋钮',exact:true}).click();await page.getByRole('button',{name:'调制设置',exact:true}).click();
  const ratio=page.getByRole('spinbutton',{name:'B:A 频率比',exact:true});const saved=await ratio.inputValue();await ratio.fill('3');await ratio.press('Enter');
  await page.getByRole('button',{name:'撤销',exact:true}).click();await expect(ratio).toHaveValue(saved);
  await page.getByRole('button',{name:'重做',exact:true}).click();await expect(ratio).toHaveValue('3');
  await page.getByRole('heading',{name:'声音设计',exact:true}).click();await page.keyboard.press('Control+z');await expect(ratio).toHaveValue(saved);
});

test('sustain, session transpose, unified velocity and locked editor performance',async({page,backend})=>{
  await backend.call('test_connect');await expect(page.getByText('设备已连接',{exact:true})).toBeVisible();
  await page.getByRole('heading',{name:'声音设计',exact:true}).click();await page.keyboard.down('Space');await page.keyboard.press('1');
  await expect.poll(async()=>(await backend.call('get_state')).held).toEqual([0]);
  await page.keyboard.up('Space');await expect.poll(async()=>(await backend.call('get_state')).held).toEqual([]);
  await page.getByRole('button',{name:'升高八度',exact:true}).click();await page.getByRole('spinbutton',{name:'统一力度',exact:true}).fill('42');
  await expect.poll(async()=>(await backend.call('get_state')).performance.velocity).toBe(42);
  await page.getByRole('button',{name:'锁定编辑键',exact:true}).click();
  await page.getByRole('button',{name:'音键 2 C♯4',exact:true}).click();await expect(page.getByLabel('音色名称')).toHaveValue('KEY 01');
  const on=(await backend.call('test_frames')).filter((f:number[])=>f[1]===1).at(-1);expect(on[3]).toBe(61);expect(on[4]).toBe(42);
  expect((await backend.call('get_state')).config.keys[1].note).toBe(49);
  await page.getByRole('button',{name:'移调归零',exact:true}).click();await page.getByRole('button',{name:'恢复各键力度',exact:true}).click();
  await expect.poll(async()=>(await backend.call('get_state')).performance.velocity).toBeNull();
});

test('two touch contacts share a pad safely and cancellation releases both',async({page,backend})=>{
  await backend.call('test_connect');await expect(page.getByText('设备已连接',{exact:true})).toBeVisible();
  await page.getByRole('button',{name:'锁定编辑键',exact:true}).click();await page.getByRole('switch',{name:'触点力度',exact:true}).click();
  const pad=(await page.getByRole('button',{name:'音键 1 C3',exact:true}).boundingBox())!;
  const cdp=await page.context().newCDPSession(page),point=(id:number,y:number)=>({id,x:Math.round(pad.x+pad.width/2),y:Math.round(pad.y+y)});
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[point(1,10),point(2,30)]});
  await expect.poll(async()=>(await backend.call('get_state')).held).toEqual([0]);
  expect((await backend.call('test_frames')).filter((f:number[])=>f[1]===1)).toHaveLength(1);
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[point(2,30)]});
  expect((await backend.call('test_frames')).filter((f:number[])=>f[1]===2)).toHaveLength(0);
  await cdp.send('Input.dispatchTouchEvent',{type:'touchCancel',touchPoints:[]});
  await expect.poll(async()=>(await backend.call('get_state')).held).toEqual([]);await cdp.detach();
});

test('live controls coalesce edits, preserve held voices, save confirmed preview and fail closed',async({page,backend})=>{
  await backend.call('test_connect');await expect(page.getByText('设备已连接',{exact:true})).toBeVisible();
  const saved=(await backend.call('get_state')).config;
  await page.getByRole('button',{name:'按住演奏当前键',exact:true}).focus();await page.keyboard.down('Enter');
  await page.getByRole('switch',{name:'实时参数同步',exact:true}).click();
  const gain=page.getByRole('spinbutton',{name:'A 电平',exact:true});await gain.fill('20');
  await expect.poll(async()=>(await backend.call('get_state')).live.inflight).toBe(0);
  await gain.fill('30');await gain.fill('35');await expect.poll(async()=>(await backend.call('get_state')).live.pending).toEqual([0]);
  expect((await backend.call('get_state')).config).toEqual(saved);
  // ACK each actual upload, including an intermediate value if the 100 ms tick fell between fills.
  await expect.poll(async()=>{const s=await backend.call('get_state');if(s.live.inflight!==null)await backend.call('test_ack');return (await backend.call('get_state')).live.applied['0']?.gain_a;}).toBe(35);
  expect((await backend.call('test_frames')).filter((f:number[])=>f[1]===2)).toHaveLength(0);
  await page.getByRole('button',{name:'保存',exact:true}).click();await expect.poll(async()=>(await backend.call('get_state')).config.keys[0].synth.gain_a).toBe(35);
  expect((await backend.call('test_frames')).filter((f:number[])=>f[1]===2)).toHaveLength(0);
  // Release must follow the original owner even after focus moved into parameter fields.
  await page.keyboard.up('Enter');await expect.poll(async()=>(await backend.call('get_state')).held).toEqual([]);
  await page.getByRole('spinbutton',{name:'实时主音量',exact:true}).fill('43');
  await expect.poll(async()=>(await backend.call('test_frames')).some((f:number[])=>f[1]===3&&f[2]===0)).toBe(true);
  expect((await backend.call('get_state')).config.sound).toEqual(saved.sound);
  await gain.fill('40');await expect.poll(async()=>(await backend.call('get_state')).live.inflight).toBe(0);
  await backend.call('test_transfer_error');await expect(page.getByRole('switch',{name:'实时参数同步'})).not.toBeChecked();await expect(page.getByText('同步中断',{exact:true})).toBeVisible();
  expect((await backend.call('get_state')).synced).not.toContain(0);
});

test('MIDI event flow, pedal, channel filter and blur/page gating',async({page,backend})=>{
  await backend.call('test_connect');await expect(page.getByText('设备已连接',{exact:true})).toBeVisible();
  await backend.call('test_midi',{bytes:[0x90,48,77]});await expect.poll(async()=>(await backend.call('get_state')).held).toEqual([0]);
  await backend.call('test_midi',{bytes:[0xb0,64,127]});await backend.call('test_midi',{bytes:[0x90,48,0]});expect((await backend.call('get_state')).held).toEqual([0]);
  await backend.call('test_midi',{bytes:[0xb0,64,0]});await expect.poll(async()=>(await backend.call('get_state')).held).toEqual([]);
  await page.getByLabel('MIDI 通道',{exact:true}).selectOption('2');await expect.poll(async()=>(await backend.call('get_state')).performance.channel).toBe(2);
  await backend.call('test_midi',{bytes:[0x90,48,77]});expect((await backend.call('get_state')).held).toEqual([]);
  await backend.call('test_midi',{bytes:[0x91,48,77]});await page.evaluate(()=>window.dispatchEvent(new Event('blur')));
  await expect.poll(async()=>(await backend.call('get_state')).performance.armed).toBe(false);
  await backend.call('test_midi',{bytes:[0x91,48,88]});expect((await backend.call('get_state')).held).toEqual([]);
  await page.evaluate(()=>window.dispatchEvent(new Event('focus')));await expect.poll(async()=>(await backend.call('get_state')).performance.armed).toBe(true);
  await page.getByRole('button',{name:'音色浏览器',exact:true}).click();await expect.poll(async()=>(await backend.call('get_state')).performance.armed).toBe(false);
});

test('preset search, load, edit and persist through native Rust validation',async({page,backend})=>{
  await page.getByRole('button',{name:'音色浏览器',exact:true}).click();
  await expect(page.locator('.preset-card')).toHaveCount(16);
  await page.screenshot({path:'../reports/performance-library.png'});
  await page.getByLabel('搜索音色').fill('FM 贝斯');
  await expect(page.locator('.preset-card')).toHaveCount(1);
  await page.getByRole('button',{name:'载入音色',exact:true}).click();
  await expect(page.getByLabel('音色名称')).toHaveValue('FM 贝斯');
  await page.getByLabel('音色名称').fill('我的贝斯');
  await page.getByRole('button',{name:'调制设置',exact:true}).click();
  await page.getByRole('spinbutton',{name:'调制深度',exact:true}).fill('0.72');
  await page.getByRole('button',{name:'保存',exact:true}).click();
  await expect(page.getByText('所有修改已保存')).toBeVisible();
  const config=JSON.parse(await readFile(backend.config,'utf8'));
  expect(config.keys[0].name).toBe('我的贝斯');expect(config.keys[0].synth.depth).toBe(.72);
  expect(config.keys[1].name).toBe('KEY 02');
});

test('unsaved edits are guarded during navigation and key selection',async({page})=>{
  await page.getByLabel('音色名称').fill('未保存');
  await page.getByRole('button',{name:'音色浏览器',exact:true}).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button',{name:'返回编辑'}).click();
  await expect(page.getByLabel('音色名称')).toHaveValue('未保存');
  await page.getByRole('button',{name:'音键 2 C♯3',exact:true}).click({button:'right'});
  await page.getByRole('button',{name:'继续',exact:true}).click();
  await expect(page.getByLabel('音色名称')).toHaveValue('KEY 02');
});

test('keyboard/mouse ownership, editing focus, blur and page change',async({page,backend})=>{
  await backend.call('test_connect');
  await expect(page.getByText('设备已连接',{exact:true})).toBeVisible();
  await page.getByLabel('音色名称').fill('1234');
  expect(await backend.call('test_frames')).toEqual([]);
  await page.getByRole('heading',{name:'声音设计',exact:true}).click();
  await page.keyboard.down('1');
  const pad=page.getByRole('button',{name:'音键 1 C3',exact:true});
  await pad.hover();await page.mouse.down();await page.mouse.up();
  expect((await backend.call('test_frames')).filter((f:number[])=>f[1]===1)).toHaveLength(1);
  expect((await backend.call('test_frames')).filter((f:number[])=>f[1]===2)).toHaveLength(0);
  await page.keyboard.up('1');
  await expect.poll(async()=>(await backend.call('test_frames')).filter((f:number[])=>f[1]===2).length).toBe(1);
  await page.keyboard.down('2');await page.evaluate(()=>window.dispatchEvent(new Event('blur')));
  await expect.poll(async()=>(await backend.call('get_state')).held.length).toBe(0);
  await page.keyboard.up('2');
  await page.getByRole('button',{name:'保存',exact:true}).click();
  await page.getByRole('button',{name:'音色浏览器',exact:true}).click();
  const frames=(await backend.call('test_frames')).length;
  await page.keyboard.press('3');expect((await backend.call('test_frames')).length).toBe(frames);
});

test('duplicate keyboard mapping is rejected and original file stays intact',async({page,backend})=>{
  await page.locator('.keycap').click();await page.keyboard.press('2');
  await page.getByRole('button',{name:'保存',exact:true}).click();
  await expect(page.getByRole('alert')).toContainText('快捷键不能重复');
  expect((await backend.call('get_state')).config.keys[0].keycode).toBe(49);
});

test('output changes preserve per-key tones and destructive template has confirmation',async({page,backend})=>{
  const before=(await backend.call('get_state')).config.keys;
  await page.getByRole('button',{name:'设备与输出',exact:true}).click();
  await page.getByRole('spinbutton',{name:'总音量',exact:true}).fill('37');
  await page.getByLabel('输出增益',{exact:true}).selectOption('2');
  await page.getByRole('button',{name:'应用输出设置'}).click();
  await expect.poll(async()=>(await backend.call('get_state')).config.sound.volume).toBe(37);
  expect((await backend.call('get_state')).config.keys).toEqual(before);
  await page.getByRole('button',{name:'应用到全部音键'}).click();
  await expect(page.getByRole('dialog')).toContainText('覆盖全部音键');
  await page.getByRole('button',{name:'返回编辑'}).click();
  expect((await backend.call('get_state')).config.keys).toEqual(before);
  await page.screenshot({path:'../reports/performance-device.png'});
});
