"""Explicit interfaces and behavior fixed before effects RTL implementation."""
import copy
import json
from engine_contracts import BASE, ROOT

STREAM = [('input','i_axis_aclk',1),('input','i_axis_arstn',1),
          ('input','i_s_axis_tdata',64),('input','i_s_axis_tuser',32),
          ('input','i_s_axis_tvalid',1),('output','o_s_axis_tready',1),
          ('output','o_m_axis_tdata',64),('output','o_m_axis_tuser',32),
          ('output','o_m_axis_tvalid',1),('input','i_m_axis_tready',1)]


def publish(name, ports, behavior, path=None):
    module = copy.deepcopy(BASE)
    module.update(name=name, rtl_path=path or f'rtl/{name}.v', description=behavior[0])
    module['interfaces']['ports'] = [dict(name=n,direction=d,width=w,
        role='clock' if n=='i_axis_aclk' else 'reset' if n=='i_axis_arstn' else 'data' if w>1 else 'control',
        description=n) for d,n,w in ports]
    module['behavior'] = behavior
    module['constraints'] = ['Verilog-2001; single 50MHz clock; signed Q26 audio, signed 18-bit Q16 feedback RAM.',
        'See FX.md for numerical equations, command layout and limits. No board timing claim.',
        'Clear only while idle, RAM validity reset without clearing memory contents. Reset cancels in-flight work.']
    module['verification_cases'] = ['Independent integer model, stereo impulses and random full-scale inputs',
        'Fractional and maximum delay, bypass, clipping and zero-input tail decay',
        'Backpressure and reset; independent command replay; atomic parameter commit; 1024-clock deadline']
    module['timing_diagrams'][0]['description'] = '在输入握手时锁存一帧及配置，多周期读写反馈RAM。完成结果暂停期间保持不变。示意图不代表实际时钟延迟。'
    (ROOT/f'spec/{name}_contract.json').write_text(json.dumps({'modules':[module]},indent=2,ensure_ascii=False)+'\n',encoding='utf-8')


def generate():
    endpoint=json.loads((ROOT/'spec/AxiVoiceEndpoint_contract.json').read_text(encoding='utf-8'))['modules'][0]
    lean=copy.deepcopy(endpoint)
    lean.update(name='AxiSynthEndpoint',rtl_path='rtl/AxiSynthEndpoint.v',description='新合成系统的精简AXI顶层，排除旧raw/context调试计算分支。')
    lean['behavior']=['Same AXI/PCM ports and bounded AXI protocol as AxiVoiceEndpoint, with LEGACY_ENABLE=0.',
        'Voice A0..A9, LFO B0..B3, FX C0..C4 remain available. Legacy capability/context capacity registers are zero.',
        'Unsupported command returns status 1 with original tag; does not hang or block audio. ABI 0x00010005.']
    (ROOT/'spec/AxiSynthEndpoint_contract.json').write_text(json.dumps({'modules':[lean]},indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    publish('AxisStereoDelay', STREAM+[('input','i_config',160),('input','i_clear',1),('output','o_clipped',1)], [
        '共享立体声分数延迟；每声道深度2**C_DELAY_ADDR_BITS，默认15，整板使用14；参数随握手锁存。',
        'Config words: Q16.16 left/right delay (1..2**C_DELAY_ADDR_BITS-1/65536 samples), signed Q26 feedback, Q26 wet, flags enable/pingpong.',
        'Synchronous read RAM, linear interpolation, Q52 feedback sum quantized toward zero to Q16; state saturation ±2, output saturation ±1.',
        'Disabled effect returns dry input exactly; zero injection lets the hidden tail decay. Clear invalidates history in constant time.',
        'One input in flight; sample tag unchanged; output stalls do not repeat state writes.' ])
    publish('AxisSchroederReverb', STREAM+[('input','i_config',128),('input','i_clear',1),('output','o_clipped',1)], [
        '四路低通反馈梳状滤波加左右各两级真正全通滤波，单声道激励、立体声尾音。',
        'Config words: Q26 feedback [0,0.9], damping [0,0.95], wet [0,1], enable [0,1].',
        'Comb lengths 1493,1601,1747,1999. Left allpasses 211,431; right 263,487. Allpass coefficient 0.5.',
        'One synchronous 10240-word RAM; 18-bit Q16 feedback, Q26 damping state, Q52 sums quantized toward zero.',
        'Two signed32 multiplier lanes shared between damping, feedback and separate left/right mixing. Registered Q26 unity complements fit exactly for valid controls. One added clock; sample arithmetic unchanged.',
        'Clear resets pointers, age and filter state only. Bypass injects zero but continues tail decay; dry path is bit-exact.' ])
    control = [('input','i_axis_aclk',1),('input','i_axis_arstn',1),
        ('input','i_s_axis_tdata',384),('input','i_s_axis_tuser',32),('input','i_s_axis_tdest',8),
        ('input','i_s_axis_tvalid',1),('output','o_s_axis_tready',1),
        ('output','o_m_axis_tdata',128),('output','o_m_axis_tuser',32),('output','o_m_axis_tdest',8),
        ('output','o_m_axis_tvalid',1),('input','i_m_axis_tready',1),
        ('input','i_audio_data',64),('input','i_audio_frame',32),('input','i_audio_valid',1),('output','o_audio_ready',1),
        ('output','o_audio_data',64),('output','o_audio_frame',32),('output','o_audio_valid',1),('input','i_audio_ready',1),
        ('output','o_frames',32),('output','o_clipped_frames',32),('output','o_cycles',32)]
    publish('AxisFxEngine', control, ['独立FX命令域：草稿参数原子提交，Delay→Reverb持续处理音频。',
        'C0 Delay draft, C1 Reverb draft, C2 commit, C3 clear mask, C4 query. Epoch/sequence independent from voice and legacy domains.',
        'First sequence zero binds epoch; exact latest request replay returns cached response with bit72 and fresh tag; conflicts/gaps/stale requests reject.',
        'Control accepted between frames, completion backpressure never stops audio; clear and commit prevent audio acceptance on the same edge.',
        'Chunked predecode registers21 signature comparisons and10 payload-zero words. A second stage registers result, sequence eligibility and five action bits before READY; raw parameter validation no longer drives configuration/clear enables. Audio cancels both stages and retains priority; idle command validation adds one clock, audio latency remains unchanged.',
        'Note lifecycle does not own FX state. Tail survives NoteOff and patch commit. Counts increment exactly once per output transfer.' ])
    plan = dict(requirements='Shared stereo modular Delay/Reverb behind existing bounded AXI4-MM endpoint',
        order=['contracts and WaveDrom','Python integer model','RTL','xsim numeric/protocol/deadline','Gowin synthesis','strict gate'],
        resources=dict(delay_words=65536,reverb_words=10240,bits=18),
        review=dict(interface='AXI-MM command mailbox plus private ready-valid stereo samples', reset='Age counters invalidate RAM; asynchronous control reset',
            timing='FX actual72 clocks after voice874; full-chain948/1024 with synchronous program RAM, pipelined modulation and stereo pan', widths='Q52 signed sums; explicit TZ and saturation',
            risks=['No current board top integration','Abrupt live delay changes may click','Simple Schroeder room, not Surge/DX emulation']))
    (ROOT/'spec/fx-plan.json').write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8')


if __name__ == '__main__':
    generate()
