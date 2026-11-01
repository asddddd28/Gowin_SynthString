"""Render explicit observation contracts through the registered spec writer."""
from pathlib import Path
import copy,json,os,subprocess,sys
ROOT=Path(__file__).resolve().parent
SKILL='C:/Users/asddddd28/.agents/skills/readable-verilog-generator'
BASE=ROOT.parent/'keyboard-studio/spec'
base=json.loads((BASE/'StudioOscMixer_contract.json').read_text(encoding='utf-8'))['modules'][0]
def ports(text):
    result=[]
    for token in text.split():
        name,_,width=token.partition(':')
        result.append(dict(name=name,width=int(width or 1),direction='input' if name.startswith('i_') else 'output',
            description=name.replace('_',' '),role='clock' if name=='i_clk' else 'reset' if name=='i_rstn' else 'data'))
    return result
contracts=[]
for new,source in [('LatencyAxisTop',ROOT.parent/'keyboard-parallel/spec/ParallelAxisTop_contract.json'),
                   ('LatencyAudioSystem',ROOT.parent/'keyboard-parallel/spec/ParallelAudioSystem_contract.json'),
                   ('LatencySynthTelemetry',BASE/'KeyboardSynthTelemetry_contract.json')]:
    m=json.loads(source.read_text(encoding='utf-8'))['modules'][0]
    m.update(name=new,rtl_path=f'src/{new}.v')
    if new=='LatencyAudioSystem':
        m['interfaces']['ports']+=ports('o_frame_load o_dac_left_latch o_pcm_nonzero')
        m['behavior']=['复用原32声部多核合成与响度；仅增加监测输出，不改变音频数据或背压。',
                       '输出实际串行器加载帧与左声道锁存脉冲；o_pcm_nonzero取24→16位舍入后的非零判断。']
    elif new=='LatencySynthTelemetry':
        m['interfaces']['ports']+=ports('i_latency:880')
        m['behavior']=['192字节协议4；头A5 5A 04 C0，0..77保留Studio公共字段；80..189为110字节延迟快照。',
                       '190=XOR(0..189)，191=CR；整包发送期间快照不可变；约10Hz触发加串行发送耗时。',
                       '命令仍使用原Studio长/短CRC16包。延迟统计L为包外ASCII命令。']
    else:
        m['behavior']=['完整实体键ADC→双确认判键→参数桥→多核合成→响度→PT8211，监测器只观察。',
                       '首次门限候选/二次确认/取消由判键模块提供；远程起点为FPGA有效gate上升沿。',
                       '六种核心数量保持1/2/3/1/1/1；50MHz计算，1024拍输出一帧。',
                       'L仅清零延迟统计和监测事务，不复位声音引擎或更改音色。']
    contracts.append(m)
