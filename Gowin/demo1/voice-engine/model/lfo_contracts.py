"""LFO 模块接口合同；通过现有 write-spec 入口生成规范和时序图。"""
from pathlib import Path
import copy
import json
from engine_contracts import contract, BASE, ROOT

def generate():
    contract('AxisLfoStep','无状态LFO单步流水；调用者拥有相位与随机状态。',[],
             {'i_s_axis_tdata':256,'o_m_axis_tdata':160},[
        'Request words: phase, increment, RNG state, random ramp origin, waveform/polarity/restart flags, restart phase, seed, pulse width.',
        'Result words: value Q26, next phase, next RNG, next ramp origin, wrap/restart flags. Tag is opaque.',
        'Seven shapes, bipolar/unipolar, phase restart. RNG changes exactly on phase wrap or restart.',
        'Five elastic pipeline stages, II=1; downstream stall freezes every stage; reset cancels in-flight work.' ])
    module=copy.deepcopy(BASE)
    module.update(name='VoiceModulation',rtl_path='rtl/VoiceModulation.v',description='两LFO和八路稀疏调制的参数银行、状态池与帧调度。')
    ports=[('input','i_axis_aclk',1,'共用50MHz时钟'),('input','i_axis_arstn',1,'低有效复位'),
        ('input','i_start_frame',1,'开始一次全源更新'),('input','i_patch_valid',4,'有效音色槽'),
        ('input','i_patch_bank',4,'各音色活动银行'),('input','i_voice_active',8,'活动声部'),
        ('input','i_voice_patch',16,'每声部2位音色槽'),('input','i_start_voice',1,'开始某声部路由计算'),
        ('input','i_voice',3,'当前声部'),('input','i_patch',2,'当前声部音色'),
        ('input','i_note_on',1,'实际新分配声部事件，重试不能置位'),('input','i_note_voice',3,'新分配声部'),
        ('input','i_restart',1,'仅新执行的显式重触发'),('input','i_restart_context',5,'需要重触发的上下文'),
        ('input','i_begin',1,'清空草稿的启用掩码'),('input','i_config_write',1,'写草稿参数'),
        ('input','i_config_route',1,'路由参数或LFO参数'),('input','i_config_bank',1,'草稿银行'),
        ('input','i_config_patch',2,'草稿音色槽'),('input','i_config_index',3,'LFO或路由编号'),
        ('input','i_config_data',160,'LFO五字或路由两字'),('input','i_inspect',5,'调试上下文索引'),
        ('output','o_inspect',128,'当前源值/相位/资格/RNG快照'),('output','o_busy',1,'帧或路由执行中'),
        ('output','o_done',1,'单周期完成通知'),('output','o_modulation',480,'15个有符号32位调制累加结果')]
    module['interfaces']['ports']=[dict(name=n,direction=d,width=w,role='clock' if n=='i_axis_aclk' else 'reset' if n=='i_axis_arstn' else 'data' if w>1 else 'control',description=t) for d,n,w,t in ports]
    module['behavior']=[
        '24 state slots: eight patch-global and sixteen voice-local. Only enabled/eligible source contexts advance, once per frame; routes never advance source state.',
        'Parameters are double banked with the voice program. Begin disables the inactive bank LFO and route masks without disturbing the active bank.',
        'New NoteID allocation clears local LFO initialization; first eligible frame restarts phase and seed. Global phase is independent of note events.',
        'Eight routes accumulate in 36-bit guards across fifteen targets; output saturates to signed32. Base musical parameters are not modified.',
        'Route descriptor, source/depth operands, product and accumulator are registered separately. Eight descriptors issue at II=1, drain before final clamp; start-to-done is13 clocks. Disabled routes force both operands to zero; same-target writes retain source order.',
        'Start pulses and configuration writes are only accepted while idle by contract; parent prevents control writes during a render.' ]
    module['constraints']=['Verilog-2001, one clock domain. No board integration claim.','See MODULATION.md for units, commands, source scopes and reset behavior.']
    module['verification_cases']=['Independent integer model and mixed waveform PCM comparisons','Free-run versus key restart; voice steal and duplicate request','Eight routes, signed saturation and disabled sources','Worst-case sample deadline and concurrent AXI traffic']
    module['timing_diagrams'][0]['description']='先发frame启动，24上下文流水扫描完成后发done；每个声部再启动8路累加；配置仅在idle提交。'
    (ROOT/'spec/VoiceModulation_contract.json').write_text(json.dumps({'modules':[module]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__': generate()
