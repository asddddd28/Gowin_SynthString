import { cpSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
for (const [source, name] of [
  [resolve(root, '../output/basic_bank_v1'), 'basic_bank'],
  [resolve(root, '../output/sd_library_demo'), 'wavetable_library'],
  [resolve(root, '../desktop/samples'), 'samples'],
]) {
  if (!existsSync(source)) throw new Error(`Missing asset: ${source}`);
  cpSync(source, join(root, 'src-tauri/assets', name), { recursive: true });
}
console.log('Native backend resource assets prepared; no Python runtime required.');
