import library from './data/foundation-library.json';

export type Env={attack:number;decay:number;sustain:number;release:number};
export type Patch={name:string;note:number;velocity:number;mode:string;wave_a:number;wave_b:number;ratio:number;depth:number;gain_a:number;gain_b:number;amp:Env;modulation:Env;cutoff:number;resonance:number;filter:number;morph:number};
export type FoundationPreset={id:string;category:string;name:string;description:string;fixedNote:boolean;patch:Patch};
export const foundationPresets:FoundationPreset[]=library.presets;
export const foundationCategories=library.categories;
export function foundationBank():Patch[]{
 return library.demo.map(({id,note})=>{
  const preset=foundationPresets.find(p=>p.id===id);
  if(!preset)throw new Error(`缺少示范音色 ${id}`);
  return {...structuredClone(preset.patch),note};
 });
}
export const foundationKeyGroups=library.demo.map(({id})=>foundationPresets.find(p=>p.id===id)!.category);
export function foundationMatches(patch:Patch,preset:FoundationPreset):boolean{
 // A key's pitch/velocity may differ while its timbre remains the preset.
 return JSON.stringify({...patch,note:0,velocity:0})===JSON.stringify({...preset.patch,note:0,velocity:0});
}
