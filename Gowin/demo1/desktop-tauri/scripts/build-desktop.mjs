import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const env = { ...process.env, PATH: join(process.env.USERPROFILE, '.cargo/bin') + ';' + process.env.PATH };
function run(file, args) {
  const result = spawnSync(file, args, { cwd: root, env, stdio: 'inherit', windowsHide: true });
  if (result.status !== 0) process.exit(result.status || 1);
}
run(process.execPath, ['scripts/prepare-assets.mjs']);
run(process.execPath, ['scripts/collect-licenses.mjs']);
run(process.execPath, ['node_modules/@tauri-apps/cli/tauri.js', 'build', '--no-bundle']);
const out = join(root, 'release-performance/TangSynthStudio');
mkdirSync(out, { recursive: true });
cpSync(join(root, 'src-tauri/target/release/tang-synth-studio.exe'), join(out, 'TangSynthStudio.exe'));
cpSync(join(root, 'src-tauri/assets'), join(out, 'assets'), { recursive: true });
cpSync(join(root, 'licenses-native'), join(out, 'licenses'), { recursive: true });
for (const name of ['README.md', 'THIRD_PARTY_NOTICES.md']) cpSync(join(root, name), join(out, name));
console.log(`Portable desktop release: ${out}`);
