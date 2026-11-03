import {invoke} from '@tauri-apps/api/core';
declare global { interface Window { __VOICE_TEST__?: (command:string,args?:Record<string,unknown>)=>Promise<unknown> } }
let merged=false;
export function configureMergedStudio(){merged=true;}
export async function voiceCall<T>(command:string,args?:Record<string,unknown>):Promise<T> {
 if(import.meta.env.MODE==='test'&&window.__VOICE_TEST__)return window.__VOICE_TEST__(command,args) as Promise<T>;
 const native=merged?(command==='voice_action'?'studio_voice_action':command==='list_ports'?'studio_ports':command):command;
 return invoke<T>(native,args);
}
