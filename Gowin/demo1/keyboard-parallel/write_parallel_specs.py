"""Render reviewed module contracts and timing sketches via the registered skill."""
from pathlib import Path
import copy
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
BASE = ROOT.parent / 'keyboard-studio/spec'
SKILL = 'C:/Users/asddddd28/.agents/skills/readable-verilog-generator'
base = json.loads((BASE / 'StudioOscMixer_contract.json').read_text(encoding='utf-8'))['modules'][0]

def ports(text):
    result = []
    for token in text.split():
        name, _, width = token.partition(':')
        width = int(width or 1) if not width or width.isdigit() else width
        result.append(dict(name=name, width=width, direction='input' if name.startswith('i_') else 'output',
                           description=name.replace('_', ' '), role='clock' if name in ('i_clk','i_axis_aclk') else 'reset' if name in ('i_rstn','i_axis_arstn') else 'data'))
    return result

contracts = []
behaviors = {
 'ParallelSynthEngine': [
  '32声部按7→0→1→2→3→4→5→6运行：调制包络、B相位、B波形、A相位FM、A波形、振幅包络、AM/混合、滤波/VCA。',
  '同步参数/状态RAM连续预取，经两级寄存及8槽任务FIFO发射；FIFO信用包含在途读请求。',
  '每个阶段最多发射及提交一个任务/拍，同类型核心轮流接受任务；返回保序，全部声部提交后切换阶段。',
  '振幅包络任务握手后按已发射标签消费事件；不能使用超前预取地址消费事件。',
  '默认1/2/3/1/1/1核心配置32声部385拍；外部PCM背压可延长busy，但不改变音频数值。'],
 'ParallelAudioSystem': [
  '将核心数量参数传递到ParallelSynthEngine；保持旧Studio协议及定点精度。',
  '板级50MHz/1024=48828.125Hz；引擎提前算完不会提前改变PT8211串行采样节拍。',
  '32声部混音后按活动包络数进行响度补偿、平滑主音量、限幅及16位舍入输出；左右声道复制。'],
 'ParallelAxisTop': [
  '完整ADC采集、迟滞判键、UART StudioControl、32声部参数/状态存储、多核合成和PT8211。',
  '六个C_*_CORES参数由core_counts.json在构建前确定，支持1..4；不支持运行时改变硬件实例数。',
  '默认Phase=1、Wave=2、Envelope=3、Modulation=1、Filter=1、VCA=1；波表更新广播到所有Wave副本。',
  '配置和波表接受窗口仍位于引擎空闲期；参数下次起音快照生效，音量实时平滑。']}
for new, old in [('ParallelSynthEngine','KeyboardSynthEngine'),('ParallelAudioSystem','KeyboardAudioSystem'),('ParallelAxisTop','KeyboardAxisTop')]:
    m = json.loads((BASE / f'{old}_contract.json').read_text(encoding='utf-8'))['modules'][0]
    m.update(name=new, rtl_path=f'src/{new}.v', description=behaviors[new][0], behavior=behaviors[new])
    contracts.append(m)

