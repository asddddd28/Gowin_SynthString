import { readFileSync, writeFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { resolve, relative, join } from 'node:path';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const root=resolve('..'),read=p=>JSON.parse(readFileSync(join(root,p),'utf8'));
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const frozen=read('reports/wavetable_pair_source_manifest.json');
for(const [p,h] of Object.entries(frozen))assert.equal(hash(join(root,p)),h,p);
const prior=read('reports/tauri_ui_validation.json'),rust=read('reports/rust_backend_validation.json');
const oldReleases={...prior.frozen_releases,
  ...Object.fromEntries(Object.entries(prior.files).filter(([p])=>p.startsWith('desktop-tauri/release/'))),
  ...Object.fromEntries(Object.entries(rust.files).filter(([p])=>p.startsWith('desktop-tauri/release-rust/')))};
for(const [p,h] of Object.entries(oldReleases))assert.equal(hash(join(root,p)),h,p);
const log=readFileSync(join(root,'reports/performance_backend_tests.log'),'utf8');
const count=Number(log.match(/test result: ok\. (\d+) passed; 0 failed/)?.[1]);assert.ok(count>=39);
const ui=read('reports/performance_ui_tests.json');assert.equal(ui.stats.expected,11);assert.equal(ui.stats.unexpected,0);assert.equal(ui.stats.skipped,0);
for(const p of ['reports/performance_native_smoke.json','reports/performance_release_smoke.json']){
  const r=read(p);assert.equal(r.passed,true);assert.equal(r.native_rust_backend,true);if(r.release)assert.equal(r.config_unchanged,true);
}
const config=JSON.parse(readFileSync('src-tauri/tauri.conf.json','utf8'));assert.equal(config.version,'0.4.0');assert.equal(config.bundle.externalBin,undefined);
const release=resolve('release-performance/TangSynthStudio');assert.equal(existsSync(join(release,'tang-engine.exe')),false);
assert.deepEqual(readdirSync(release).filter(n=>n.endsWith('.exe')),['TangSynthStudio.exe']);
const files={};function collect(folder){for(const entry of readdirSync(folder,{withFileTypes:true})){
  const p=join(folder,entry.name);if(entry.isDirectory())collect(p);else files[relative(root,p).replaceAll('\\','/')]=hash(p);
}}
for(const dir of ['src','src-tauri/src','src-tauri/tests','tests','scripts','release-performance/TangSynthStudio'])collect(resolve(dir));
for(const p of ['src-tauri/Cargo.toml','src-tauri/Cargo.lock','src-tauri/tauri.conf.json','src-tauri/capabilities/default.json','package.json','package-lock.json','playwright.config.ts','.gitignore','README.md','THIRD_PARTY_NOTICES.md','../README.md','../docs/task_plan.md'])files[relative(root,resolve(p)).replaceAll('\\','/')]=hash(resolve(p));
const record={format:'tang-performance-controls-v1',time:new Date().toISOString(),version:config.version,
  rust_tests:count,frontend_tests:11,native_webview2:true,release_smoke:true,python_runtime_required:false,python_build_required:false,
  midi_backend:'midir 0.11.1 / Windows native input',realtime:{master_volume:'immediate command, at most 20 Hz',profiles:'latest per key, 150 ms minimum send interval, ACK-gated next note; held voice unchanged'},
  physical_midi_uart_audio_verified:false,fpga_changes:false,frozen_source_count:Object.keys(frozen).length,preserved_old_release_files:Object.keys(oldReleases).length,
  release_executable:'desktop-tauri/release-performance/TangSynthStudio/TangSynthStudio.exe',release_executable_bytes:statSync(join(release,'TangSynthStudio.exe')).size,files};
writeFileSync(join(root,'reports/performance_validation.json'),JSON.stringify(record,null,2));
console.log(`PASS: ${count} Rust + 11 UI tests, native/release smoke; ${Object.keys(frozen).length} frozen sources and ${Object.keys(oldReleases).length} previous release files preserved.`);
