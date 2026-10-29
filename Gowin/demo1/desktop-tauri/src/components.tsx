import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import * as Slider from '@radix-ui/react-slider';
import * as Switch from '@radix-ui/react-switch';
import * as Dialog from '@radix-ui/react-dialog';
import { X } from 'lucide-react';
import type { Profile } from './types';

export const ParameterControls = createContext<'knob' | 'slider'>('knob');
type ParameterProps = { label: string; value: number; min?: number; max?: number; step?: number; unit?: string; onChange: (v: number) => void; disabled?: boolean; defaultValue?: number; compact?: boolean; logarithmic?: boolean };
export function Parameter({ label, value, min = 0, max = 100, step = 1, unit = '', onChange, disabled = false, defaultValue, compact = false, logarithmic = unit === 'ms' }: ParameterProps) {
  const style=useContext(ParameterControls),initial=useRef(value),dial=useRef<HTMLDivElement>(null);
  const drag=useRef<{pointer:number;y:number;value:number}|null>(null),latest=useRef({value,onChange,disabled});latest.current={value,onChange,disabled};
  const [text,setText]=useState(String(Number(value.toFixed(3)))),editing=useRef(false);
  useEffect(()=>{if(!editing.current)setText(String(Number(value.toFixed(3))));},[value]);
  const clamp=(v:number)=>Math.min(max,Math.max(min,Number((Math.round(v/step)*step).toFixed(6))));
  const reset=()=>{if(!disabled)onChange(clamp(defaultValue??initial.current));};
  const normalized=(v:number)=>logarithmic?Math.log1p(Math.max(0,v-min))/Math.log1p(max-min):(v-min)/(max-min);
  const denormalized=(t:number)=>min+(logarithmic?Math.expm1(Math.min(1,Math.max(0,t))*Math.log1p(max-min)):Math.min(1,Math.max(0,t))*(max-min));
  useEffect(()=>{
    const node=dial.current;if(!node)return;
    const wheel=(e:WheelEvent)=>{if(document.activeElement!==node||latest.current.disabled)return;e.preventDefault();e.stopPropagation();latest.current.onChange(clamp(latest.current.value+(e.deltaY<0?1:-1)*step*(e.shiftKey?1:5)));};
    node.addEventListener('wheel',wheel,{passive:false});return()=>node.removeEventListener('wheel',wheel);
  },[min,max,step,style]);
  const finish=()=>{if(!editing.current)return;editing.current=false;const n=Number(text);if(text.trim()&&Number.isFinite(n)){const v=clamp(n);onChange(v);setText(String(Number(v.toFixed(3))));}else setText(String(Number(value.toFixed(3))));};
  const amount=Math.min(1,Math.max(0,normalized(value)));
  return <div className={`parameter ${style==='knob'?'rotary-parameter':''} ${compact?'compact-parameter':''}`}><div className="parameter-head"><span>{label}</span><label className="value-input"><input aria-label={label} type="number" min={min} max={max} step={step} value={text} disabled={disabled} onFocus={()=>editing.current=true} onBlur={finish} onKeyDown={e=>{if(e.key==='Enter'){finish();e.currentTarget.blur();}if(e.key==='Escape'){editing.current=false;setText(String(Number(value.toFixed(3))));e.currentTarget.blur();}}} onChange={e => {setText(e.target.value);const n=Number(e.target.value);if(e.target.value!==''&&Number.isFinite(n)&&n>=min&&n<=max)onChange(n);}}/><span>{unit}</span></label></div>
    {style==='knob'?<div className="knob-row"><div ref={dial} className="knob" role="slider" aria-label={`${label}旋钮`} aria-valuemin={min} aria-valuemax={max} aria-valuenow={Number(value.toFixed(3))} aria-valuetext={`${Number(value.toFixed(3))} ${unit}`} aria-orientation="vertical" aria-disabled={disabled} tabIndex={disabled?-1:0} title="上下拖动 · Shift 精调 · 聚焦后滚轮 · 双击复位" onDoubleClick={reset} onBlur={()=>drag.current=null} onPointerDown={e=>{if(disabled||e.button!==0)return;e.preventDefault();e.currentTarget.focus();e.currentTarget.setPointerCapture(e.pointerId);drag.current={pointer:e.pointerId,y:e.clientY,value};}} onPointerMove={e=>{const d=drag.current;if(!d||d.pointer!==e.pointerId)return;d.value=denormalized(normalized(d.value)+(d.y-e.clientY)/150/(e.shiftKey?10:1));d.y=e.clientY;onChange(clamp(d.value));}} onPointerUp={()=>drag.current=null} onPointerCancel={()=>drag.current=null} onLostPointerCapture={()=>drag.current=null} onKeyDown={e=>{if(disabled)return;const direction=['ArrowUp','ArrowRight','PageUp'].includes(e.key)?1:['ArrowDown','ArrowLeft','PageDown'].includes(e.key)?-1:0;if(direction){e.preventDefault();onChange(clamp(value+direction*step*(e.key.startsWith('Page')?10:e.shiftKey?1:5)));}else if(e.key==='Home'||e.key==='End'){e.preventDefault();onChange(e.key==='Home'?min:max);}else if(e.key==='Enter'){e.preventDefault();reset();}}}>
      <svg viewBox="0 0 64 64" aria-hidden="true"><path className="knob-track" d="M10.79 53.21 A30 30 0 1 1 53.21 53.21" pathLength="100"/><path className="knob-progress" d="M10.79 53.21 A30 30 0 1 1 53.21 53.21" pathLength="100" strokeDasharray={`${amount*100} 100`}/><circle className="knob-face" cx="32" cy="32" r="23"/><path className="knob-indicator" d="M32 14 V21" transform={`rotate(${-135+270*amount} 32 32)`}/></svg>
    </div><div className="knob-scale"><span>{min}{unit}</span><span>{max}{unit}</span></div></div>:<Slider.Root className="slider" value={[value]} min={min} max={max} step={step} disabled={disabled} onValueChange={([v]) => onChange(v)} onDoubleClick={reset}><Slider.Track className="slider-track"><Slider.Range className="slider-range"/></Slider.Track><Slider.Thumb className="slider-thumb" aria-label={`${label}滑杆`}/></Slider.Root>}
  </div>;
}

