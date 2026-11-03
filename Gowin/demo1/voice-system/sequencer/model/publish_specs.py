"""Publish sequencer contracts without rewriting unrelated touch/voice contracts."""
from pathlib import Path
import copy,json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
TEMPLATE=json.loads((ROOT/'spec/SynthKeyboardSource_contract.json').read_text(encoding='utf-8'))['modules'][0]
WAVE={'signal':[{'name':'clk','wave':'p.........'}, {'name':'record','wave':'01....0...'},
 {'name':'bar_boundary','wave':'0..10.....'},{'name':'note_capture','wave':'0.10.10...'},
 {'name':'committed','wave':'0......1..'},{'name':'play_req','wave':'0......1..'},
 {'name':'ready','wave':'1......01.'},{'name':'completion','wave':'0........1'}]}
NEW={
 'SynthSequencer':('i_clk i_rstn i_enabled i_silent i_buttons:6 i_capture i_key:5 i_event:392 o_request:392 o_request_valid i_request_ready i_response:136 i_response_valid o_response_ready i_local_request i_opcode:8 i_argument:8 i_words:64 o_local_valid o_local_response:136 o_patch_lock:4 o_click o_accent o_recording o_bpm:9 o_status:32',[
 '50MHz 独立音乐时钟：每微秒累加 BPM×16，960PPQ，20..300BPM，4/4；AXI 背压不暂停时间。',
 '能力版本3沿用版本2按键：SW1开始/停止，SW2清空，SW3保存请求，SW4播放/暂停，SW5/6上一条/下一条；按键5ms消抖、仅取按下边沿。BPM通过App/0x42修改。存取请求尚未接入SD执行器，不能声称保存成功。',
 '只记录已被仲裁器接受的实体键盘/触摸拨弦 A4/A5；回放不会再次录入。首次完整小节决定循环长度，之后同长度叠录。',
 '首次录制以首个Note-On所在小节为起点。C_EARLY_WINDOW默认1，将四拍窗口前移约20ms：floor(BPM*8/25)个960PPQ tick；迭代减25求商，最多98拍，无DSP/除法器。BPM开始录制前稳定时取得偏移，单次录制期间冻结。C_EARLY_WINDOW=0关闭提前。启用时要求C_PPQ>=32。',
 '首音基于包含当前flag_tick的窗口相位，边界当拍音符属于新窗口。首音之前空小节不入长度；首次录制仅在含Note-On或持续按住的完整窗口更新提交边界，删除末尾纯空小节，中间休止和持续长音保留。已有叠录沿用原长度和时间基准。',
 '首次录制的窗口尚未完成时不发布录音；截断长音补Off。导入的已存音序不自动裁剪；该改动只影响随后新录的第一层。状态bit6表示已开始节拍但尚未收到首音，不改变现场音频延迟。',
 '五个1024×18独立地址同步RAM，事件90位；保留32条收尾空间，满时保留上次完整小节。初始化只清元数据，不清RAM。',
 '回放按音乐时间窗口遍历已提交事件；请求VALID保持到READY，等待Completion后才继续。帧延误不静默丢掉整段时间事件，但无无限队列或无限复音保证。',
 '回放NoteID高四位4，现场按键高位8。八个回放声部索引按A4回执更新；清空/暂停/循环只释放回放ID，不发全局panic。',
 '0x40能力、0x41状态、0x42控制、0x43..0x48事件快照、0x49库按键累计数；由上层CRC/重放缓存去重，同一个包不能重复翻转录制或追加事件。锁住提交/录制的音色槽，由Master拒绝覆盖。',
 '0x49依次返回SW3/SW5/SW6三个16位无符号计数（高16位零）及工作区32位代数。录制/收尾/租约/禁用期间不产生库操作；空循环长度时不产生保存请求，同时按前后键两者均不触发。计数仅表示输入事件，不能作为SD成功回执。',
 '快照租约只在录制/回放停止且回放Note-Off已完成时接受。导出模式复用原同步RAM读口；请求后两拍返回90位事件和32位代数，不增加事件RAM副本。',
 '导入要求空工作区。先0x46暂存低64位，再0x47提交高26位和顺序索引；只接受保留位零、起音索引等于自身、松键引用更早索引的事件。主机还必须验证松键引用的是Note-On。0x48验证数量/BPM/小节数/最大时间戳后一次性发布。中止和超时不发布部分事件。',
 '租约期间锁四槽，拒绝录放、清空和BPM更改；独立现场演奏和PCM不暂停。C_ARCHIVE_TIMEOUT默认为2147483647个50MHz时钟（约42.95秒），每个有效快照命令刷新；不得短于单个传输事务。',
 'SD文件系统、断电保存/自动恢复未实现；不能把这个RAM模块称为持久化音序器。']),
 'SynthMetronome':('i_clk i_rstn i_sample i_running i_click i_accent o_sample:16',[
 'i_click将DDS相位归零并设置重音/普通音幅度；i_sample每个PCM帧更新一次。',
 '24位相位累加，1320/880Hz近似方波、一阶平滑及线性衰减；峰值限制1536/1024，不占用合成声部、DSP或RAM。',
 'i_running无效立即归零；独立固定低音量监听，未绑定用户主音量。声音路由最终经PCM饱和混音。'])}
