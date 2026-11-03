"""Publish touch contracts and updated integration port documentation."""
from pathlib import Path
import copy,json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
template=json.loads((ROOT/'spec/SynthKeyboardSource_contract.json').read_text(encoding='utf-8'))['modules'][0]
new={
 'TouchPosition':('i_clk i_rstn i_raw:336 i_sequence:16 i_error:8 o_update o_touch o_x:10 o_y:10',[
 '双轴单触点重心；原始行电极5个映射X，列电极7个映射Y，归一化0..1023。',
 '检测扫描序号改变后逐电极提取、求权重、乘坐标并累加；再并行做两个10拍移位减法除法。没有组合除法器。',
 '扫描器原子发布336位数据，约毫秒更新；计算期间若序号变化立即放弃，完成时重新校验。',
 '两个轴均须有连续触摸簇，断裂多簇、缺轴、错误不产生有效触摸。输出位置仅在COMMIT提交，update为一拍。']),
 'SynthTouchInput':('i_clk i_rstn io_scl:2 io_sda:2 o_update:2 o_touch:2 o_x:20 o_y:20 o_error:16',[
 '两套原有MprScanner/I2cRegister/OpenCores I2C引擎分别采集两块MPR121，错误互不影响。',
 'SCL/SDA为开漏，遵循demo_test引脚与初始化；无需IRQ，软件串口轮询不参与实时采集。',
 '每块接一套TouchPosition；位置和更新脉冲都在50MHz系统域。']),
 'SynthTouchPerformance':('i_clk i_rstn i_next_mode i_silent i_update:2 i_touch:2 i_x:20 i_y:20 i_error:16 i_pressed:32 i_delivered:32 i_keys_idle o_pressed:32 o_mode:2 o_gain:18 o_pitch:32 o_cutoff:20 o_cutoff_active i_request i_opcode:8 i_argument:8 i_words:64 o_response_valid o_response:136',[
 '模式0强度、1音高、2Cutoff、3吉他。i_next_mode单拍递增一次；UART kind3 0x30..0x33提供能力、原子配置和状态。',
 '1kHz共享乘法器计算(X-Y)×范围；音高查256×18 exp2 ROM，三个目标用1/8一阶平滑，每毫秒更新一次。松手/过期40ms/错误恢复到中性。',
 '增益Q16的18位无符号数、音高Q26有符号频率增量、Cutoff20位有符号对数索引；配置上限100%、12半音、6oct。左板优先连续调制。',
 '四根横弦Y=128/384/640/896，滞回20，冷却12ms，每板独立运动历史。首次落指、方向设置更改、模式更改、断流不拨弦。',
 '每行8键取最右侧按住键，空行静音。每行一个pending目标；先清旧键，等待i_keys_idle且i_delivered==当前门控图，再重发，合并快速重复请求并计数。',
 '进入/离开吉他停止旧实体键；离开时已按键抑制到释放。连续调制模式之间切换不停止已按键。校准silent强制不发声。'])}
updates={
 ROOT/'rtl/SynthSystemTop.v':('i_touch_next io_touch_scl:2 io_touch_sda:2 o_touch_mode:2',['C_TOUCH_ENABLE默认0；HDMI顶层开启后，串口0x30..0x33分派触摸模块，物理按键先经TouchPerformance再交给KeyboardSource。']),
 ROOT/'rtl/SynthKeyboardSource.v':('o_idle',['o_idle在SCAN状态有效；拨弦调度必须同时确认o_delivered等于预期门控图，防止在途NoteOn尚未ACK就覆盖重触发。']),
 ROOT/'hdmi/rtl/SynthHdmiTop.v':('io_touch_scl:2 io_touch_sda:2',['启用双MPR触摸；DisplayControl长按脉冲切换模式，模式编号同步到HDMI页眉。']),
 ROOT/'hdmi/rtl/SynthDisplayControl.v':('o_touch_next',['摇杆按下800ms产生单次o_touch_next，保持不重复；松手重新解锁。短按确认改为松手发出，长按松手不会确认音色草稿。']),
 ROOT/'hdmi/rtl/SynthDisplayVideo.v':('i_touch_mode:2',['C_TOUCH_ENABLE开启时页眉显示TOUCH 1..4，2位模式经两拍同步用于显示。']),
 ROOT.parent/'voice-engine/rtl/VoiceSynthEngine.v':('i_touch_gain:18 i_touch_pitch:32',['C_TOUCH_ENABLE默认0保持旧行为。预先寄存主增益×触摸Q16增益并限制到UNITY，每帧锁存。state14叠加触摸与原调制矩阵音高，state15原乘法器执行；固定频率算子保持原频率。无新增音频FSM拍数。']),
 ROOT.parent/'voice-engine/rtl/AxisMasterLowpass.v':('i_touch_cutoff:20 i_touch_cutoff_active',['C_TOUCH_ENABLE默认0；帧边界锁存触摸偏移，AUDIO_WAVE寄存base+touch，AUDIO_TARGET再叠加LFO。触摸有效临时开启滤波，不修改已保存配置。']),
}
for name in ['AxiSynthEndpoint','AxiVoiceEndpoint','AxisSynthSystem']:
 updates[ROOT.parent/f'voice-engine/rtl/{name}.v']=('i_touch_gain:18 i_touch_pitch:32 i_touch_cutoff:20 i_touch_cutoff_active',['C_TOUCH_ENABLE默认0，透传注册的硬件触摸调制源到Voice和Lowpass；AXI继续管理基础参数和音色程序。开启触摸的AxiVoiceEndpoint报告ABI1.7，否则保持1.6。'])
