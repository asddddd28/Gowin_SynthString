"""Preserve 0x180A and generate an isolated parameterized parallel integration."""
from pathlib import Path
import json
from configure_cores import PARAMETERS, read_counts
ROOT=Path(__file__).resolve().parent;BASE=ROOT.parent/'keyboard-studio'
core_parameters='parameter C_PHASE_CORES=1,parameter C_WAVE_CORES=2,parameter C_ENV_CORES=3,parameter C_MOD_CORES=1,parameter C_FILTER_CORES=1,parameter C_VCA_CORES=1'
forward=','.join(f'.{name}({name})' for name in ['C_PHASE_CORES','C_WAVE_CORES','C_ENV_CORES','C_MOD_CORES','C_FILTER_CORES','C_VCA_CORES'])
engine=(BASE/'src/KeyboardSynthEngine.v').read_text()
engine=engine.replace('module KeyboardSynthEngine #(parameter C_VOICES=8, parameter C_MIX_SHIFT=3)',f'module ParallelSynthEngine #({core_parameters},parameter C_VOICES=32,parameter C_MIX_SHIFT=5)')
start=engine.index(' reg [1:0] cnt_prefetch;');end=engine.index(' reg [5:0] cnt_issue',start)
engine=engine[:start]+''' wire flag_task_valid;
 wire [351:0] wire_task;
'''+engine[end:]
start=engine.index(' always @(posedge i_clk or negedge i_rstn)begin');end=engine.index(' assign flag_run=',start)
engine=engine[:start]+engine[end:]
engine=engine.replace(" assign wire_read_voice=(cnt_issue<C_VOICES)?cnt_issue[4:0]:5'd0;\n",'').replace(' assign wire_issue_tag={cnt_epoch,wire_read_voice};\n','')
engine=engine.replace('flag_run&&flag_prefetched&&(cnt_issue<C_VOICES)&&flag_input_ready','flag_run&&flag_task_valid&&flag_input_ready')
engine=engine.replace('&&flag_prefetched&&(cnt_issue<C_VOICES)','&&flag_task_valid')
engine=engine.replace(' assign wire_query={wire_profile[192:177],wire_profile[195:193],(reg_stage==1?wire_profile[173:171]:wire_profile[176:174]),(reg_stage==1?wire_state[31:0]:wire_state[63:32])};\n','')
engine=engine.replace('.i_event_voice(wire_read_voice)', '.i_event_voice(wire_issue_tag[4:0])')
start=engine.index(' AxisWaveLookup Lookup_Inst');end=engine.index(' KeyboardFrameMixer #',start)
engine=engine[:start]+''' SynthTaskPrefetch #(.C_VOICES(C_VOICES)) Prefetch_Inst(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_begin(flag_start||(flag_last&&reg_stage!=6)),.i_run(flag_run),.i_stage(reg_stage),.i_epoch(cnt_epoch),
 .o_read_voice(wire_read_voice),.i_profile(wire_profile),.i_state(wire_state),
 .o_valid(flag_task_valid),.i_ready(flag_input_ready),.o_data(wire_task),.o_user(wire_issue_tag));
'''+engine[end:]
engine=engine.replace('wire [159:0] wire_wave_input','wire [53:0] wire_wave_input')
engine=engine.replace('AxisPhaseFm #(.C_ADDR_WIDTH(5))','AxisComputePool #(.C_KIND(0),.C_CORES(C_PHASE_CORES),.C_INPUT_WIDTH(128),.C_OUTPUT_WIDTH(32),.C_ADDR_WIDTH(3))')
engine=engine.replace('AxisWaveSample #(.C_ADDR_WIDTH(5))','AxisComputePool #(.C_KIND(1),.C_CORES(C_WAVE_CORES),.C_INPUT_WIDTH(54),.C_OUTPUT_WIDTH(32),.C_ADDR_WIDTH(3))')
engine=engine.replace('AxisAdsr #(.C_ADDR_WIDTH(5))','AxisComputePool #(.C_KIND(2),.C_CORES(C_ENV_CORES),.C_INPUT_WIDTH(112),.C_OUTPUT_WIDTH(64),.C_ADDR_WIDTH(3))')
engine=engine.replace('StudioOscMixer #(.C_ADDR_WIDTH(5))','AxisComputePool #(.C_KIND(3),.C_CORES(C_MOD_CORES),.C_INPUT_WIDTH(136),.C_OUTPUT_WIDTH(64),.C_ADDR_WIDTH(4))')
engine=engine.replace('AxisVoiceChain #(.C_ADDR_WIDTH(5))','ParallelVoiceChain #(.C_ADDR_WIDTH(5),.C_FILTER_CORES(C_FILTER_CORES),.C_VCA_CORES(C_VCA_CORES))')
engine=engine.replace('.i_s_axis_tuser(wire_lookup_tag),.i_s_axis_tvalid(flag_lookup_valid)', '.i_s_axis_tuser(wire_issue_tag),.i_s_axis_tvalid(flag_wave_stage&&flag_task_valid)')
engine=engine.replace('flag_input_ready=flag_lookup_ready;', 'flag_input_ready=flag_wave_input_ready;')
for stage in ['phase','env','am']:
 needle=f'.i_m_axis_tready(flag_{stage}_stage));'
 engine=engine.replace(needle,f".i_m_axis_tready(flag_{stage}_stage),.i_wave_write(1'b0),.i_wave_frame(1'b0),.i_wave_address(11'd0),.i_wave_data(16'd0));")
