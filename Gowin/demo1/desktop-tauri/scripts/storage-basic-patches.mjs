// Reuse the actual UI conversion, without loading the App or opening a port.
import ts from 'typescript';
import {readFile, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import path from 'node:path';
const [input, output] = process.argv.slice(2);
if (!input || !output) throw new Error('Expected input catalogue and output file');
const bundle = path.resolve(output + '.converter.cjs');
const native = path.resolve(output + '.native.cjs').replaceAll('\\','/');
const options={compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.React}};
await writeFile(native,ts.transpileModule(await readFile('../../demo_test/desktop-tauri/src/native-voice.tsx','utf8'),options).outputText);
const source=(await readFile('src/patches.ts','utf8')).replace("'../../../demo_test/desktop-tauri/src/native-voice'",JSON.stringify(native));
await writeFile(bundle,ts.transpileModule(source,options).outputText);
const {basicPatch} = createRequire(import.meta.url)(bundle);
const bank=JSON.parse(await readFile(input,'utf8'));
const included=[],excluded=[];
for (const row of bank) {
  if (row.resource_id != null || row.profile.mode==='采样钢琴' || [row.profile.wave_a,row.profile.wave_b].includes('自定义波表')) {
    excluded.push({id:row.id,name:row.title,reason:'wavetable or PCM sample'});continue;
  }
  const patch=basicPatch(row);
  if (patch.operators.some(o=>o.wave==='wavetable')) throw new Error('Wave-dependent conversion');
  included.push({id:`basic-${row.id}`,title:row.title,category:row.category,patch});
}
await writeFile(output,JSON.stringify({included,excluded},null,2));
