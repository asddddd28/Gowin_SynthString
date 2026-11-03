"""Render explicit contracts for changed interfaces using the installed renderer."""
from pathlib import Path
import json,os,subprocess,sys,copy
ROOT=Path(__file__).resolve().parents[1]
engine=ROOT.parent/'voice-engine'
template=json.loads((ROOT/'spec/SynthKeyboardSource_contract.json').read_text(encoding='utf-8'))['modules'][0]
def port(name,width=1):
    return dict(name=name,direction='input' if name.startswith('i_') else 'output',width=width,clock_domain='i_clk',role='clock' if name=='i_clk' else 'reset' if name=='i_rstn' else 'data' if width>1 else 'control',description=name)
added={
'SynthKeyboardSource':[('i_config_write',1),('i_config_key',5),('i_config_data',48),('o_config_data',48),('o_event_start',1),('o_event_finish',1),('o_event_failed',1),('o_event_key',5),('o_event_frame',32)],
'SynthUartControl':[('o_local_request',1),('o_local_opcode',8),('o_local_argument',8),('o_local_words',64),('i_local_valid',1),('i_local_response',136)],
'SynthPcmOutput':[('o_sample_valid',1),('o_sample',16)],
'SynthSystemTop':[],
}
behavior={
'SynthKeyboardSource':['32 physical keys use a synchronous 48-bit RAM mapping: phase32, slot2, MIDI7, velocity7. Power-up defaults remain MIDI48..79, patch0, velocity100.','The scan port latches a complete mapping before preparing a note. Configuration writes acknowledge after the write edge. Concurrently prepared events retain the latched mapping.','Held-key remapping never retriggers; Note-Off retains its original identity. New presses receive a fresh bit31-set identity and use the new mapping.','o_event_start observes PREPARE for Note-On; o_event_finish observes the accepted response. o_event_frame is completion bits63:32. Failed events are cancelled by the passive monitor.'],
'SynthUartControl':['Protocol5 retains 52-byte requests and 32-byte CRC16 responses. Kinds0/1/2 preserve existing AXI/status behavior.','Kind3 dispatches to a board-local monitor, with unused payload words2..9 required zero. LOCAL_SEND is a single-cycle pulse; LOCAL_WAIT waits for completion.','Duplicate sequence plus identical complete payload replays the cached response without another write or capture trigger. Changed duplicate and out-of-order sequence reject without side effects.','Local operation errors consume their sequence and are cached, exactly like other validated requests.'],
'SynthPcmOutput':['PT8211 runs at 50MHz/1024 with signed16 left/right samples, rounded and saturated from Q26.','o_sample_valid is true only on the actual output frame acceptance; o_sample is that same signed16 left-channel value. No sampling, interpolation or visualization affects audio readiness.'],
'SynthSystemTop':['SynthStudioMonitor connects to the UART local command port, keyboard mapping RAM and actual PT8211 frame acceptance.','DSP AXI routing, six-operator pool, eight voices, 50MHz clock and 1024-cycle sample period remain unchanged.','Audio capture and host reads are passive. The monitor tracks one key dispatch at a time, correlates the Note-On completion frame tag, and reports cycles to that exact output frame.'],
}
paths=[]
for name,extra in added.items():
    path=ROOT/f'spec/{name}_contract.json';c=json.loads(path.read_text(encoding='utf-8'));m=c['modules'][0]
    ports=m['interfaces']['ports'];seen={p['name'] for p in ports}
    ports.extend(port(n,w) for n,w in extra if n not in seen)
    m['clock']['name']='i_clk';m['reset']['name']='i_rstn';m['behavior']=behavior[name]
    m['verification_cases']=['Full existing board regression: 134 UART replies, all 32 keys, eight-voice load and serial DAC.','tb_studio_system: local command CRC/replay, distinct key patches, held remapping/release, 512 signed16 capture samples compared to DAC quantization, tagged latency.']
    path.write_text(json.dumps(c,ensure_ascii=False,indent=2),encoding='utf-8');paths.append((ROOT,path))
