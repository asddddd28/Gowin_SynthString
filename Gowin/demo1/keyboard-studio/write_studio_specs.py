from pathlib import Path
import copy,json,os,subprocess
ROOT=Path(__file__).resolve().parent
SKILL='C:/Users/asddddd28/.agents/skills/readable-verilog-generator'
PY=ROOT.parent/'desktop/.venv/Scripts/python.exe'
base=json.loads((ROOT/'spec/KeyboardVoiceBridge_contract.json').read_text())['modules'][0]
def ports(text):
 result=[]
 for token in text.split():
  name,_,width=token.partition(':');result.append(dict(name=name,width=int(width or 1),direction='input' if name.startswith('i_') else 'output',description=name.replace('_',' '),role='clock' if name in ['i_clk','i_axis_aclk'] else 'reset' if name in ['i_rstn','i_axis_arstn'] else 'data'))
 return result
new={
 'StudioVoiceStore':('i_clk i_rstn i_cfg_write i_cfg_voice:5 i_cfg_data:512 i_read_voice:5 o_profile:512 o_state:384 i_write i_write_voice:5 i_write_stage:3 i_write_data:192 i_event_consume i_event_voice:5',[
 '参数512位及384位状态按字段分同步RAM；读延迟一拍，调度器至少等待两拍预取。',
 '写回先寄存，再写RAM。每个状态字段仅一个写口；不复位RAM本体，启动配置bit482清零状态。',
 'bit483只写事件并保留发声参数。调制包络先读事件，振幅包络发射后消费一次性事件。']),
 'StudioOscMixer':('i_axis_aclk i_axis_arstn i_s_axis_tdata:136 i_s_axis_tuser:21 i_s_axis_tvalid o_s_axis_tready o_m_axis_tdata:64 o_m_axis_tuser:21 o_m_axis_tvalid i_m_axis_tready',[
 '136位任务含Q26载波、调制源、深度、2位AM模式、mix开关、两个Q16音量。',
 '七拍算术：锁存、深度乘法、AM因子、载波乘法、两个音量乘法、混合、饱和。信用池持有票据并支持背压。',
 '混合模式A+B按总增益归一化；FM/AM/环形模式仅输出A，调制振荡器用于控制。']),
 'StudioControl':('i_clk i_rstn i_rx_valid i_rx_error i_rx_data:8 o_ascii_valid o_ascii_data:8 o_patch_valid i_patch_ready o_patch_key:5 o_patch_data:512 o_wave_valid i_wave_ready o_wave_frame o_wave_address:11 o_wave_data:16 o_remote:32 o_velocity:224 o_volume:4 o_volume_valid o_ack_seq:8 o_ack_op:8 o_ack_status:8 o_ack_key:8 o_ack_crc:16 o_commits:32',[
 '长包71字节：A5 C3 op seq key payload64 CRC16小端；CRC-CCITT初始化FFFF，覆盖头及数据。',
 '短包8字节：A5 C4 op seq key value CRC16小端；仅演奏、音量、心跳命令允许。载荷不解释为ASCII。',
 '仅CRC与参数范围通过后提交；配置等待Bridge接受才ACK，波表块等待32个写握手才ACK。',
 '20ms字节超时取消残包；1.5秒无有效主机包释放远程键，实体键不受影响。',
 '64块完成位图保护双帧波表可用性；第0块重置位图，失败需重新完整上传。']),
}
contracts=[]
for name in ['KeyboardAudioSystem','KeyboardSynthEngine','KeyboardVoiceBridge','KeyboardAxisTop','KeyboardSynthTelemetry']:
 m=json.loads((ROOT.parent/'keyboard-performance/spec'/f'{name}_contract.json').read_text())['modules'][0]
 for p in m['interfaces']['ports']:
  if p['name'] in ['i_cfg_data','o_cfg_data']:p['width']=512
 m['constraints']=['Tang Mega 60K；50MHz统一计算时钟；1024拍音频帧；固定32个逻辑声部。']
 if name=='KeyboardVoiceBridge':
  m['interfaces']['ports']+=ports('i_patch_valid o_patch_ready i_patch_key:5 i_patch_data:512 i_velocity:224')
  m['behavior']=['启动逐声部清零状态并装入ROM初始音色，完成后启动音频。','程序RAM接受CRC验证后的音色；同步读取后在下一note-on复制到活动声部。','note-off仅更新事件，保留发声中的旧参数，直到释音结束。','物理键与远程键合并；一次事件提交后等待音频帧结束，避免覆盖未消费的事件。']
 elif name=='KeyboardSynthTelemetry':
  m['interfaces']['ports']+=ports('i_ack_seq:8 i_ack_op:8 i_ack_status:8 i_ack_key:8 i_ack_crc:16 i_commits:32')
  m['behavior']=['80字节快照：A5 5A 03 50；0..61保持旧遥测布局。','62seq、63op、64status、65key、66..67CRC、68..71配置提交数、72..75能力位、76..77保留、78 XOR(0..77)、79=0D。','100ms周期锁存一次，发完整包后再锁存；ACK不是命令发送的本地回显。']
 elif name=='KeyboardSynthEngine':m['behavior']=['八阶段顺序7→0→1→2→3→4→5→6：调制包络、B相位、B波形、A相位FM、A波形、振幅包络、混合AM、SVF/VCA。','每次新声部等待两拍同步RAM预取及调制深度乘法，然后发射带票据任务。','32声部共享计算核心，下一阶段等待所有当前阶段结果返回；RAM写回增加一拍，由预取等待覆盖。','事件消费位于振幅包络阶段；活动声部计数仅取振幅包络，包含release。']
 elif name=='KeyboardAudioSystem':m['behavior']=['串联八阶段合成器、固定除32混音、1/sqrt(N)补偿与主音量、PT8211。','采样率50000000/1024=48828.125Hz；PCM必须在下一帧开始前提交。','左右声道复制单声道；波表写入仅在引擎空闲窗口接受。']
 else:m['behavior']=['实际ADC引脚采样、迟滞判键、程序RAM、AXIS合成、响度控制和PT8211构成完整链路。','StudioControl处理带CRC参数包与短演奏包，保留空闲时ASCII T/P和0..8。','程序和波表存储在片上RAM，掉电丢失；不修改SD卡或Flash。']
 contracts.append(m)