extra = {
 'AxisComputePool': ('i_axis_aclk i_axis_arstn i_s_axis_tdata:C_INPUT_WIDTH i_s_axis_tuser:C_USER_WIDTH i_s_axis_tvalid o_s_axis_tready o_m_axis_tdata:C_OUTPUT_WIDTH o_m_axis_tuser:C_USER_WIDTH o_m_axis_tvalid i_m_axis_tready i_wave_write i_wave_frame i_wave_address:11 i_wave_data:16', [
  'C_KIND=0..5依次实例化PhaseFm、WaveLookup+WaveSample、ADSR、StudioOscMixer、SVF、VCA；每池C_CORES=1..4。',
  '输入游标只在valid&&ready时前进；输出游标只在结果握手时前进；二者分别模C_CORES轮转。',
  '各lane保存独立信用和返回FIFO，按发射顺序回收；排在前面的lane未完成时保守阻塞，不能跨声部乱序提交。',
  '背压时保持结果及标签；复位清游标和核心有效位，取消全部旧任务。',
  'Wave池每lane含独立波表缓存；仅空闲时广播每个写采样，所有副本接收相同写地址和数据。',
  '合法输入/输出位宽依次为128/32、54/32、112/64、136/64、320/192、64/32；前四类user固定21位。']),
 'SynthTaskPrefetch': ('i_clk i_rstn i_begin i_run i_stage:3 i_epoch:16 o_read_voice:5 i_profile:512 i_state:384 o_valid i_ready o_data:352 o_user:21', [
  '调用方提供同步一拍RAM读；边沿N发起读，N+1寄存任务和深度乘法，N+2写入队列。',
  '默认C_QUEUE_BITS=3，8槽队列；cnt_reserved同时覆盖读流水和队列，接受一个下游任务才返还一个信用。',
  '352位任务按阶段打包，标签为16位epoch+5位voice；FM/AM深度乘调制包络后右移18位。',
  'i_begin清空队列有效性、读写游标及在途有效位；阶段/epoch在运行该阶段期间保持不变。',
  '每阶段固定发射C_VOICES个任务；board仅使用32；背压时输出队首保持不变。']),
 'ParallelVoiceChain': ('i_axis_aclk i_axis_arstn i_s_axis_tdata:352 i_s_axis_tuser:21 i_s_axis_tvalid o_s_axis_tready o_m_axis_tdata:192 o_m_axis_tuser:21 i_m_axis_tready o_m_axis_tvalid', [
  'SVF池与VCA池独立配置物理实例数量，通过AXI-Stream直接级联。',
  '滤波user携带原21位标签+18位包络+7位力度，共46位；VCA user携带21位标签+156位滤波状态与标志，共177位。',
  '最终返回192位音频与状态以及原21位标签；算术、量化和状态格式与旧AxisVoiceChain一致。',
  '每池保序并传递背压；复位取消所有在途上下文。'])}
for name, (interface, behavior) in extra.items():
    m = copy.deepcopy(base)
    m.update(name=name, rtl_path=f'src/{name}.v', description=behavior[0], behavior=behavior)
    m['interfaces']['ports'] = ports(interface)
    if name == 'SynthTaskPrefetch':
        m['clock']['name'] = 'i_clk'; m['reset']['name'] = 'i_rstn'
    contracts.append(m)

(ROOT / 'spec').mkdir(exist_ok=True)
for m in contracts:
    name = m['name']
    m['constraints'] = ['50MHz同一时钟域，低有效复位；板级复位同步释放。',
                        'C_*_CORES是综合期参数，1..4；任意配置需要独立验证资源和时序，只有默认配置有本板实现证据。',
                        '一个issue和一个retire端口；仍保留阶段屏障，不是任意连接的多发射计算图。']
    m['corner_cases'] = ['全满背压及同时接受/返回', '非2次幂核心数游标回绕', '处理中复位', 'wave副本写一致性', 'note-off保留旧参数']
    m['verification_cases'] = ['原引擎逐声部及PCM等值比较', '各池1/2/3/4核配置', '输入输出停顿及复位', '真实ADC/UART/PT8211引脚闭环', 'Gowin综合与50MHz时序']
    m['timing_diagrams'] = [dict(id='ordered', title='背压与有序返回', scenario='handshake',
        description='示意ready为0时保持队首；箭头不代表固定核心算术延迟。实际周期见各核心和阶段统计。',
        wavejson={'signal':[{'name':m['clock']['name'],'wave':'p.......'},
                            {'name':'valid','wave':'01...0..'}, {'name':'ready','wave':'0...10..'},
                            {'name':'task','wave':'x2...x..','data':['voice n']}, {'name':'accept','wave':'0...10..'}]})]
    path = ROOT / 'spec' / f'{name}_contract.json'
    path.write_text(json.dumps({'modules':[m]},ensure_ascii=False,indent=2),encoding='utf-8')
    with (ROOT / 'reports' / f'{name}_spec.log').open('w',encoding='utf-8') as out:
        # The skill source extractor misclassifies parameterized packed widths as
        # port names (C_INPUT_WIDTH etc.). Keep the reviewed contract truthful;
        # xsim/Gowin validate this generic interface, instead of adding fake ports.
        source_args = [] if name == 'AxisComputePool' else ['--source',str(ROOT / m['rtl_path'])]
        result = subprocess.run([sys.executable,'-m','scripts.python.workflow.cli','write-spec','--spec',str(path),
                '--out-dir',str(ROOT),*source_args,'--language','zh'],
                env={**os.environ,'PYTHONPATH':SKILL,'PYTHONUTF8':'1'},stdout=out,stderr=subprocess.STDOUT)
    if result.returncode:
        raise SystemExit('Specification failed: '+name)
print('PASS six module contracts and timing diagrams')
