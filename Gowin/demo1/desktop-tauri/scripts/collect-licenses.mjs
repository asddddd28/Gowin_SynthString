import { readdirSync, readFileSync, mkdirSync, cpSync, existsSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
const destination=resolve('licenses-native');mkdirSync(destination,{recursive:true});
const packages=[];
for(const entry of readdirSync('node_modules',{withFileTypes:true})){
  if(entry.name.startsWith('.'))continue;
  const path=join('node_modules',entry.name);
  if(entry.name.startsWith('@')) for(const sub of readdirSync(path))packages.push(join(path,sub));
  else packages.push(path);
}
const manifest=[];
for(const path of packages){
  if(!existsSync(join(path,'package.json')))continue;
  const info=JSON.parse(readFileSync(join(path,'package.json'),'utf8'));
  const names=readdirSync(path).filter(n=>/^(license|licence|copying|ofl)(\.|$)/i.test(n));
  for(const name of names){
    const target=info.name.replaceAll('/','__').replace('@','')+'__'+name;
    cpSync(join(path,name),join(destination,target),{recursive:true});
  }
  manifest.push({name:info.name,version:info.version,license:info.license,files:names});
}
writeFileSync(join(destination,'packages.json'),JSON.stringify(manifest,null,2));
const env={...process.env,PATH:join(process.env.USERPROFILE,'.cargo/bin')+';'+process.env.PATH};
const run=spawnSync('cargo',['metadata','--format-version','1','--locked','--filter-platform','x86_64-pc-windows-msvc'],{cwd:resolve('src-tauri'),env,encoding:'utf8',windowsHide:true,maxBuffer:32*1024*1024});
if(run.status!==0)throw new Error(run.stderr||String(run.error));
const metadata=JSON.parse(run.stdout),resolved=new Set(metadata.resolve.nodes.map(n=>n.id));
const crates=[];
for(const p of metadata.packages.filter(p=>resolved.has(p.id)&&p.source)){
  const folder=dirname(p.manifest_path),names=readdirSync(folder).filter(n=>/^(license|licence|copying|copyright|unlicense)([-_.]|$)/i.test(n));
  for(const name of names)cpSync(join(folder,name),join(destination,`rust__${p.name}__${p.version}__${name}`),{recursive:true});
  crates.push({name:p.name,version:p.version,license:p.license,source:p.source,files:names});
}
writeFileSync(join(destination,'rust-crates.json'),JSON.stringify(crates,null,2));
console.log(`Collected ${manifest.length} JS package notices and ${crates.length} Rust crate notices.`);
