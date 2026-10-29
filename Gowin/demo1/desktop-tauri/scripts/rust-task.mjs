import { spawnSync } from 'node:child_process';
import { join, resolve } from 'node:path';
const env = { ...process.env, PATH: join(process.env.USERPROFILE, '.cargo/bin') + ';' + process.env.PATH };
const result = spawnSync('cargo', process.argv.slice(2), { cwd: resolve('src-tauri'), env, stdio:'inherit', windowsHide:true });
if(result.error) console.error(result.error);
process.exit(result.status ?? 1);