UPDATES={
 ROOT.parent/'voice-engine/rtl/AxisDxEnvelope.v':('',[
 '将原键位曲线乘常数329预先折入128×18 ROM（前64为指数曲线，后64为线性曲线）；执行期只保留与depth的乘法。ROM生成和32768组穷举由sequencer/model/keyscale_rom.py验证。7拍结果延迟、截断位置与正负号不变。']),
 ROOT.parent/'voice-engine/rtl/VoiceSynthEngine.v':('',[
'算子频率比乘积在state1寄存，state4再饱和并组装请求；固定频率直接保留state1的参数。复用原路由求和拍，不增加算子或整帧周期，位精确截断不变。',
 '命令发放许可flag_issue在校验和Completion可用之后独立寄存。当前sample_tick仍立即取消ready，已接受包立即清许可；新增1拍命令等待，不改音频帧计算状态或PCM采样周期。']),
 ROOT.parent/'voice-engine/rtl/AxisFmOperator.v':('',[
 '波表morph系数在state2读表期间提前限幅并寄存，state5插值只使用该17位系数。切断参数比较/mux到乘加路径；十拍延迟、插值精度、饱和范围和ready/valid语义保持不变。']),
 ROOT/'rtl/SynthCommandArbiter.v':('i_sequence_request:392 i_sequence_request_valid o_sequence_request_ready o_sequence_response:136 o_sequence_response_valid i_sequence_response_ready',[
 'C_SEQUENCE_ENABLE=1时新增回放请求源，启动完成后按键/主机/回放轮询；启动请求独占。现有单拍offer缓存保持392位命令直到下游接受，Completion按owner返回。默认0保持旧两源策略。']),
 ROOT/'rtl/SynthAxiMaster.v':('i_patch_lock:4',[
 'C_SEQUENCE_ENABLE启用时，接受请求边界检查A0..A3目标音色槽和A8共享波表；保留槽返回本地状态11，完全不发AXI写，不增加下游序号，不置全局fault。']),
 ROOT/'rtl/SynthPcmOutput.v':('i_click:16',[
 'C_METRONOME_ENABLE默认0。启用时在原Q26→16位舍入后以17位相加再饱和；固定1024拍PT8211帧率不变，旁路监测包含节拍。']),
 ROOT/'rtl/SynthSystemTop.v':('i_buttons:6 o_sequence_status:32 o_sequence_bpm:9',[
 'C_SEQUENCE_ENABLE默认0；启用后实例化SynthSequencer/SynthMetronome，真实键盘命令在ready/valid同时有效时采样。校准中静音停录/停播。',
 '本地0x40..0x49与原键盘/显示/滤波/触摸本地指令解码互斥；音序器是第三个运行期AXI命令来源。']),
 ROOT/'hdmi/rtl/SynthHdmiTop.v':('i_buttons:6',[
 '板级开启C_SEQUENCE_ENABLE，映射demo_test六个独立高有效按钮；保留50MHz音频、73.333MHz像素时钟。',
 '显示分析入口将16位PCM和valid一同寄存一级，切断PCM舍入/节拍相加到峰值和触发比较的组合链。声音采样周期不变，显示分析延后一个系统时钟。'])}