export function Toggle({ label, checked, onChange, disabled=false }: { label: string; checked: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return <label className="toggle"><Switch.Root aria-label={label} className="switch" checked={checked} disabled={disabled} onCheckedChange={onChange}><Switch.Thumb className="switch-thumb"/></Switch.Root><span>{label}</span></label>;
}

export function Modal({ open, onClose, title, description, children }: { open: boolean; onClose: () => void; title: string; description: string; children: ReactNode }) {
  return <Dialog.Root open={open} onOpenChange={v => !v && onClose()}><Dialog.Portal><Dialog.Overlay className="modal-overlay"/><Dialog.Content className="modal"><Dialog.Title>{title}</Dialog.Title><Dialog.Description>{description}</Dialog.Description>{children}<Dialog.Close className="icon-button modal-close" aria-label="关闭"><X size={18}/></Dialog.Close></Dialog.Content></Dialog.Portal></Dialog.Root>;
}

export function Waveform({ wave = '正弦', data, color = 'var(--accent)', compact = false }: { wave?: string; data?: number[] | null; color?: string; compact?: boolean }) {
  const values = data ?? Array.from({ length: 128 }, (_, i) => {
    const p = (i / 127 * 2) % 1;
    return (wave === '正弦' ? Math.sin(p * Math.PI * 2) : wave === '三角' ? 1 - 4 * Math.abs(p - .5) : wave === '方波' ? (p < .5 ? 1 : -1) : wave === '锯齿' ? p * 2 - 1 : 0) * 32767;
  });
  const points = values.map((v, i) => `${i / (values.length - 1) * 400},${60 - v / 32768 * 40}`).join(' ');
  return <svg className={`waveform ${compact ? 'compact' : ''}`} viewBox="0 0 400 120" preserveAspectRatio="none" role="img" aria-label={data ? '资源波形预览' : `${wave}波形示意`}>
    {!compact && <g className="wave-grid">{[20,40,60,80,100].map(y => <path key={y} d={`M0 ${y} H400`}/>)}{[0,50,100,150,200,250,300,350,400].map(x => <path key={x} d={`M${x} 0 V120`}/>)}</g>}
    <polyline points={points} stroke={color} fill="none" strokeWidth={compact ? 2 : 2.5} vectorEffect="non-scaling-stroke"/>
  </svg>;
}

export function Envelope({ profile, mod = false }: { profile: Profile; mod?: boolean }) {
  const a = mod ? profile.m_attack : profile.attack, d = mod ? profile.m_decay : profile.decay;
  const s = mod ? profile.m_sustain : profile.sustain, r = mod ? profile.m_release : profile.release;
  const hold = Math.max(250, (a + d + r) * .25), total = Math.max(1, a + d + r + hold);
  const ax = 14 + a / total * 572, dx = ax + d / total * 572, hx = dx + hold / total * 572, sy = 90 - s / 100 * 70;
  const line = `M14 90 L${ax} 20 L${dx} ${sy} L${hx} ${sy} L586 90`;
  return <svg className="envelope" viewBox="0 0 600 110" preserveAspectRatio="none" role="img" aria-label={mod ? '调制 ADSR 包络示意' : '音量 ADSR 包络示意'}>
    <g className="wave-grid">{[20,55,90].map(y => <path key={y} d={`M0 ${y} H600`}/>)}{[ax,dx,hx].map((x,i) => <path key={i} d={`M${x} 0 V110`}/>)}</g>
    <path d={`${line} Z`} fill={mod ? 'var(--violet-fill)' : 'var(--accent-fill)'}/><path d={line} fill="none" stroke={mod ? 'var(--violet)' : 'var(--accent)'} strokeWidth="2" vectorEffect="non-scaling-stroke"/>
    {[[ax,20],[dx,sy],[hx,sy]].map(([x,y],i) => <circle key={i} cx={x} cy={y} r="3" fill={mod ? 'var(--violet)' : 'var(--accent)'}/>)}
  </svg>;
}
