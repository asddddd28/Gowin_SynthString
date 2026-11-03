"""Publish explicit pre-RTL interface contracts, consumed by registered write-spec."""
import copy
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASE=json.loads((ROOT/'spec/AxisPhasePm_contract.json').read_text(encoding='utf-8'))['modules'][0]

def contract(name, description, extra, widths, behavior):
    module=copy.deepcopy(BASE)
    module.update(name=name,rtl_path=f'rtl/{name}.v',description=description)
    ports=module['interfaces']['ports']
    for p in ports:
        if p['name'] in widths: p['width']=widths[p['name']]
    for direction,port,width,desc in extra:
        ports.append(dict(name=port,direction=direction,width=width,role='data' if width>1 else 'control',description=desc))
    module['behavior']=behavior
    module['constraints']=['Single 50 MHz clock domain; reset cancels in-flight work.','See ENGINE.md for exact fixed-point and command ABI.','Candidate: board timing and strict style gate are separate from functional simulation.']
    module['verification_cases']=['Independent Python integer model versus xsim','Backpressure stability and reset cancellation','Illegal parameters and voice lifecycle','1024-clock frame deadline under eight voices and six operators']
    module['timing_diagrams'][0]['description']='请求锁存后运算；结果可以暂停，已驻留声部仍按采样时钟推进。图示握手关系，不按图推断延迟。'
    (ROOT/f'spec/{name}_contract.json').write_text(json.dumps({'modules':[module]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def generate():
    contract('AxisFmOperator','单个可复用 PM/FM/AM/Ring 算子，EG 与波形计算并行。',[
        ('input','i_wave_write',1,'仅空闲时写波表'),('input','i_wave_address',11,'帧与采样地址'),
        ('input','i_wave_data',32,'有符号 Q26 采样'),('output','o_wave_ready',1,'波表可安全写入')],
        {'i_s_axis_tdata':672,'o_m_axis_tdata':160},[
        '21-word request contains phase, increment, modulation, depth, gain, EG state/control/eight parameters, two feedback samples, feedback depth, noise state, waveform/mode flags, shape.',
        'Output words: sample, next phase, EG level, EG flags, next noise state.',
        'Independent four-stage linear EG advances once per request. Feedback reads two previous samples, not current output.',
        'Six waveform types; 1024-point interpolated sine and two writable frames; initial tables are sine.',
        'Two signed33-by-signed32 multiplier lanes share phase/feedback and gain phases. Dedicated signed33-by-positive23 interpolation registers retain the full56-bit products before the base addition; morph remains signed33-by-positive18 with51 bits. State2 reads tables; state3 registers interpolation products; state4 adds bases; state5 computes morph and AM/ring factor; state6 computes wave*factor and accepts EG; state7 extracts the scaled wave and computes EG*gain; state8 computes the sample; state9 stores the result; state10 is valid. State6 may wait for EG. Preserve native64 and factor65 slices; native request latency is ten clocks; pipelined DX envelope extends DX requests to eleven clocks.',
        'Single in-flight request. Output and tag stable during backpressure. Table writes only when idle and no request accepted.' ])
    contract('VoiceSynthEngine','驻留音色程序、8 声部生命周期与 6 算子逐采样调度。',[
        ('input','i_s_axis_tdest',8,'高层命令 A0..A9 与调制 B0..B3'),('output','o_m_axis_tdest',8,'完成的命令'),
        ('input','i_sample_tick',1,'一个采样周期的启动脉冲'),('output','o_pcm_valid',1,'单周期完成脉冲'),
        ('output','o_pcm_data',64,'左右 Q26 采样'),('output','o_frame',32,'完成帧数'),
        ('output','o_overruns',32,'忙碌时到来的采样脉冲'),('output','o_render_cycles',32,'最近一次渲染时钟数'),
        ('output','o_active',8,'活动声部位图')],{'i_s_axis_tdata':384,'o_m_axis_tdata':128},[
        'Four patch slots, two atomic parameter banks each; six topologically ordered operators per patch.',
        'Synchronous RAM outputs prefetch the next core/envelope/context row during states1/2/3. Current carrier is latched; history writeback takes current request last, not the prefetched row. State4 now registers final route sum/saturation after state1 partial sums; state17 is removed. Voice gain/pan row selection, smoothing and modulation occupy states13/14/15. Native full-load voice834; optional FX chain908. Board defaults to C_FX_ENABLE=0 and dry PCM.',
        'State16 registers unsigned27 left/right pan coefficients. State7 multiplies signed32 audio by signed27 zero-extended low26 coefficient bits; state18 selects exact sample<<26 for unity or sign-extends the full59-bit product. Inactive voices still clear products in state1 and skip directly to state8.',
        'Packed163-bit context RAM has one synchronous read and one result write. New NoteOn invalidates its eight context flags; first use supplies zero phase/level/history and context+1 noise seed. Initialization is independent from pending gate events.',
        'Eight dynamic voices, independent phase/EG/noise/feedback state; a single physical composite operator is scheduled for each enabled logical operator.',
        'Control sequence/epoch protects retries; note identity protects held-key duplicate events; note release never targets a replacement with another identity.',
        'Commands apply between frames; completion backpressure never freezes audio rendering.',
        'Note lookup scans one voice row per clock; first free and oldest active ties retain legacy ordering. A sample tick cancels and restarts the scan.',
        'Predecode registers 21 signature-equality chunks and 10 payload-zero words; identity/business checks and final result selection occupy two following stages. READY follows checked status; sample ticks cancel all stages without delaying audio.',
        'VoiceModulation advances patch-global and voice-local LFOs once per enabled audio frame, then resolves eight routes per voice; base parameters remain unchanged.',
        'Fixed voice-capacity headroom, normalized carriers, smoothed live gain/pan and stereo output. This is a generic engine, not exact DX7 or Surge emulation.' ])
    contract('AxisSynthSystem','兼容旧任务的内部互联与持续采样时钟、PCM 队列。',[
        ('input','i_s_axis_tdest',8,'任务目的操作码'),('input','i_s_axis_tlast',1,'原子命令边界'),
        ('output','o_m_axis_tdest',8,'完成操作码'),('output','o_m_axis_tlast',1,'完成均为单拍'),
        *[('output','o_count_'+n,32,'旧上下文计数') for n in ('executed','replayed','rejected','bound')],
        ('output','o_pcm_valid',1,'PCM 队列有数据'),('input','i_pcm_ready',1,'消费 PCM'),
        ('output','o_pcm_data',64,'左右 Q26 采样'),('output','o_pcm_frame',32,'对应完成帧'),
        ('output','o_overruns',32,'采样期限错过'),('output','o_pcm_dropped',32,'PCM 队列满丢弃新帧'),
        ('output','o_render_cycles',32,'最近渲染周期'),('output','o_active',8,'活动声部位图'),
        ('output','o_fx_frames',32,'FX处理帧数'),('output','o_fx_clipped',32,'FX削波帧数'),
        ('output','o_fx_dropped',32,'FX输入丢帧数'),('output','o_fx_cycles',32,'FX处理时钟数')],
        {'i_s_axis_tdata':384,'o_m_axis_tdata':128},[
        'C_FX_ENABLE=0 removes the FX instance and input storage; dry Voice PCM enters the original PCM queue. FX commands return unsupported in the board LEGACY_ENABLE=0 configuration.',
        'Single-beat A0..A9 and B0..B3 route to the resident engine; C0..C4 route to the independent shared FX domain.',
        'LEGACY_ENABLE defaults to one for compatibility; the AxiSynthEndpoint wrapper sets zero and returns unsupported status 1 to old raw/context commands.',
        'Malformed packet head and tails remain in the legacy drain domain.',
        'Three-way round-robin completion arbitration latches ownership while stalled. PCM uses a separate four-entry FIFO.',
        'Two-entry ingress queue adapts voice PCM pulses to AxisFxEngine; Delay then Reverb own shared tail state; output FIFO full drops new frames without freezing feedback.',
        'Sample tick every 1024 clocks; PCM full drops new frame and increments telemetry without blocking synthesis.' ])

def refresh_endpoint_and_tests():
    path=ROOT/'spec/AxiVoiceEndpoint_contract.json'
    endpoint=json.loads(path.read_text(encoding='utf-8'))['modules'][0]
    ports=endpoint['interfaces']['ports']
    existing={p['name'] for p in ports}
    for direction,name,width,description in [
        ('output','o_pcm_valid',1,'PCM 队列输出有效'),('input','i_pcm_ready',1,'PCM 消费者接纳'),
        ('output','o_pcm_data',64,'左右 signed Q26 采样'),('output','o_pcm_frame',32,'采样帧编号')]:
        if name not in existing: ports.append(dict(name=name,direction=direction,width=width,role='data' if width>1 else 'control',description=description))
    endpoint['behavior']=[b for b in endpoint['behavior'] if not b.startswith('Engine extension:')]
    holding='Registered424-bit command head separates FIFO read selection from runtime decode. VALID holds until READY; only this handshake pops the queue, preserving four-entry capacity. Reset discards any held command.'
    if holding not in endpoint['behavior']: endpoint['behavior'].append(holding)
    endpoint['behavior'].append('Engine extension: ABI 0x00010005; A0..A9 voice, B0..B3 modulation, C0..C4 shared FX; 0x048 modulation and 0x04c..0x060 FX capabilities/telemetry. LEGACY_ENABLE=0 removes old raw/context hardware and clears 0x00c/0x01c/0x030 capabilities. Independent PCM FIFO and 0x300..0x30c AR snapshot. See FX.md, MODULATION.md and ENGINE.md.')
    path.write_text(json.dumps({'modules':[endpoint]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    template=json.loads((ROOT/'spec/tb_voice_context_contract.json').read_text(encoding='utf-8'))['modules'][0]
    tests={
        'tb_fm_operator':['2656 Python oracle vectors; 2048 uploaded table points; stalled result stability; reset cancellation.'],
        'tb_voice_engine':['400 stereo frames versus independent Python; two patches, 8 voices, 48 logical operators.', 'Sustain, duplicate NoteID, sequence replay/conflict/gap, live pitch/gain/pan, oldest stealing, stale release, panic, reset and control backpressure.'],
        'tb_axi_synth_engine':['AXI patch upload, continuous PCM, parameter-bank commit, replay, legacy arithmetic coexistence, PCM FIFO overflow and coherent AR snapshot.'],
        'tb_voice_presets':['Five actual compiler outputs executed in RTL; 10240 stereo frames versus Python; three-voice played chord.'],
        'tb_axi_voice_endpoint':['Legacy AXI interface/context regression against ABI 0x00010006 with LEGACY_ENABLE=1.'],
        'tb_lfo_step':['3560 independent LFO oracle vectors; five-cycle transfer latency, II=1, stalls and reset cancellation.'],
        'tb_lfo_engine':['1600 stereo PCM frames and 38400 source-state snapshots; eight voices, seven shapes, signed routes and all target types.', 'Global/key-synced scopes, live bank commit, duplicate NoteID, sustain/release, source inspection/retry and deadline.'],
        'tb_axi_lfo':['Three actual compiled LFO example patches via AXI; persistent PCM, global/local lifetime, duplicate NoteOn, exact B2 replay and invalid requests.']}
    for name,behavior in tests.items():
        m=copy.deepcopy(template); m.update(name=name,rtl_path=f'sim/{name}.v',description=behavior[0],behavior=behavior,verification_cases=behavior)
        (ROOT/f'spec/{name}_contract.json').write_text(json.dumps({'modules':[m]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    modules=[]
    for path in sorted((ROOT/'spec').glob('*_contract.json')):
        if path.name.startswith('tb_'): continue
        modules.extend(json.loads(path.read_text(encoding='utf-8'))['modules'])
    (ROOT/'spec/operators.json').write_text(json.dumps({'modules':modules},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':
    generate()
    from dx7_contracts import main as dx_contracts
    dx_contracts()
    refresh_endpoint_and_tests()
