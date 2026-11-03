import {useState} from 'react';
import './touch.css';
import {Parameter,Toggle} from './components';
import type {StudioView,Action} from './useStudioEngine';
export type TouchProfile={mode:number;gain_percent:number;pitch_semitones:number;cutoff_octaves:number;swap_axes:boolean;flip_x:boolean;flip_y:boolean};
export type TouchView={available:boolean;profile:TouchProfile;applied:boolean;mode:number;touching:boolean;pads:number;pad:number;x:number;y:number;errors:number[];strums:number;coalesced:number;gain:number;pitch_semitones:number;cutoff_octaves:number};
const defaults:TouchProfile={mode:0,gain_percent:25,pitch_semitones:1.96875,cutoff_octaves:2,swap_axes:false,flip_x:false,flip_y:false};
const modes=['强度 / 音量','频率 / 音高','滤波 / Cutoff','吉他 / 四弦'];
export function TouchStatus({view}:{view:StudioView|null}){
 const t=view?.touch;if(!view?.connected||!t?.available)return null;
 return <section className="panel touch-status" aria-label="触摸演奏状态"><div className="section-heading"><h3>触摸演奏 · {t.mode+1} {modes[t.mode]}</h3><span className="badge">长按摇杆 0.8 秒切换</span></div><div className="touch-status-body"><div className={`touch-map ${t.touching?'active':''}`} aria-label="触摸位置"><span className="touch-corner">−</span><span className="touch-corner high">+</span>{t.mode===3&&[0,1,2,3].map(row=><div className="touch-string" key={row} style={{top:`${12.5+25*row}%`}}><span>{row+1}</span></div>)}{t.touching&&<i style={{left:`${t.x/1023*100}%`,top:`${t.y/1023*100}%`}}/>}</div><div className="touch-readout"><strong>{t.touching?`${t.pad?'右':'左'}触摸板 · ${t.x}, ${t.y}`:t.mode===3?'未触摸 · 等待拨弦':'未触摸 · 正常输出'}</strong><span>音量 ×{t.gain.toFixed(2)} · 音高 {t.pitch_semitones.toFixed(2)} 半音 · Cutoff {t.cutoff_octaves.toFixed(2)} oct</span>{t.mode===3?<span>先按住实体琴键，再上下划过横弦。每行最右侧按键发声，空行静音。拨弦 {t.strums} 次。</span>:<span>左下减小，右上增大；松手平滑恢复。灵敏度可在“设备与输出”中设置。</span>}{t.errors.some(Boolean)&&<span role="alert">触摸板通信异常：左 {t.errors[0]} / 右 {t.errors[1]}，异常板已停止调制。</span>}</div></div></section>;
}
export function TouchSettings({view,run,busy,onError}:{view:StudioView|null;run:(a:Action,b?:boolean)=>Promise<StudioView>;busy:boolean;onError:(e:unknown)=>void}){
 const t=view?.touch,profile=t?.profile??defaults;
 const [changes,setChanges]=useState<Partial<TouchProfile>>({}),[saving,setSaving]=useState(false);
 // Keep hardware mode changes when editing only a sensitivity field.
 const current={...profile,...changes},dirty=Object.keys(changes).length>0;
 const ready=!!view?.connected&&!!t?.available&&!view.pending&&!view.wave_transfer&&!view.keyboard?.calibration;
 const change=(p:Partial<TouchProfile>)=>setChanges(old=>({...old,...p}));
 const apply=async()=>{setSaving(true);try{await run({kind:'touch_apply',profile:current});setChanges({});}catch(e){onError(e);}finally{setSaving(false);}};
 return <section className="panel" aria-label="触摸板设置"><div className="section-heading"><h3>触摸板 · 演奏模式与灵敏度</h3><span className="badge">FPGA 本地实时控制</span></div>
 <p>长按摇杆 0.8 秒切换四种模式；短按仍为确认。两块触摸板均可使用，同时触摸时连续调制优先使用左板。</p>
 {!t?.available&&<p className="microcopy">{view?.connected?'当前固件不支持触摸演奏，请更新固件。':'连接板卡后配置触摸演奏。'}</p>}
 <label className="touch-mode-label">演奏模式<select aria-label="触摸演奏模式" disabled={!ready||saving} value={current.mode} onChange={e=>change({mode:Number(e.target.value)})}>{modes.map((name,index)=><option key={name} value={index}>{index+1} · {name}</option>)}</select></label>
 <div className="master-filter-parameters"><Parameter label="触摸音量范围" value={current.gain_percent} min={0} max={100} step={1} unit="%" disabled={!ready||saving} onChange={gain_percent=>change({gain_percent})}/><Parameter label="触摸音高范围" value={current.pitch_semitones} min={0} max={12} step={.1} unit="半音" disabled={!ready||saving} onChange={pitch_semitones=>change({pitch_semitones})}/><Parameter label="触摸 Cutoff 范围" value={current.cutoff_octaves} min={0} max={6} step={.1} unit="oct" disabled={!ready||saving} onChange={cutoff_octaves=>change({cutoff_octaves})}/></div>
 <p className="microcopy">范围表示从中心到角落的最大变化。音量相对当前主音量调整并限制上限；音高调节作用于跟随琴键的算子；滤波模式与原 Cutoff LFO 叠加，触摸时临时启用低通，松手恢复原设置。</p>
 <div className="master-filter-toggles"><Toggle label="交换触摸 X/Y" checked={current.swap_axes} disabled={!ready||saving} onChange={swap_axes=>change({swap_axes})}/><Toggle label="反转触摸左右" checked={current.flip_x} disabled={!ready||saving} onChange={flip_x=>change({flip_x})}/><Toggle label="反转触摸上下" checked={current.flip_y} disabled={!ready||saving} onChange={flip_y=>change({flip_y})}/></div>
 <p>吉他模式：四根横弦从上到下对应 K01–08、K09–16、K17–24、K25–32。实体琴键只选音，划过弦时发声；每行取最右侧按住的键。离开吉他模式后，已按住的键需松开再按。App 与 MIDI 仍可直接试音。</p>
 <div className="keyboard-actions"><span role="status">{saving?'正在同步触摸设置…':dirty?'有未应用的触摸设置':t?.applied?'触摸设置已确认':'本机触摸设置尚未恢复'}</span><button className="button primary" disabled={!ready||busy||saving||!dirty&&!!t?.applied} onClick={()=>void apply()}>应用触摸设置</button>{dirty&&<button className="button" disabled={saving} onClick={()=>setChanges({})}>取消修改</button>}</div>
 <TouchStatus view={view}/></section>;
}