m=copy.deepcopy(template);m.update(name='SynthStudioMonitor',rtl_path='rtl/SynthStudioMonitor.v',description='Independent board-local key mapping control, frozen PCM capture and tagged digital output latency.')
m['interfaces']['ports']=[port(n,w) for n,w in [('i_clk',1),('i_rstn',1),('i_request',1),('i_opcode',8),('i_argument',8),('i_words',64),('o_response_valid',1),('o_response',136),('o_key_write',1),('o_key_index',5),('o_key_data',48),('i_key_data',48),('i_pcm_valid',1),('i_pcm_sample',16),('i_pcm_frame',32),('i_key_start',1),('i_key_finish',1),('i_key_failed',1),('i_event_key',5),('i_event_frame',32)]]
m['clock']['name']='i_clk';m['reset']['name']='i_rstn'
m['behavior']=['Command pulse latches opcode/argument/words; VALIDATE then EXECUTE; RESPOND asserts one cycle. No second command until response.','Opcodes0..5 implement the exact table in UNIFIED_STUDIO_CONTRACT.md. Invalid arguments return status5; capture busy/not-ready returns10.','Capture starts at the next accepted PCM frame and freezes after512 signed16 left samples; 64 chunks of8 samples read synchronously in16 clocks.','Latency starts at key PREPARE, commits target tag on successful Note-On response, ends on matching PCM frame. Only one observation is in flight; other keys still execute normally.','Reset clears capture-ready and observation state. Mapping RAM initialization belongs to SynthKeyboardSource.']
m['corner_cases']=['Capture trigger while busy; read before ready; malformed opcode or argument.','Identical request replay handled by SynthUartControl without repeating side effects.','Old PCM frames queued before a key command do not complete the tagged latency observation.','Simultaneous keys coalesce monitoring only; failed Note-On cancels pending observation.']
m['verification_cases']=['studio_monitor_model.py independent PCM rounding and scheduling model','tb_studio_system bit-exact output sample capture and mapped real key path']
m['timing_diagrams']=[dict(id='local',title='本地命令与冻结快照读取',scenario='local',description='命令锁存、校验、执行；读样本每两拍装入一个16位结果，最后响应。此图是阶段示意。',wavejson={'signal':[{'name':'clk','wave':'p.........'},{'name':'request','wave':'010.......'},{'name':'state','wave':'x=========','data':['LATCH','VALIDATE','EXECUTE','READ','COLLECT','READ','COLLECT','...','RESPOND']},{'name':'response_valid','wave':'0........1'}]})]
path=ROOT/'spec/SynthStudioMonitor_contract.json';path.write_text(json.dumps({'modules':[m]},ensure_ascii=False,indent=2),encoding='utf-8');paths.append((ROOT,path))
path=engine/'spec/VoiceSynthEngine_contract.json';c=json.loads(path.read_text(encoding='utf-8'))
note='Accepted successful Note-On completion bits63:32 carry cnt_frame+1, the first rendered frame affected by that event. Cached replay returns the same frame tag. Other completion words and DSP scheduling are unchanged.'
if note not in c['modules'][0]['behavior']:c['modules'][0]['behavior'].append(note)
path.write_text(json.dumps(c,ensure_ascii=False,indent=2),encoding='utf-8');paths.append((engine,path))
env=os.environ.copy();env['PYTHONPATH']='C:/Users/asddddd28/.agents/skills/readable-verilog-generator';env['PYTHONIOENCODING']='utf-8'
for base,path in paths:
    log=ROOT/f'reports/unified-studio/{path.stem}-spec.log'
    with log.open('w',encoding='utf-8') as f:r=subprocess.run([sys.executable,'-m','scripts.python.workflow.cli','write-spec','--spec',str(path),'--out-dir',str(base),'--language','zh'],cwd=base,env=env,stdout=f,stderr=subprocess.STDOUT)
    if r.returncode:raise RuntimeError(str(log))
print('Rendered six module contracts and timing diagrams')
