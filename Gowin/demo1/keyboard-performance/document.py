"""为新增接口写出显式合同；时序图通过既有技能渲染，不推断源码行为。"""
from pathlib import Path
import json,os,subprocess

ROOT=Path(__file__).resolve().parent
SKILL='C:/Users/asddddd28/.agents/skills/readable-verilog-generator'
PY=ROOT.parent/'desktop/.venv/Scripts/python.exe'
common=[('i_clk',1,'input','50MHz统一计算时钟'),('i_rstn',1,'input','低有效复位，异步置位同步释放')]
contracts={
 'KeyboardThresholds':(common+[('i_key',5,'input','零基键号'),('i_raw',12,'input','ADC结果'),('i_valid',1,'input','采样提交'),('o_pressed',32,'output','迟滞判键结果')],
  ['ROM由已保存的32键实测校准产生，包含方向、50%按下门限和35%释放门限。','同一键连续两个有效样本越过当前状态的门限才翻转；任何不满足样本清除该键资格。','复位清除按键及资格，保留只读门限。'],
  [{'name':'clk','wave':'p.......'},{'name':'sample_valid','wave':'0101010.'},{'name':'threshold_crossed','wave':'01......'},{'name':'pressed','wave':'0..1....'}]),
 'KeyboardVoiceBridge':(common+[('i_pressed',32,'input','目标键状态'),('i_frame_done',1,'input','PCM完成脉冲'),('o_cfg_valid',1,'output','完整配置有效'),('i_cfg_ready',1,'input','引擎接受配置'),('o_cfg_voice',5,'output','目标逻辑声部'),('o_cfg_data',376,'output','完整参数和单次事件'),('o_initialized',1,'output','全部初始配置已接受'),('o_delivered',32,'output','最后接受的键状态'),('o_events',32,'output','已接受事件计数')],
  ['启动依次初始化32个独立逻辑声部，全部接受后允许音频运行。','按键0至31对应MIDI48至79；此版按键对应逻辑声部，运算器仍共享。','配置保持到valid和ready同时有效；事件为重触发或释音。','运行中每次配置接受后等待该音频帧PCM完成，避免同声部单槽事件被提前覆盖。'],
  [{'name':'clk','wave':'p.......'},{'name':'key','wave':'01......'},{'name':'cfg_valid','wave':'0.1..0..'},{'name':'cfg_ready','wave':'0...10..'},{'name':'frame_done','wave':'0.....10'}]),
 'KeyboardSynthTelemetry':(common+[(n,w,'input',d) for n,w,d in [('i_frames',32,'音频帧计数'),('i_pressed',32,'物理键状态'),('i_delivered',32,'提交键状态'),('i_nonzero',32,'非零PCM计数'),('i_events',32,'事件计数'),('i_cycles',16,'合成周期'),('i_flags',8,'错误及测试标志'),('i_key',5,'最近键号'),('i_raw',12,'最近ADC结果')]]+[('o_uart_tx',1,'output','115200 8N1输出')],
  ['周期性锁存32字节原子状态快照，计算前30字节异或，最后字节0D。','头部为A5 5A 01 20，其余多字节整数小端。发送期间不覆盖快照。','等待UART完整停止位发送结束后再移出一个字节。异或仅作为调试校验，不是CRC。'],
  [{'name':'clk','wave':'p.......'},{'name':'snapshot','wave':'010.....'},{'name':'checksum','wave':'0.1.0...'},{'name':'uart_busy','wave':'0...1..0'}]),
 'KeyboardAxisTop':(common+[('i_adc_dout',1,'input','外部ADC串行数据'),('i_uart_rx',1,'input','调试命令输入'),('o_mux_sel',3,'output','模拟多路选择'),('o_mux_en',1,'output','多路器使能'),('o_adc_cs_n',1,'output','ADC片选'),('o_adc_sclk',1,'output','ADC时钟'),('o_adc_din',1,'output','ADC命令'),('o_uart_tx',1,'output','调试快照'),('HP_BCK',1,'output','PT8211位时钟'),('HP_WS',1,'output','PT8211声道选择'),('HP_DIN',1,'output','PT8211音频数据'),('PA_EN',1,'output','低有效功放使能')],
  ['50MHz单域，1024拍音频帧，采样率48828.125Hz，相位增量按此采样率计算。','真实ADC双转换扫描，门限判键，376位完整参数握手，32声部AXIS，16位PT8211。','配置初始化完成后才启动音频；功放延时打开，fault或overrun时关闭。','UART T产生有标记的一秒C4数字自测，P结束自测；不改物理按键状态。','固定正弦和ADSR音色；本次不实现App音色编辑、SD加载或任意任务图。'],
  [{'name':'clk','wave':'p.......'},{'name':'adc_valid','wave':'01010...'},{'name':'key_on','wave':'0..1....'},{'name':'cfg_transfer','wave':'0...10..'},{'name':'pcm','wave':'0.....10'}]),
 'tb_keyboard_audio':([('o_done',1,'output','所有引脚级检查完成')],['引脚级模拟ADC双转换及UART，独立解码PT8211左右声道并对照PCM舍入。','覆盖启动静音、三键跨行和弦、释音归零、单独数字自测及停止、遥测帧校验。'],
  [{'name':'clk','wave':'p.......'},{'name':'physical_keys','wave':'0.1..0..'},{'name':'dac_nonzero','wave':'0..1...0'}])
}
for name,(ports,behavior,waves) in contracts.items():
    bench=name.startswith('tb_')
    module={'name':name,'rtl_path':('sim/' if bench else 'src/')+name+'.v','description':behavior[0],
      'interfaces':{'ports':[{'name':n,'width':w,'direction':d,'description':s,'role':'clock' if n=='i_clk' else 'reset' if n=='i_rstn' else 'data'} for n,w,d,s in ports]},
      'clock':{'name':'clk' if bench else 'i_clk','edge':'posedge','period_ns':20},
      'reset':{'name':'rstn' if bench else 'i_rstn','active':'low','style':'asynchronous','values':'取消事件和任务，键状态及计数清零'},
      'behavior':behavior,'constraints':['固定32个逻辑声部；50MHz；板型31004；只用于本轮SRAM诊断验证。'],
      'corner_cases':['复位后按住键','门限附近抖动','事件遇到音频忙帧','多个键同时变化'],
      'verification_cases':['上电静音','跨行多键按下和释放','ADC至DAC引脚解码','配置反压保持','命令自测与物理键隔离'],
      'timing_diagrams':[{'id':'flow','title':'接口概念时序','scenario':'pipeline','description':'为事件顺序示意，间隔不按比例；实际周期见仿真与构建报告。','wavejson':{'signal':waves}}]}
    spec=ROOT/'spec'/(name+'_contract.json')
    spec.write_text(json.dumps({'modules':[module]},ensure_ascii=False,indent=2),encoding='utf-8')
    with (ROOT/'reports'/(name+'_spec.log')).open('w',encoding='utf-8') as log:
        r=subprocess.run([str(PY),'-m','scripts.python.workflow.cli','write-spec','--spec',str(spec),'--out-dir',str(ROOT),'--language','zh'],
            cwd=ROOT,env={**os.environ,'PYTHONPATH':SKILL,'PYTHONUTF8':'1'},stdout=log,stderr=subprocess.STDOUT)
    if r.returncode:raise SystemExit('Specification render failed: '+name)
print('Generated five contract and waveform bundles')
