"""Add passive observation taps to an isolated copy of the parallel top."""
from pathlib import Path
import json,shutil
ROOT=Path(__file__).resolve().parent
PARALLEL=ROOT.parent/'keyboard-parallel'
STUDIO=ROOT.parent/'keyboard-studio'
for resource in (PARALLEL/'rtl').rglob('*'):
    if resource.is_file() and resource.suffix in ('.hex','.mem'):
        target=ROOT/resource.relative_to(PARALLEL)
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(resource,target)

keys=(STUDIO/'src/KeyboardThresholds.v').read_text(encoding='utf-8').replace('KeyboardThresholds','LatencyKeyThresholds')
keys=keys.replace('output [31:0] o_pressed','output o_candidate,output o_confirm,output o_cancel,\n output [31:0] o_pressed')
keys=keys.replace(' assign o_pressed=reg_pressed_o;', ''' assign o_pressed=reg_pressed_o;
 assign o_candidate=i_valid&&!reg_pressed_o[i_key]&&flag_crossed&&!reg_qualify[i_key];
 assign o_confirm=i_valid&&!reg_pressed_o[i_key]&&flag_crossed&&reg_qualify[i_key];
 assign o_cancel=i_valid&&!reg_pressed_o[i_key]&&!flag_crossed&&reg_qualify[i_key];''')
(ROOT/'src/LatencyKeyThresholds.v').write_text(keys,encoding='utf-8')

serial=(ROOT.parent/'rtl/audio/I2sTx.v').read_text(encoding='utf-8').replace('I2sTx','LatencyI2sTx')
serial=serial.replace('output o_mclk, output o_underrun','output o_frame_load,output o_dac_left_latch,\n\toutput o_mclk, output o_underrun')
serial=serial.replace('reg flag_pending, flag_started;','reg flag_pending, flag_started, flag_play_valid;')
serial=serial.replace('assign o_sample_tick = flag_frame_start;', '''assign o_sample_tick = flag_frame_start;
    assign o_frame_load = i_rstn && flag_frame_start && (i_sample_valid || flag_pending);
    assign o_dac_left_latch = i_rstn && C_PT8211 && flag_play_valid && (cnt_frame == 512-C_FRAME_STEP);''')
serial=serial.replace('flag_pending <= 0; flag_started <= 0;', 'flag_pending <= 0; flag_started <= 0; flag_play_valid <= 0;')
serial=serial.replace('flag_started <= 1;', 'flag_started <= 1;\n                flag_play_valid <= i_sample_valid || flag_pending;')
(ROOT/'src/LatencyI2sTx.v').write_text(serial,encoding='utf-8')

audio=(PARALLEL/'src/ParallelAudioSystem.v').read_text(encoding='utf-8').replace('module ParallelAudioSystem','module LatencyAudioSystem')
audio=audio.replace(' output o_sample_tick,',' output o_frame_load,output o_dac_left_latch,output o_pcm_nonzero,\n output o_sample_tick,')
audio=audio.replace(' I2sTx #',''' wire [15:0] wire_monitor_pcm;
 PcmRounder MonitorRound_Inst(.i_sample(o_pcm_left),.o_sample(wire_monitor_pcm));
 assign o_pcm_nonzero=wire_monitor_pcm!=0;
 LatencyI2sTx #''')
audio=audio.replace('.o_sample_tick(o_sample_tick),.o_bclk', '.o_frame_load(o_frame_load),.o_dac_left_latch(o_dac_left_latch),.o_sample_tick(o_sample_tick),.o_bclk')
(ROOT/'src/LatencyAudioSystem.v').write_text(audio,encoding='utf-8')

telemetry=(STUDIO/'src/KeyboardSynthTelemetry.v').read_text(encoding='utf-8').replace('KeyboardSynthTelemetry','LatencySynthTelemetry')
telemetry=telemetry.replace(' output o_uart_tx',' input [879:0] i_latency,\n output o_uart_tx')
telemetry=telemetry.replace('[639:0] reg_packet','[1535:0] reg_packet').replace('[6:0] cnt_byte','[7:0] cnt_byte')
telemetry=telemetry.replace('cnt_byte==77','cnt_byte==189').replace('cnt_byte==79','cnt_byte==191')
telemetry=telemetry.replace("{8'h0d,8'd0,16'd0,32'h0000001f", "{8'h0d,8'd0,i_latency,16'd0,16'd0,32'h0000003f")
telemetry=telemetry.replace("32'h50035aa5", "32'hc0045aa5")
telemetry=telemetry.replace('[631:624]','[1527:1520]').replace('[623:616]','[1519:1512]').replace('[639:8]','[1535:8]')
(ROOT/'src/LatencySynthTelemetry.v').write_text(telemetry,encoding='utf-8')