extra={
 'LatencySupervisor':('i_clk i_rstn i_clear i_initialized i_sample_valid i_sample_key:5 i_candidate i_confirm i_cancel i_physical:32 i_effective:32 i_commit i_commit_key:5 i_result_valid i_result_key:5 i_result_sample:32 i_pcm_valid i_pcm_nonzero i_frame_load i_dac_left_latch o_payload:880',[
  '每键一个监测事务，8状态：空闲、扫描确认、等待提交、等待非零声部、等待非零PCM、等待加载、等待DAC左字锁存、完成。',
  '物理起点为首次ADC越过按下门限，确认在第二次扫描；远程起点为FPGA内部有效gate上升沿，不含主机/串口时间。',
  '记录第一次声部返回和后续选中的非零返回；零PCM继续等待，实际加载该帧后在PT8211左声道锁存沿结束。',
  '分段总和=扫描确认+事件排队+首次计算+非零起音等待+输出等待；输出等待中包含单独列出的混音耗时。',
  '32位50MHz时间戳模减，约85.9秒回绕；事务1秒超时。默认预算10ms，不改变音频节拍。',
  '全部事件与原始时间戳先寄存一拍；逐键快照→差值计算→发布；代号校验丢弃旧事务。32键同时完成最多36拍发布完；统计读出时间不计入延迟。',
  '扫描周期使用共享减法器；PCM/DAC时间戳按帧共享，完成批次必须在下一次相隔1024拍的DAC左字锁存前排空。',
  '新起音覆盖未完成旧事务并累计覆盖计数；每键8位覆盖暂存计数饱和255，每32拍汇总一次。',
  '最小、最大、64位和、完成数、物理/远程数、超预算、超时、取消候选及pending位图通过固定小端字段发布。',
  '没有声学回采；其他声部的混音和非零数据不能保证目标音符已达到可闻响度。']),
 'LatencyKeyThresholds':('i_clk i_rstn i_key:5 i_raw:12 i_valid o_candidate o_confirm o_cancel o_pressed:32',[
  '沿用原门限ROM、迟滞和连续两次完整扫描确认，音频事件行为不变。',
  '候选、确认和取消脉冲均在相应ADC样本握手沿有效，只针对按下过程；释放仍按原逻辑处理。']),
 'LatencyI2sTx':('i_clk i_rstn i_sample_valid i_left:24 i_right:24 o_sample_tick o_bclk o_lrclk o_sdata o_frame_load o_dac_left_latch o_mclk o_underrun',[
  '沿用原PT8211/I2S音频位流、舍入和待播放缓冲；观察口不影响功能。',
  'o_frame_load在真实帧边界且有新PCM可加载时有效，含同拍旁路。',
  'PT8211模式下o_dac_left_latch在cnt_frame=512-C_FRAME_STEP且该播放帧有效时有效；这个沿使WS从高转低。',
  '板级只使用PT8211、C_FRAME_STEP=1；锁存是数字终点，不代表模拟输出无额外延迟。'])}
for name,(interface,behavior) in extra.items():
    m=copy.deepcopy(base);m.update(name=name,rtl_path=f'src/{name}.v',behavior=behavior)
    m['interfaces']['ports']=ports(interface);m['clock']['name']='i_clk';m['reset']['name']='i_rstn';contracts.append(m)
for m in contracts:
    name=m['name'];m['description']=m['behavior'][0]
    m['constraints']=['50MHz同一时钟域，异步低有效复位，顶层同步释放。','监测无音频控制反馈；一次事件窗口小于32位时间戳周期，默认1秒超时。']
    m['corner_cases']=['32键同时完成','计数回绕','候选取消','静音与慢起音','覆盖与超时并发','清零时仍按住键']
    m['verification_cases']=['独立时间差模型','逐分段确定值比较','真实ADC和PT8211 WS边沿关联','协议4全部分包边界及坏包恢复','Gowin时序与板上串口/听感']
    m['timing_diagrams']=[dict(id='onset',title='采集到数字起音',scenario='onset',description='概念时序，扫描等待与音频帧间隔被压缩；所有时间戳来自同一50MHz计数器。',wavejson={'signal':[
        {'name':'clk','wave':'p...........'},{'name':'ADC candidate','wave':'010.........'},
        {'name':'ADC confirm','wave':'0...10......'},{'name':'note commit','wave':'0....10.....'},
        {'name':'voice nonzero','wave':'0......10...'},{'name':'PCM valid','wave':'0.......10..'},
        {'name':'frame load','wave':'0........10.'},{'name':'DAC left latch','wave':'0.........10'}]})]
    path=ROOT/'spec'/f'{name}_contract.json';path.write_text(json.dumps({'modules':[m]},ensure_ascii=False,indent=2),encoding='utf-8')
    with (ROOT/'reports'/f'{name}_spec.log').open('w',encoding='utf-8') as out:
        r=subprocess.run([sys.executable,'-m','scripts.python.workflow.cli','write-spec','--spec',str(path),'--out-dir',str(ROOT),
            '--source',str(ROOT/m['rtl_path']),'--language','zh'],env={**os.environ,'PYTHONPATH':SKILL,'PYTHONUTF8':'1'},stdout=out,stderr=subprocess.STDOUT)
    if r.returncode:raise SystemExit('Specification failed: '+name)
print('PASS six source-checked latency specifications with WaveDrom')
