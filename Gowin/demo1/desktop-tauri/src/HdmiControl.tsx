import type {Action,StudioView} from './useStudioEngine';
const pages=['总览','音色槽','六算子','调制','效果','系统','音序库','SD 音色库'];
export function HdmiControl({view,run,busy,onError}:{view:StudioView|null;run:(a:Action,b?:boolean)=>Promise<StudioView>;busy:boolean;onError:(e:unknown)=>void}){
 const h=view?.hdmi,ready=view?.connected&&h?.available&&!view.pending&&!view.wave_transfer&&!view.keyboard?.calibration;
 return <section className="panel hdmi-control"><div className="section-heading"><h3>HDMI 显示与实体控制</h3><span className="badge">{h?.available?'1280 × 720':view?.connected?'未检测到显示固件':'等待连接'}</span></div>
 <p>屏幕的琴键、波形、频谱和延迟由 FPGA 独立刷新。声音仍从底板耳机接口输出。</p>
 <div className="hdmi-pages" role="group" aria-label="HDMI 页面">{pages.map((p,i)=><button key={p} className={`button ${h?.page===i?'primary':''}`} disabled={!ready||busy||i>=(h?.page_count??6)} onClick={()=>void run({kind:'hdmi_page',page:i}).catch(onError)}>{p}</button>)}</div>
 <p className="microcopy">摇杆左右切页；E1 选择音色槽，E2 选择算子，E3 调电平，E4 调频率比，E5 调音量。当前参数编辑由 App 桥接，请保持 App 连接。各槽草稿在本次连接中分别保留，切槽不会丢失或应用草稿；按下摇杆仅应用当前槽，影响共享该槽的琴键。</p>
 <p className="microcopy">从左到右为 E5、E4、E3、E2、E1；E1 在最右侧。摇杆上下选择算子，左右每拨动一次切一页，回中不重复触发。</p>
 {(h?.page_count??6)>6&&<p className="microcopy">{view?.storage?.service?'音序库与 SD 音色库由 FPGA 独立操作：上下选择文件、按摇杆加载，E1 选择目标音色槽。SW3 保存音序，SW5 / SW6 切换已保存音序。':'当前固件未启用 SD 存储；内存录制、叠录和循环回放可正常使用。'}库页面的摇杆确认不会应用算子草稿。</p>}
 {h?.rgb_available&&<div className="device-connection" aria-label="键盘 RGB 灯效">
  <strong>键盘 RGB 灯效</strong>
  <label>模式<select aria-label="键盘灯效模式" disabled={!ready||busy} value={h.rgb_mode??1} onChange={e=>void run({kind:'hdmi_rgb',mode:Number(e.target.value),direction:!!h.rgb_direction}).catch(onError)}>
   <option value={0}>关闭</option><option value={1}>单键点亮</option><option value={2}>涟漪</option><option value={3}>扫光</option><option value={4}>十字扩散</option><option value={6}>彩虹流水</option>
  </select></label>
  {h.rgb_mode===3&&<label>方向<select aria-label="键盘扫光方向" disabled={!ready||busy} value={h.rgb_direction?'vertical':'horizontal'} onChange={e=>void run({kind:'hdmi_rgb',mode:3,direction:e.target.value==='vertical'}).catch(onError)}><option value="horizontal">从左到右</option><option value="vertical">从上到下</option></select></label>}
  <p className="microcopy">按实体琴键触发；彩虹流水持续播放。灯效由 FPGA 独立运行，退出 App 后仍有效，重新上电恢复单键点亮。校准期间暂停按键灯效。</p>
 </div>}
 {h?.available&&<div className="hdmi-current"><span>SLOT {h.slot+1} · OP {h.operator+1}</span><span>{h.dirty?'尚未应用的旋钮草稿':'参数已同步'}</span><button className="button" disabled={!ready||busy||!h.dirty} onClick={()=>void run({kind:'hdmi_apply'}).catch(onError)}>应用屏幕草稿</button><button className="button" disabled={!ready||busy||!h.dirty} onClick={()=>void run({kind:'hdmi_cancel'}).catch(onError)}>取消草稿</button></div>}
 {h?.message&&<p role="status">{h.message}</p>}
 {!!h?.draft_slots?.length&&<p className="microcopy">待应用音色槽：{h.draft_slots.map(s=>s+1).join('、')}。退出或断开前请分别应用需要保留的草稿。</p>}
 {h?.encoder_counts&&<details><summary>旋钮输入诊断</summary><p className="microcopy">FPGA 累计边沿计数；每格约 4 个边沿，转动后应变化。它用于区分输入采集与参数边界，不是旋钮绝对角度。</p><div className="hdmi-current">{[4,3,2,1,0].map(i=><span key={i}>E{i+1}：{h.encoder_counts![i]}</span>)}</div></details>}
 </section>;
}