def publish(source,ports,behavior,fresh=False):
    base=source.parents[1];contract=base/f'spec/{source.stem}_contract.json';contract.parent.mkdir(exist_ok=True)
    module=copy.deepcopy(TEMPLATE) if fresh else json.loads(contract.read_text(encoding='utf-8'))['modules'][0]
    module.update(name=source.stem,rtl_path=f'rtl/{source.name}')
    if fresh:
        module['interfaces']['ports']=[];module['behavior']=[];module['description']=behavior[0]
        module['constraints']=['50MHz单时钟；异步低有效复位。事件RAM无清零复位。参数C_ADDRESS_BITS为6..10，C_PPQ为1..1024，C_US_CYCLES为1..64。C_EARLY_WINDOW=1时C_PPQ至少32；正式板级PPQ=960，BPM20..300。']
        module['corner_cases']=['不足一小节、边界同拍事件、截断长音、满缓存、背压清空、重复包、音色覆盖、暂停时现场键仍按住。']
        module['verification_cases']=['sequence_model.py参考行为；tb_sequencer边界/叠录/背压。','tb_sequencer_system真实ADC/UART/AXI/PT8211；UART重复包只翻转一次。']
    for text in behavior:
        if text not in module['behavior']:module['behavior'].append(text)
    known={p['name'] for p in module['interfaces']['ports']}
    for token in ports.split():
        name,_,width=token.partition(':')
        if name not in known:module['interfaces']['ports'].append(dict(name=name,direction='input' if name.startswith('i_') else 'output',width=int(width or 1),role='clock' if name=='i_clk' else 'reset' if name=='i_rstn' else 'data',description=name))
    module['timing_diagrams']=[dict(id='record-play',title='小节提交与回放握手',scenario='record-play',description='按键事件暂存，停止后保留完成的小节；回放命令稳定等待仲裁和回执。',wavejson=WAVE)]
    if source.stem=='VoiceSynthEngine':
        module['timing_diagrams']=[dict(id='ratio-pipeline',title='频率比乘法与饱和分拍',scenario='ratio-pipeline',description='当前参数行在state1被采样；state4使用寄存的乘积做饱和，state2发放完整请求。RAM可继续预取下一算子；固定频率保留原参数。',wavejson={'signal':[{'name':'clk','wave':'p......'},{'name':'state','wave':'=======','data':['1','4','2','3','3','3','1']},{'name':'core_row','wave':'==.....','data':['current','next']},{'name':'tuned_product','wave':'x=.....','data':['current product']},{'name':'request_increment','wave':'x==....','data':['fixed value','selected/saturated']},{'name':'operator_valid','wave':'0.10...'},{'name':'operator_ready','wave':'1.0....'},{'name':'result_valid','wave':'0....10'}]})]
        module['verification_cases'].append('dsp_regression.py及system_test.py：DX音色数值逐位比较、固定/比例频率、非DX波表/AM、AXI背压与饱和调度；分拍不增加帧周期。')
    if source.stem=='AxisFmOperator':
        module['timing_diagrams']=[dict(id='morph-coefficient',title='波表插值系数提前准备',scenario='morph-coefficient',description='state2读表并限幅morph，state3分数乘积、state4基值相加、state5双表morph；最终握手保持原来的十拍结果延迟。',wavejson={'signal':[{'name':'clk','wave':'p........'},{'name':'state','wave':'=========','data':['0','1','2','3','4','5','6','7','8']},{'name':'request_valid','wave':'10.......'},{'name':'morph_clamped','wave':'x..=.....','data':['0..65536']},{'name':'fraction_product','wave':'x...=....','data':['registered']},{'name':'interpolated_tables','wave':'x....=...','data':['low/high']},{'name':'wave','wave':'x.....=..','data':['morph result']}]})]
    if source.stem=='SynthSequencer':
        module['verification_cases'].append('tb_record_window及record_window.py：20ms窗口前/当拍/后、原始强拍前后，删除首尾空小节、中间休止/长音保留、四轮播放周期、所有20..300BPM偏移。旧版本复现768tick循环，新版本收紧为256tick。')
        module['timing_diagrams'].append(dict(id='early-window',title='首音归属提前窗口',scenario='early-window',description='T为强拍；提前窗口起点T-20ms。靠近强拍的首音归入新窗口，首音之前的空小节不计入循环。只保留完整且有演奏的首尾窗口。',wavejson={'signal':[{'name':'time','wave':'=.=.=.=.','data':['T-21ms','T-20ms','T','T+one bar-20ms']},{'name':'recording','wave':'1.......'},{'name':'waiting_first_note','wave':'1..0....'},{'name':'first_note','wave':'0..10...'},{'name':'metronome_accent','wave':'0...10..'},{'name':'complete_window','wave':'0.....10'}]}))
        module['verification_cases'].append('tb_sequence_archive：租约/超时、半包/乱序拒绝、原子发布、导出逐位一致；tb_sequencer_system通过真实UART导入后回放至PT8211。')
        module['timing_diagrams'].append(dict(id='archive-read',title='暂停期间复用事件RAM读口',scenario='archive-read',description='已取得导出租约。接受0x44索引后，下一拍同步RAM取数，再一拍返回；等待期间不置本地完成。',wavejson={'signal':[{'name':'clk','wave':'p.....'},{'name':'lease','wave':'1.....'},{'name':'request','wave':'010...'},{'name':'address','wave':'x.=...','data':['index']},{'name':'ram_data','wave':'x..=..','data':['event']},{'name':'response_valid','wave':'0...10'}]}))
    contract.write_text(json.dumps({'modules':[module]},ensure_ascii=False,indent=2),encoding='utf-8')
    env=os.environ.copy();env['PYTHONPATH']='C:/Users/asddddd28/.agents/skills/readable-verilog-generator';env['PYTHONIOENCODING']='utf-8'
    with (ROOT/f'reports/sequencer/{source.stem}-spec.log').open('w',encoding='utf-8') as log:
        subprocess.run([sys.executable,'-m','scripts.python.workflow.cli','write-spec','--spec',str(contract),'--out-dir',str(base),'--language','zh'],cwd=base,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
    print(source.stem,flush=True)


if __name__=='__main__':
    for name,(ports,behavior) in NEW.items():publish(ROOT/f'sequencer/rtl/{name}.v',ports,behavior,True)
    for source,(ports,behavior) in UPDATES.items():publish(source,ports,behavior)
