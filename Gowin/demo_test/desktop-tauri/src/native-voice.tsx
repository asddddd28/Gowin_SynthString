export type NativeOperator={enabled:boolean;carrier:boolean;wave:string;mode:string;sources:number[];ratio:number|null;fixed_hz:number|null;gain:number;depth:number;feedback:number;morph:number;pulse_width:number;levels:number[];segment_ms:number[]};
export type NativePatch={name:string;operators:NativeOperator[]};
export const waveNames:Record<string,string>={sine:'正弦',triangle:'三角',saw:'锯齿',pulse:'脉冲',noise:'噪声',wavetable:'共享波表'};
export const modeNames:Record<string,string>={pm:'FM / PM',fm:'线性 FM',am:'AM',ring:'环形调制',wavetable:'波表合成'};
export function nativeTemplate(mode:string):NativePatch {
 const operators=Array.from({length:6},(_,i):NativeOperator=>({enabled:i<2,carrier:i===1,wave:mode==='wavetable'&&i===1?'wavetable':'sine',mode:mode==='wavetable'?'pm':mode,sources:i===1&&mode!=='wavetable'?[0]:[],ratio:i===0?2:1,fixed_hz:null,gain:1,depth:i===1?(mode==='am'||mode==='ring'?.8:mode==='wavetable'?0:.12):0,feedback:0,morph:0,pulse_width:.5,levels:[1,.65,.65,0],segment_ms:[8,160,160,250]}));
 if(mode==='wavetable')operators[0].enabled=false;
 return {name:modeNames[mode]+' 音色',operators};
}
function NumberField({label,value,min=0,max=1,step=.01,onChange,disabled=false}:{label:string;value:number;min?:number;max?:number;step?:number;onChange:(v:number)=>void;disabled?:boolean}){
 return <label>{label}<input aria-label={label} type="number" value={value} min={min} max={max} step={step} disabled={disabled} onChange={e=>{if(e.target.value!=='')onChange(Number(e.target.value));}}/></label>;
}
export function NativeEditor({patch,onChange,advanced=false}:{patch:NativePatch;onChange:(p:NativePatch)=>void;advanced?:boolean}) {
 const edit=(index:number,change:Partial<NativeOperator>)=>onChange({...patch,operators:patch.operators.map((o,i)=>i===index?{...o,...change}:o)});
 return <div className={`vs-native ${advanced?'advanced':''}`}>
  {advanced&&<p className="vs-muted">按 OP1 → OP6 计算。调制源只能选择前面的算子；勾选“输出载波”的算子混入声音。Native 四段包络时间为满量程线性斜坡时间，与 FM1 的 DX 速率不同。</p>}
  <div className="vs-native-grid">{patch.operators.map((op,i)=>!advanced&&i>1?null:<article key={i} className="vs-operator">
   <div className="vs-op-heading"><strong>OP{i+1}{!advanced?(i===0?' · 调制源':' · 载波'):''}</strong><label><input type="checkbox" checked={op.enabled} onChange={e=>edit(i,{enabled:e.target.checked})}/>启用</label></div>
   <div className="vs-native-fields">
    <label>OP{i+1} 波形<select aria-label={`OP${i+1} 波形`} value={op.wave} onChange={e=>edit(i,{wave:e.target.value})}>{Object.entries(waveNames).map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></label>
    <NumberField label={`OP${i+1} 电平`} value={op.gain} onChange={gain=>edit(i,{gain})}/>
    <label>OP{i+1} 调谐<select aria-label={`OP${i+1} 调谐`} value={op.fixed_hz===null?'ratio':'fixed'} onChange={e=>edit(i,e.target.value==='ratio'?{ratio:1,fixed_hz:null}:{ratio:null,fixed_hz:440})}><option value="ratio">跟随音高 / 比率</option><option value="fixed">固定 Hz</option></select></label>
    <NumberField label={`OP${i+1} ${op.fixed_hz===null?'频率比':'频率 Hz'}`} value={op.fixed_hz??op.ratio??1} max={op.fixed_hz===null?16:24413} step={op.fixed_hz===null?.01:1} onChange={v=>edit(i,op.fixed_hz===null?{ratio:v}:{fixed_hz:v})}/>
    {op.wave==='wavetable'&&<NumberField label={`OP${i+1} 波表位置`} value={op.morph} onChange={morph=>edit(i,{morph})}/>}
    {op.wave==='pulse'&&<NumberField label={`OP${i+1} 脉宽`} value={op.pulse_width} onChange={pulse_width=>edit(i,{pulse_width})}/>}
    {(advanced||i===1)&&<><label>OP{i+1} 调制<select aria-label={`OP${i+1} 调制`} value={op.mode} onChange={e=>edit(i,{mode:e.target.value,depth:Math.max(0,Math.min(.49,op.depth))})}>{Object.entries(modeNames).filter(([id])=>id!=='wavetable').map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></label><NumberField label={`OP${i+1} 调制深度`} value={op.depth} min={['am','ring'].includes(op.mode)?0:-.5} max={['am','ring'].includes(op.mode)?1:.499999} step={.01} onChange={depth=>edit(i,{depth})}/></>}
    {advanced&&<NumberField label={`OP${i+1} 反馈（周期）`} value={op.feedback} min={-.5} max={.499999} onChange={feedback=>edit(i,{feedback})}/>}
   </div>
   {advanced&&<div className="vs-routing"><label><input type="checkbox" checked={op.carrier} onChange={e=>edit(i,{carrier:e.target.checked})}/>输出载波</label><span>调制源：</span>{Array.from({length:i},(_,n)=><label key={n}><input aria-label={`OP${i+1} 来源 OP${n+1}`} type="checkbox" checked={op.sources.includes(n)} onChange={e=>edit(i,{sources:e.target.checked?[...op.sources,n]:op.sources.filter(s=>s!==n)})}/>OP{n+1}</label>)}{i===0&&<small>无前序源</small>}</div>}
   <div className="vs-native-eg">{op.levels.map((level,k)=><div key={k}><span>{['起音','衰减','保持目标','释放'][k]}</span><NumberField label={`OP${i+1} L${k+1}`} value={level} disabled={k===3} onChange={v=>edit(i,{levels:op.levels.map((l,n)=>n===k?v:l)})}/><NumberField label={`OP${i+1} 时间${k+1} ms`} value={op.segment_ms[k]} max={60000} step={1} onChange={v=>edit(i,{segment_ms:op.segment_ms.map((t,n)=>n===k?v:t)})}/></div>)}</div>
  </article>)}</div>
 </div>;
}