engine=engine.replace('.i_m_axis_tready(flag_wave_stage));','.i_m_axis_tready(flag_wave_stage),.i_wave_write(flag_wave_write),.i_wave_frame(i_wave_frame),.i_wave_address(i_wave_address),.i_wave_data(i_wave_data));')
start=engine.index(' assign wire_phase_input=');end=engine.index(' // 每个阶段先发射',start)
engine=engine[:start]+''' assign wire_phase_input=wire_task[127:0];
 assign wire_wave_input=wire_task[53:0];
 assign wire_env_input=wire_task[111:0];
 assign wire_am_input=wire_task[135:0];
 assign wire_tail_input=wire_task;
'''+engine[end:]
for line in [' wire [53:0] wire_query;',' wire flag_lookup_ready,flag_lookup_valid;',' wire [159:0] wire_lookup_data;',' wire [20:0] wire_lookup_tag;']:
 engine=engine.replace(line+'\n','')
(ROOT/'src/ParallelSynthEngine.v').write_text(engine)

tail=(ROOT.parent/'rtl/axis/AxisVoiceChain.v').read_text().replace('module AxisVoiceChain','module ParallelVoiceChain')
tail=tail.replace('parameter C_ADDR_WIDTH = 6','parameter C_FILTER_CORES=1,parameter C_VCA_CORES=1,parameter C_ADDR_WIDTH = 5')
tail=tail.replace('AxisSvfSample #(\n', 'AxisComputePool #(.C_KIND(4),.C_CORES(C_FILTER_CORES),.C_INPUT_WIDTH(320),.C_OUTPUT_WIDTH(192),\n')
tail=tail.replace('AxisVoiceVca #(\n', 'AxisComputePool #(.C_KIND(5),.C_CORES(C_VCA_CORES),.C_INPUT_WIDTH(64),.C_OUTPUT_WIDTH(32),\n')
tail=tail.replace('.i_m_axis_tready(flag_filter_ready)',".i_wave_write(1'b0),.i_wave_frame(1'b0),.i_wave_address(11'd0),.i_wave_data(16'd0),\n\t\t.i_m_axis_tready(flag_filter_ready)")
tail=tail.replace('.i_m_axis_tready(i_m_axis_tready)',".i_wave_write(1'b0),.i_wave_frame(1'b0),.i_wave_address(11'd0),.i_wave_data(16'd0),\n\t\t.i_m_axis_tready(i_m_axis_tready)")
(ROOT/'src/ParallelVoiceChain.v').write_text(tail)
system=(BASE/'src/KeyboardAudioSystem.v').read_text().replace('module KeyboardAudioSystem #(',f'module ParallelAudioSystem #({core_parameters},')
system=system.replace('KeyboardSynthEngine #(',f'ParallelSynthEngine #({forward},')
(ROOT/'src/ParallelAudioSystem.v').write_text(system)
board_parameters=','.join(f'parameter {PARAMETERS[key]}={count}' for key,count in read_counts().items())
top=(BASE/'src/KeyboardAxisTop.v').read_text().replace('module KeyboardAxisTop #(\n',f'module ParallelAxisTop #(\n {board_parameters},\n')
top=top.replace('KeyboardAudioSystem #(',f'ParallelAudioSystem #({forward},')
(ROOT/'src/ParallelAxisTop.v').write_text(top)
sources=json.loads((BASE/'sources.json').read_text())+[p.as_posix() for p in sorted((ROOT/'src').glob('*.v'))]
(ROOT/'sources.json').write_text(json.dumps(sources,indent=2))
project=(BASE/'keyboard_axis.gprj').read_text();start=project.index('<FileList>');end=project.index('</FileList>')
project=project[:start]+'<FileList>\n'+''.join(f'<File path="{p}" type="file.verilog" enable="1"/>\n' for p in sources)+f'''<File path="{BASE.as_posix()}/src/keyboard_axis.cst" type="file.cst" enable="1"/>
<File path="{BASE.as_posix()}/src/keyboard_axis.sdc" type="file.sdc" enable="1"/>
<File path="{ROOT.parent.as_posix()}/constraints/surge_svf_sample.gsc" type="file.gsc" enable="1"/>
'''+project[end:]
(ROOT/'keyboard_parallel.gprj').write_text(project)
(ROOT/'build.tcl').write_text(f'''open_project {{{ROOT.as_posix()}/keyboard_parallel.gprj}}
set_option -top_module ParallelAxisTop
set_option -verilog_std v2001
set_option -use_cpu_as_gpio 1
run all
exit
''')
print('Prepared configurable pools, prefetch, wrappers and isolated Gowin project')
