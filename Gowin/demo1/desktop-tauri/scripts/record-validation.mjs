import { readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, relative, join } from 'node:path';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const root=resolve('..');
const hash=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
const frozen=JSON.parse(readFileSync(join(root,'reports/wavetable_pair_source_manifest.json'),'utf8'));
for(const [path,expected] of Object.entries(frozen))assert.equal(hash(join(root,path)),expected,path);
const releases={
  'output/demo1_pair_31002.fs':'bc1c2a02565def32737dfbe5b922a03b7ac0941b003bd25e5eb034bb8771a8dd',
  'output/demo1_pair_31004.fs':'363c81d5112abecd3eafae1b05e1a2d8283fabd89b9e6c8d54bc1f87b1f9f906',
  'desktop/release_basic/TangSynth32/TangSynth32.exe':'267cc91abc9b904521837b96cd14edc0cbbeb553cb556440643c2a0a5e5a3700',
};
for(const [path,expected] of Object.entries(releases))assert.equal(hash(join(root,path)),expected,path);
const pythonLog=readFileSync(join(root,'reports/tauri_desktop_regression.log'),'utf8');
assert.match(pythonLog,/Ran 100 tests/);assert.match(pythonLog,/\bOK\s*$/);
const ui=JSON.parse(readFileSync(join(root,'reports/tauri_ui_tests.json'),'utf8'));
assert.equal(ui.stats.expected,6);assert.equal(ui.stats.unexpected,0);assert.equal(ui.stats.skipped,0);
const native=JSON.parse(readFileSync(join(root,'reports/tauri_native_smoke.json'),'utf8'));
const release=JSON.parse(readFileSync(join(root,'reports/tauri_release_smoke.json'),'utf8'));
assert.equal(native.passed,true);assert.equal(release.passed,true);assert.equal(release.config_unchanged,true);
const files={};
function collect(folder){for(const entry of readdirSync(folder,{withFileTypes:true})){
  const path=join(folder,entry.name);if(entry.isDirectory())collect(path);else files[relative(root,path).replaceAll('\\','/')]=hash(path);
}}
collect(resolve('src'));collect(resolve('release/TangSynthStudio'));
for(const path of ['src-tauri/src/main.rs','src-tauri/Cargo.toml','src-tauri/Cargo.lock','src-tauri/tauri.conf.json','src-tauri/capabilities/default.json','package.json','package-lock.json','../desktop/studio_engine.py','../desktop/studio_service.py','../desktop/test_studio_engine.py'])files[relative(root,resolve(path)).replaceAll('\\','/')]=hash(resolve(path));
const record={format:'tang-tauri-ui-v1',time:new Date().toISOString(),scope:'desktop-ui-and-headless-controller',python_tests:100,frontend_tests:6,native_webview2_and_sidecar:true,release_smoke:true,hardware_connected:false,physical_uart_sd_audio_verified:false,fpga_changes:false,frozen_source_count:Object.keys(frozen).length,frozen_releases:releases,release_executable:'desktop-tauri/release/TangSynthStudio/TangSynthStudio.exe',files};
writeFileSync(join(root,'reports/tauri_ui_validation.json'),JSON.stringify(record,null,2));
console.log(`Verified 100 Python + 6 UI tests, native/release smoke, ${Object.keys(frozen).length} frozen hardware sources and ${Object.keys(files).length} file hashes.`);
