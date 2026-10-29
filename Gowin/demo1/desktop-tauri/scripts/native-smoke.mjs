// Real Tauri/WebView2 IPC check. Only a debug build accepts the isolated config.
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { chromium } from '@playwright/test';
import assert from 'node:assert/strict';

const folder=await mkdtemp(join(tmpdir(),'tang-native-'));
const release=process.argv.includes('--release');
const endpoint='http://127.0.0.1:9338';
try { await fetch(endpoint+'/json/version'); throw new Error('Debug port already in use'); }
catch(e) { if(e.message==='Debug port already in use') throw e; }
const child=spawn(resolve(release ? 'release-performance/TangSynthStudio/TangSynthStudio.exe' : 'src-tauri/target/debug/tang-synth-studio.exe'),[],{
  windowsHide:true,stdio:['ignore','pipe','pipe'],
  env:{...process.env,TANG_STUDIO_TEST_CONFIG:join(folder,'settings.json'),
    WEBVIEW2_USER_DATA_FOLDER:join(folder,'webview'),
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:'--remote-debugging-port=9338 --remote-debugging-address=127.0.0.1'},
});
let output='';child.stderr.on('data',d=>output+=d);child.stdout.on('data',d=>output+=d);
let browser;
try {
  for(let i=0;i<60;i++){
    if(child.exitCode!==null)throw new Error('Native app exited: '+output);
    try { if((await fetch(endpoint+'/json/version')).ok)break; }catch{}
    await new Promise(r=>setTimeout(r,500));
  }
  browser=await chromium.connectOverCDP(endpoint);
  let page;
  for(let i=0;i<40;i++){
    page=browser.contexts().flatMap(c=>c.pages()).find(p=>p.url().includes('tauri.localhost'));
    if(page)break;
    await new Promise(r=>setTimeout(r,250));
  }
  if(!page)throw new Error('No Tauri document: '+browser.contexts().flatMap(c=>c.pages()).map(p=>p.url()));
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.getByLabel('音色名称').waitFor({timeout:20000});
  const rpc=(method,params={})=>page.evaluate(({method,params})=>window.__TAURI_INTERNALS__.invoke('studio_request',{method,params}),{method,params});
  const before=await rpc('get_state');assert.equal(before.online,false);assert.equal(before.backend,'rust');
  assert.equal(before.live.enabled,false);assert.equal(before.performance.transpose,0);
  const midi=await rpc('midi_ports');assert.ok(Array.isArray(midi));
  await assert.rejects(()=>rpc('test_connect')); // Test-only adapter cannot connect the production app.
  const gain=page.getByRole('spinbutton',{name:'A 电平',exact:true});
  const oldGain=Number(await gain.inputValue());
  await page.getByRole('slider',{name:'A 电平旋钮',exact:true}).press(oldGain>50?'ArrowDown':'ArrowUp');
  assert.notEqual(Number(await gain.inputValue()),oldGain);
  await page.getByRole('button',{name:'撤销',exact:true}).click();assert.equal(Number(await gain.inputValue()),oldGain);
  await page.getByRole('button',{name:'收起控制',exact:true}).click();assert.equal(await page.getByLabel('MIDI 输入设备').isVisible(),false);
  await page.getByRole('button',{name:'展开控制',exact:true}).click();
  assert.equal((await rpc('bank_catalog')).length,16);
  await page.screenshot({path:release ? '../reports/performance-release-design.png' : '../reports/performance-native-design.png'});
  await page.getByRole('button',{name:'音色浏览器',exact:true}).click();
  await page.getByLabel('搜索音色').fill('FM 电钢琴');
  if(!release) {
    await page.getByRole('button',{name:'载入音色',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('input[aria-label="音色名称"]')?.value==='FM 电钢琴');
    const after=await rpc('get_state');assert.equal(after.config.keys[0].synth.mode,'FM / PM');
  }
  await page.getByRole('button',{name:'波表工坊',exact:true}).click();
  await page.getByRole('img',{name:'资源波形预览'}).first().waitFor();
  if(!release)await page.screenshot({path:'../reports/performance-native-wavetable.png'});
  if(release)assert.deepEqual((await rpc('get_state')).config,before.config);
  assert.equal(await page.getByRole('alert').count(),0);assert.deepEqual(errors,[]);
  // Invoke the documented native window close; Rust joins the backend and serial workers cleanly.
  await page.evaluate(()=>window.__TAURI_INTERNALS__.invoke('plugin:window|close',{label:'main'})).catch(()=>{});
  await new Promise((resolve,reject)=>{if(child.exitCode!==null)return resolve();child.once('exit',resolve);setTimeout(()=>reject(new Error('App did not close')),8000).unref();});
  assert.equal(child.exitCode,0);
  await writeFile(release ? '../reports/performance_release_smoke.json' : '../reports/performance_native_smoke.json',JSON.stringify({passed:true,time:new Date().toISOString(),release,real_webview2:true,native_rust_backend:true,hardware_connected:false,bank_count:16,preset_loaded:release?null:'FM 电钢琴',config_unchanged:release,exit_code:child.exitCode,page_errors:errors,isolated_config:release?null:join(folder,'settings.json')},null,2));
  console.log('PASS: Native WebView2 → Rust IPC → native Rust engine; clean close. Release='+release);
} finally { if(browser)await browser.close().catch(()=>{});if(child.exitCode===null)child.kill(); }
