import { readFileSync, writeFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { resolve, relative, join } from 'node:path';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const root=resolve('..');
const read=path=>JSON.parse(readFileSync(join(root,path),'utf8'));
const hash=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
const frozen=read('reports/wavetable_pair_source_manifest.json');
for(const [path,expected] of Object.entries(frozen))assert.equal(hash(join(root,path)),expected,path);
const prior=read('reports/tauri_ui_validation.json');
const oldReleases={...prior.frozen_releases,...Object.fromEntries(Object.entries(prior.files).filter(([p])=>p.startsWith('desktop-tauri/release/')))};
for(const [path,expected] of Object.entries(oldReleases))assert.equal(hash(join(root,path)),expected,path);
const log=readFileSync(join(root,'reports/rust_backend_tests.log'),'utf8');
assert.match(log,/test result: ok\. 25 passed; 0 failed/);
const ui=read('reports/rust_ui_tests.json');
assert.equal(ui.stats.expected,6);assert.equal(ui.stats.unexpected,0);assert.equal(ui.stats.skipped,0);
for(const path of ['reports/rust_native_smoke.json','reports/rust_release_smoke.json']){
  const r=read(path);assert.equal(r.passed,true);assert.equal(r.native_rust_backend,true);
  if(r.release)assert.equal(r.config_unchanged,true);
}
const config=JSON.parse(readFileSync('src-tauri/tauri.conf.json','utf8'));
assert.equal(config.bundle.externalBin,undefined);
const release=resolve('release-rust/TangSynthStudio');
assert.equal(existsSync(join(release,'tang-engine.exe')),false);
assert.deepEqual(readdirSync(release).filter(n=>n.endsWith('.exe')),['TangSynthStudio.exe']);
const files={};
function collect(folder){for(const entry of readdirSync(folder,{withFileTypes:true})){
  const path=join(folder,entry.name);if(entry.isDirectory())collect(path);else files[relative(root,path).replaceAll('\\','/')]=hash(path);
}}
for(const folder of ['src','src-tauri/src','src-tauri/tests','tests','scripts','release-rust/TangSynthStudio'])collect(resolve(folder));
for(const path of ['src-tauri/Cargo.toml','src-tauri/Cargo.lock','src-tauri/tauri.conf.json','src-tauri/capabilities/default.json','package.json','package-lock.json','playwright.config.ts','README.md','THIRD_PARTY_NOTICES.md'])files[relative(root,resolve(path)).replaceAll('\\','/')]=hash(resolve(path));
const record={format:'tang-native-rust-backend-v1',time:new Date().toISOString(),version:config.version,
  rust_tests:25,frontend_tests:6,legacy_profile_vectors:223,legacy_output_vectors:20,legacy_transfer_transcripts:8,
  native_webview2:true,release_smoke:true,python_runtime_required:false,python_build_required:false,
  physical_uart_sd_audio_verified:false,fpga_changes:false,frozen_source_count:Object.keys(frozen).length,
  preserved_old_release_files:Object.keys(oldReleases).length,
  release_executable:'desktop-tauri/release-rust/TangSynthStudio/TangSynthStudio.exe',
  release_executable_bytes:statSync(join(release,'TangSynthStudio.exe')).size,files};
writeFileSync(join(root,'reports/rust_backend_validation.json'),JSON.stringify(record,null,2));
console.log(`PASS: 25 Rust + 6 UI tests, native/release smoke; ${Object.keys(frozen).length} frozen sources and ${Object.keys(oldReleases).length} previous release files preserved.`);