env=os.environ.copy();env['PYTHONPATH']='C:/Users/asddddd28/.agents/skills/readable-verilog-generator';env['PYTHONIOENCODING']='utf-8'
def publish(source,ports,behavior,fresh=False):
 base=source.parents[1];path=base/f'spec/{source.stem}_contract.json';path.parent.mkdir(exist_ok=True)
 module=copy.deepcopy(template) if fresh else json.loads(path.read_text(encoding='utf-8'))['modules'][0]
 module.update(name=source.stem,rtl_path=f'rtl/{source.name}')
 if fresh:
  module['interfaces']['ports']=[];module['behavior']=behavior;module['description']=behavior[0]
  module['verification_cases']=['touch/model/run_simulations.py:位置/失联/四模式/右侧优先/重触发完成握手。','tb_touch_voice5120帧逐样本等效；tb_touch_filter4096帧；tb_touch_system真实UART/ADC/PT8211通路。']
  module['constraints']=['50MHz系统域；实时控制不依赖串口；ROM由touch_model.py生成。']
  module['corner_cases']=['复位、数据过期、触点跳变、重复包、在途按键命令、方向与模式切换、空行。']
 else:module['behavior']+=behavior
 existing={p['name'] for p in module['interfaces']['ports']}
 for item in ports.split():
  name,_,width=item.partition(':')
  if name not in existing:module['interfaces']['ports'].append(dict(name=name,direction='inout' if name.startswith('io_') else 'input' if name.startswith('i_') else 'output',width=int(width or 1),role='clock' if name=='i_clk' else 'reset' if name=='i_rstn' else 'data',description=name))
 module['timing_diagrams']=[dict(id='touch',title='触摸事件与调制提交',scenario='touch',description='触摸采集在系统域提交，调制每毫秒平滑；音频帧独立执行，NoteOff确认之后才重新起音。',wavejson={'signal':[{'name':'clk','wave':'p.........'},{'name':'position_update','wave':'010...10..'},{'name':'control_tick','wave':'0..10...10'},{'name':'audio_frame','wave':'0101010101'},{'name':'row_noteoff','wave':'0..10.....'},{'name':'keys_idle_ack','wave':'0.....10..'},{'name':'row_noteon','wave':'0......10.'}]})]
 path.write_text(json.dumps({'modules':[module]},ensure_ascii=False,indent=2),encoding='utf-8')
 log=ROOT/f'reports/touch-performance/{source.stem}-spec.log'
 with log.open('w',encoding='utf-8') as f:
  r=subprocess.run([sys.executable,'-m','scripts.python.workflow.cli','write-spec','--spec',str(path),'--out-dir',str(base),'--language','zh'],cwd=base,env=env,stdout=f,stderr=subprocess.STDOUT)
 if r.returncode:raise RuntimeError(log)
 print(source.stem,flush=True)
for name,(ports,behavior) in new.items():publish(ROOT/f'touch/rtl/{name}.v',ports,behavior,True)
for source,(ports,behavior) in updates.items():publish(source,ports,behavior)
