"""Extend existing interface contracts and render same-name specifications."""
from pathlib import Path
import json,os,subprocess,copy
ROOT=Path(__file__).resolve().parent;SKILL='C:/Users/asddddd28/.agents/skills/readable-verilog-generator'
PY=ROOT.parent/'desktop/.venv/Scripts/python.exe'
def load(path):return json.loads(path.read_text())['modules'][0]
def port(name,width,direction,description):return dict(name=name,width=width,direction=direction,description=description,role='clock' if name=='i_clk' else 'reset' if name=='i_rstn' else 'data')
contracts=[]
for name in ['KeyboardThresholds','KeyboardVoiceBridge','KeyboardAxisTop','KeyboardSynthTelemetry','tb_keyboard_audio']:
    contracts.append(load(ROOT.parent/'keyboard-axis/spec'/f'{name}_contract.json'))
extra=[('volume',4,'主音量0至8'),('active_count',6,'ADSR非空闲声部数，包括释音'),('gain',19,'平滑后的Q16增益'),('input_peak',24,'处理前采样峰值保持'),('output_peak',24,'处理后采样峰值保持'),('clips',32,'保护限幅累计次数'),('stages',7,'已提交阶段累计位图'),('wave_peak',32,'振荡波形绝对峰值'),('mod_peak',32,'AM输出绝对峰值'),('env_peak',18,'包络整数峰值')]
for m in contracts:
 if m['name']=='KeyboardAxisTop':m['behavior']+=['命令0至8设置主音量，默认6；ADSR释音仍计入发声数，按4/sqrt(N)及音量缩放，增益变化平滑。','输出经四拍响度流水后送入PT8211，64字节遥测包含电平、增益和限幅。']
 if m['name']=='KeyboardSynthTelemetry':
  m['interfaces']['ports'] += [port('i_'+n,w,'input',d) for n,w,d in extra]
  m['behavior']=['周期锁存64字节快照；头A5 5A 02 40，0至61字节XOR写62，63字节0D。','0至29字节沿用旧状态布局，30音量，31声部数，32增益，36输入峰值，40输出峰值，44限幅计数，48包络峰值，52波形峰值，56调制峰值，60阶段位图，61音量副本。','多字节整数小端；发完整包后才重新锁存，等待UART停止位。']
 if m['name']=='tb_keyboard_audio':m['behavior']+=['增加32键同时按下、释音仍计入补偿、音乐和弦无限幅，以及64字节遥测校验。']
for old,name in [('AxisSynthEngine','KeyboardSynthEngine'),('AxisSynthSystem','KeyboardAudioSystem')]:
 m=load(ROOT.parent/'spec'/f'{old}_contract.json');m['name']=name;m['rtl_path']='src/'+name+'.v'
 if old=='AxisSynthEngine':
  additions=[('active',32,'实际ADSR非空闲位图'),('stages',7,'已接受阶段位图'),('wave_peak',32,'振荡峰值'),('mod_peak',32,'AM峰值'),('env_peak',18,'包络峰值')]
  m['interfaces']['ports'] += [port('o_'+n,w,'output',d) for n,w,d in additions]
  m['behavior']+=['保留原有算术和调度；仅观察flag_commit有效结果，包络stage非0保持活动，包含release。']
 else:
  m['interfaces']['ports'] += [port(('i_' if n=='volume' else 'o_')+n,w,'input' if n=='volume' else 'output',d) for n,w,d in extra]
  m['behavior']+=['Engine与I2sTx之间插入KeyboardLoudness，计算448拍后增加四拍音量处理；1024拍截止期不变。']
 contracts.append(m)
base=copy.deepcopy(contracts[0]);base['name']='KeyboardLoudness';base['rtl_path']='src/KeyboardLoudness.v'
base['interfaces']['ports']=[port(n,w,d,desc) for n,w,d,desc in [('i_clk',1,'input','50MHz时钟'),('i_rstn',1,'input','异步低有效复位'),('i_valid',1,'input','每音频帧一次PCM'),('i_sample',24,'input','有符号PCM'),('i_active',32,'input','ADSR非空闲位图'),('i_volume',4,'input','0至8主音量'),('o_valid',1,'output','四沿后有效'),('o_sample',24,'output','舍入限幅PCM')]]+[port('o_'+n,w,'output',d) for n,w,d in extra if n in ['active_count','gain','input_peak','output_peak','clips']]
base['behavior']=['固定除32混音之后，Q16目标增益=floor(4*65536/sqrt(max(N,1)))*volume/8。','N来自实际包络，包含释音。音量0至8，越界钳位8。','每帧增益向下ceil(delta/64)，向上ceil(delta/4096)；最后恰好达到静音。','四级有效流水：完整乘积、绝对值、对称半值远离零舍入、限幅至正负0x700000。','峰值以约84ms时间常数衰减；限幅次数饱和计数。电平不是LUFS；没有前视限幅，超阈值样本可能失真。']
base['verification_cases']=['55500独立整数向量','多复音与增益切换','最负数和正满量程','管线复位取消','32键音乐和弦与松键']
base['timing_diagrams']=[dict(id='pcm',title='四沿输出',scenario='pipeline',description='第一个沿接收乘积，第四沿提交限幅结果。',wavejson={'signal':[{'name':'clk','wave':'p......'},{'name':'i_valid','wave':'010....'},{'name':'o_valid','wave':'0...10.'}]})]
contracts.append(base)
mix=load(ROOT.parent/'spec/SynthFrameMixer_contract.json');mix['name']='KeyboardFrameMixer';mix['rtl_path']='src/KeyboardFrameMixer.v'
mix['behavior']+=['仅用于32声部，40位累加足以保留32个signed32样本之和。输入、最终帧和、缩放及限幅分别寄存，数值与旧64位实现一致；PCM发布比旧版增加三拍。','i_start必须在上一帧完全退役后，i_last只随最后有效输入；当前Engine已保证这些条件。']
contracts.append(mix)
bench=copy.deepcopy(base);bench['name']='tb_keyboard_loudness';bench['rtl_path']='sim/tb_keyboard_loudness.v';bench['interfaces']['ports']=[port('o_done',1,'output','独立向量与复位检查完成')];contracts.append(bench)
for m in contracts:
 name=m['name'];path=ROOT/'spec'/f'{name}_contract.json';path.write_text(json.dumps({'modules':[m]},ensure_ascii=False,indent=2))
 with (ROOT/'reports'/f'{name}_spec.log').open('w') as out:
  source_args=[] if name.startswith('tb_') else ['--source',str(ROOT/m['rtl_path'])]
  r=subprocess.run([str(PY),'-m','scripts.python.workflow.cli','write-spec','--spec',str(path),'--out-dir',str(ROOT),*source_args,'--language','zh'],env={**os.environ,'PYTHONPATH':SKILL,'PYTHONUTF8':'1'},stdout=out,stderr=subprocess.STDOUT)
 if r.returncode:raise SystemExit('Spec failed '+name)
print('PASS contracts and diagrams',len(contracts))