top=(PARALLEL/'src/ParallelAxisTop.v').read_text(encoding='utf-8').replace('ParallelAxisTop','LatencyAxisTop')
top=top.replace(' parameter C_SETTLE_CYCLES', ' parameter C_LATENCY_TIMEOUT=50000000,parameter C_LATENCY_BUDGET=500000,\n parameter C_SETTLE_CYCLES')
top=top.replace(' KeyboardThresholds Keys_Inst', ' wire flag_candidate,flag_confirm,flag_cancel;\n LatencyKeyThresholds Keys_Inst')
top=top.replace('.o_pressed(enc_pressed));','.o_pressed(enc_pressed),.o_candidate(flag_candidate),.o_confirm(flag_confirm),.o_cancel(flag_cancel));')
top=top.replace(' ParallelAudioSystem #',' wire flag_result,flag_frame_load,flag_dac_latch,flag_pcm_nonzero;\n wire [4:0] enc_result_key;wire [191:0] enc_result;\n LatencyAudioSystem #')
top=top.replace('.o_result_valid(),.o_result_voice(),.o_result_data(),.o_sample_tick(),', '''.o_result_valid(flag_result),.o_result_voice(enc_result_key),.o_result_data(enc_result),.o_sample_tick(),
 .o_frame_load(flag_frame_load),.o_dac_left_latch(flag_dac_latch),.o_pcm_nonzero(flag_pcm_nonzero),''')
top=top.replace(' KeyboardSynthTelemetry #',''' wire [879:0] enc_latency;
 LatencySupervisor #(.C_TIMEOUT_CYCLES(C_LATENCY_TIMEOUT),.C_BUDGET_CYCLES(C_LATENCY_BUDGET)) Monitor_Inst(
 .i_clk(i_clk),.i_rstn(flag_rstn),.i_clear(flag_ascii&&enc_ascii==8'h4c),.i_initialized(flag_initialized),
 .i_sample_valid(flag_sample),.i_sample_key(enc_key),.i_candidate(flag_candidate),.i_confirm(flag_confirm),.i_cancel(flag_cancel),
 .i_physical(enc_pressed),.i_effective(enc_effective),
 .i_commit(flag_cfg_valid&&flag_cfg_ready&&flag_initialized&&enc_cfg_data[170:169]==2'd1),.i_commit_key(enc_cfg_voice),
 .i_result_valid(flag_result),.i_result_key(enc_result_key),.i_result_sample(enc_result[31:0]),
 .i_pcm_valid(flag_pcm),.i_pcm_nonzero(flag_pcm_nonzero),.i_frame_load(flag_frame_load),.i_dac_left_latch(flag_dac_latch),.o_payload(enc_latency));
 LatencySynthTelemetry #''')
top=top.replace('.o_uart_tx(o_uart_tx));','.i_latency(enc_latency),.o_uart_tx(o_uart_tx));')
(ROOT/'src/LatencyAxisTop.v').write_text(top,encoding='utf-8')
sources=json.loads((PARALLEL/'sources.json').read_text())+[p.as_posix() for p in sorted((ROOT/'src').glob('*.v'))]
(ROOT/'sources.json').write_text(json.dumps(sources,indent=2),encoding='utf-8')
project=(PARALLEL/'keyboard_parallel.gprj').read_text(encoding='utf-8')
start=project.index('<FileList>');end=project.index('</FileList>')
constraint=project[project.index('<File path="'+STUDIO.as_posix()+'/src/keyboard_axis.cst'):end]
project=project[:start]+'<FileList>\n'+''.join(f'<File path="{p}" type="file.verilog" enable="1"/>\n' for p in sources)+constraint+project[end:]
(ROOT/'keyboard_latency.gprj').write_text(project,encoding='utf-8')
(ROOT/'build.tcl').write_text(f'''open_project {{{ROOT.as_posix()}/keyboard_latency.gprj}}
set_option -top_module LatencyAxisTop
set_option -verilog_std v2001
set_option -use_cpu_as_gpio 1
run all
exit
''',encoding='utf-8')
print('PASS isolated observation taps, extended telemetry and Gowin project')