for name,(interface,behavior) in new.items():
 m=copy.deepcopy(base);m.update(name=name,rtl_path='src/'+name+'.v',description=behavior[0],behavior=behavior)
 m['interfaces']['ports']=ports(interface)
 if name=='StudioOscMixer':m['clock']['name']='i_axis_aclk';m['reset']['name']='i_axis_arstn'
 contracts.append(m)
for m in contracts:
 name=m['name'];m['constraints']=['50MHz单时钟域；异步低有效复位，板级同步释放。','新固件协议与旧96kHz Studio不兼容，必须核对版本3。']
 m['corner_cases']=['复位取消旧任务','输出背压','32键复音','CRC失败与残包','参数在释音中更新']
 m['verification_cases']=['完整ADC/UART/PT8211闭环','400个混合整数向量','配置ACK及短演奏包','无覆盖的活动参数快照','Gowin综合实现时序']
 m['timing_diagrams']=[dict(id='commit',title='参数与任务提交',scenario='handshake',description='有效期间保持完整事务，接受后才发射或确认；算术延迟见行为合同。',wavejson={'signal':[{'name':m['clock']['name'],'wave':'p......'},{'name':'valid','wave':'01..0..'},{'name':'ready','wave':'0..10..'},{'name':'commit','wave':'0...10.'}]})]
 path=ROOT/'spec'/f'{name}_contract.json';path.write_text(json.dumps({'modules':[m]},ensure_ascii=False,indent=2))
 with (ROOT/'reports'/f'{name}_spec.log').open('w') as out:r=subprocess.run([str(PY),'-m','scripts.python.workflow.cli','write-spec','--spec',str(path),'--out-dir',str(ROOT),'--source',str(ROOT/m['rtl_path']),'--language','zh'],env={**os.environ,'PYTHONPATH':SKILL,'PYTHONUTF8':'1'},stdout=out,stderr=subprocess.STDOUT)
 if r.returncode:raise SystemExit('Specification failed: '+name)
print('PASS Studio contracts and timing diagrams',len(contracts))
