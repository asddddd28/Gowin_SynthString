import type {Profile,Timbre} from './types';
import {nativeTemplate,type NativePatch,type NativeOperator} from '../../../demo_test/desktop-tauri/src/native-voice';
export type DxOperator={output:number;rates:number[];levels:number[];ratio:number|null;fixed_hz:number|null};
export type Draft={patch:NativePatch|null;program:number|null;operators:DxOperator[];note:number;velocity:number;dirty:boolean;revision:number};
const waves:Record<string,string>={'正弦':'sine','三角':'triangle','锯齿':'saw','方波':'pulse','自定义波表':'wavetable'};
export function basicPatch(t:Timbre):NativePatch{
 const p=t.profile,mode=p.mode==='AM'?'am':p.mode==='环形调制'?'ring':'pm';
 if(p.mode==='采样钢琴')throw Error('当前 Voice 固件不支持 PCM 采样播放器，请选择 FM 电钢琴或谐波波表音色。');
 const patch=nativeTemplate(mode);patch.name=t.title;
 const eg=(prefix:''|'m_')=>({levels:[1,Number(p[`${prefix}sustain`])/100,Number(p[`${prefix}sustain`])/100,0],segment_ms:[Number(p[`${prefix}attack`]),Number(p[`${prefix}decay`]),0,Number(p[`${prefix}release`])]});
 Object.assign(patch.operators[0],eg('m_'),{wave:waves[p.wave_b],ratio:p.mod_hz?null:p.ratio,fixed_hz:p.mod_hz||null,gain:1});
 Object.assign(patch.operators[1],eg(''),{wave:waves[p.wave_a],gain:p.gain_a/100,morph:(p.frame_position??0)/100,depth:mode==='pm'?Math.min(.499999,p.depth*.25):p.depth});
 if(p.mode==='波表混合'){
  Object.assign(patch.operators[0],eg(''),{carrier:true,enabled:p.gain_b>0,gain:p.gain_b/100,ratio:p.ratio,fixed_hz:null});
  Object.assign(patch.operators[1],{sources:[],depth:0});
 }
 return patch;
}
export function envelopeProfile(op:NativeOperator):Profile{return {mode:'',wave_a:'',wave_b:'',ratio:1,depth:0,mod_hz:0,sensitivity:0,gain_a:100,gain_b:0,attack:op.segment_ms[0],decay:op.segment_ms[1],sustain:op.levels[1]*100,release:op.segment_ms[3],m_attack:0,m_decay:0,m_sustain:0,m_release:0};}
export function modeOf(p:NativePatch){return p.operators[0].carrier&&p.operators[1].sources.length===0?'mix':p.operators[1].mode;}
