"""Isolated diagnostic build: preserve the audible keyboard-axis firmware and cores."""
from pathlib import Path
import json, math, shutil, hashlib, importlib.util, subprocess, sys
ROOT=Path(__file__).resolve().parent
OLD=ROOT.parent/'keyboard-axis'
for folder in ['src','sim','reports','spec','rtl/synth']:(ROOT/folder).mkdir(parents=True,exist_ok=True)
for name in ['model.py','document.py','run_sim.py','calibration.json','raw_rest.hex','raw_bottom.hex']:
    shutil.copy2(OLD/name,ROOT/name)
for p in (OLD/'src').glob('*'):shutil.copy2(p,ROOT/'src'/p.name)
shutil.copy2(OLD/'sim/tb_keyboard_audio.v',ROOT/'sim/tb_keyboard_audio.v')
spec=importlib.util.spec_from_file_location('base_model',ROOT/'model.py');model=importlib.util.module_from_spec(spec);spec.loader.exec_module(model);model.prepare()
# Independent arithmetic contract: fixed /32 mix, equal-energy 4/sqrt(N), master /8.
norm=[math.floor(4*65536/math.sqrt(max(1,n))) for n in range(33)]
assert norm[1]==262144 and all(norm[n]>=norm[n+1] for n in range(1,32))
assert max(n*norm[n]/65536/32 for n in range(1,33))<.708
(ROOT/'reports/loudness_model.json').write_text(json.dumps({'normalization_q16':norm,'limit_pcm24':0x700000,'gain_attack_shift':6,'gain_release_shift':12,'voices_include_release':True,'meaning':'Equal-energy compensation, not perceptual LUFS normalization'},indent=2))
engine=(ROOT.parent/'rtl/system/AxisSynthEngine.v').read_text()
engine=engine.replace('module AxisSynthEngine #','module KeyboardSynthEngine #')
engine=engine.replace('output [191:0] o_result_data //','output [31:0] o_active, output [6:0] o_stages,\n output [31:0] o_wave_peak, output [31:0] o_mod_peak, output [17:0] o_env_peak,\n output [191:0] o_result_data //')
monitor='''
 reg [31:0] reg_active,reg_wave_peak,reg_mod_peak;
 reg [17:0] reg_env_peak;
 reg [6:0] reg_stages;
 wire [31:0] enc_magnitude=reg_result[31] ? -reg_result[31:0] : reg_result[31:0];
 assign o_active=reg_active;assign o_stages=reg_stages;
 assign o_wave_peak=reg_wave_peak;assign o_mod_peak=reg_mod_peak;assign o_env_peak=reg_env_peak;
 // Observe accepted stage results only. Release envelopes remain active until idle.
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin reg_active<=0;reg_stages<=0;reg_wave_peak<=0;reg_mod_peak<=0;reg_env_peak<=0;end
  else if(flag_commit)begin
   reg_stages[reg_stage]<=1;
   if(reg_stage==4)begin
    reg_active[cnt_retire[4:0]]<=reg_result[34:32]!=0;
    if(reg_result[31:14]>reg_env_peak)reg_env_peak<=reg_result[31:14];
   end
   if(reg_stage==3&&enc_magnitude>reg_wave_peak)reg_wave_peak<=enc_magnitude;
   if(reg_stage==5&&enc_magnitude>reg_mod_peak)reg_mod_peak<=enc_magnitude;
  end
 end
'''
engine=engine.replace('\nendmodule',monitor+'\nendmodule')
(ROOT/'src/KeyboardSynthEngine.v').write_text(engine)
system=(ROOT.parent/'rtl/system/AxisSynthSystem.v').read_text().replace('module AxisSynthSystem #','module KeyboardAudioSystem #').replace('AxisSynthEngine #','KeyboardSynthEngine #')
system=system.replace('input i_clk,','input [3:0] i_volume,\n output [5:0] o_active_count,output [18:0] o_gain,\n output [23:0] o_input_peak,output [23:0] o_output_peak,output [31:0] o_clips,\n output [6:0] o_stages,output [31:0] o_wave_peak,output [31:0] o_mod_peak,output [17:0] o_env_peak,\n input i_clk,',1)
system=system.replace(' wire flag_audio_reset;',' wire flag_audio_reset;\n wire [31:0] enc_active;wire flag_mix;wire [23:0] enc_mix_left,enc_mix_right;')
system=system.replace('.o_pcm_valid(o_pcm_valid),','.o_pcm_valid(flag_mix),',1).replace('.o_pcm_left(o_pcm_left),','.o_pcm_left(enc_mix_left),',1).replace('.o_pcm_right(o_pcm_right),','.o_pcm_right(enc_mix_right),',1)
system=system.replace('.o_result_data(o_result_data));','.o_result_data(o_result_data),.o_active(enc_active),.o_stages(o_stages),.o_wave_peak(o_wave_peak),.o_mod_peak(o_mod_peak),.o_env_peak(o_env_peak));')
system=system.replace(' I2sTx #',' assign o_pcm_right=o_pcm_left;\n KeyboardLoudness Level_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_valid(flag_mix),.i_sample(enc_mix_left),.i_active(enc_active),.i_volume(i_volume),\n .o_valid(o_pcm_valid),.o_sample(o_pcm_left),.o_active_count(o_active_count),.o_gain(o_gain),.o_input_peak(o_input_peak),.o_output_peak(o_output_peak),.o_clips(o_clips));\n I2sTx #')
(ROOT/'src/KeyboardAudioSystem.v').write_text(system)
top=(ROOT/'src/KeyboardAxisTop.v').read_text().replace('AxisSynthSystem #','KeyboardAudioSystem #')
top=top.replace(' wire [7:0] enc_flags;',''' wire [7:0] enc_flags;
 reg [3:0] reg_volume;
 wire [5:0] enc_active_count;wire [18:0] enc_gain;
 wire [23:0] enc_input_peak,enc_output_peak;wire [31:0] enc_clips,enc_wave_peak,enc_mod_peak;
 wire [17:0] enc_env_peak;wire [6:0] enc_stages;
 always @(posedge i_clk or negedge flag_rstn)begin
  if(!flag_rstn)reg_volume<=6;
  else if(flag_rx_valid&&!flag_rx_error&&enc_rx>=8'h30&&enc_rx<=8'h38)reg_volume<=enc_rx[3:0];
 end''')
top=top.replace('.i_clk(i_clk),.i_rstn(flag_rstn),.i_run(flag_initialized),','.i_clk(i_clk),.i_rstn(flag_rstn),.i_run(flag_initialized),\n .i_volume(reg_volume),.o_active_count(enc_active_count),.o_gain(enc_gain),.o_input_peak(enc_input_peak),.o_output_peak(enc_output_peak),.o_clips(enc_clips),\n .o_stages(enc_stages),.o_wave_peak(enc_wave_peak),.o_mod_peak(enc_mod_peak),.o_env_peak(enc_env_peak),')
top=top.replace('.i_nonzero(cnt_nonzero),','.i_volume(reg_volume),.i_active_count(enc_active_count),.i_gain(enc_gain),.i_input_peak(enc_input_peak),.i_output_peak(enc_output_peak),.i_clips(enc_clips),\n .i_stages(enc_stages),.i_wave_peak(enc_wave_peak),.i_mod_peak(enc_mod_peak),.i_env_peak(enc_env_peak),\n .i_nonzero(cnt_nonzero),')
(ROOT/'src/KeyboardAxisTop.v').write_text(top)
tele=(ROOT/'src/KeyboardSynthTelemetry.v').read_text().replace('output o_uart_tx','input [3:0] i_volume,input [5:0] i_active_count,input [18:0] i_gain,\n input [23:0] i_input_peak,input [23:0] i_output_peak,input [31:0] i_clips,\n input [6:0] i_stages,input [31:0] i_wave_peak,input [31:0] i_mod_peak,input [17:0] i_env_peak,\n output o_uart_tx')
tele=tele.replace('[255:0]','[511:0]').replace('[4:0] cnt_byte','[5:0] cnt_byte').replace('cnt_byte==29','cnt_byte==61').replace('cnt_byte==31','cnt_byte==63').replace('[247:240]','[503:496]').replace('[239:232]','[495:488]').replace('[255:8]','[511:8]')
tele=tele.replace("reg_packet<={8'h0d,8'd0,4'd0,i_raw", "reg_packet<={8'h0d,8'd0,4'd0,i_volume,1'b0,i_stages,i_mod_peak,i_wave_peak,14'd0,i_env_peak,i_clips,8'd0,i_output_peak,8'd0,i_input_peak,13'd0,i_gain,2'd0,i_active_count,4'd0,i_volume,4'd0,i_raw")
tele=tele.replace("32'h20015aa5","32'h40025aa5")
(ROOT/'src/KeyboardSynthTelemetry.v').write_text(tele)
# New project references original arithmetic cores but only forked system wrappers.
sources=json.loads((ROOT/'sources.json').read_text())
sources=[p for p in sources if not p.endswith('/AxisSynthEngine.v') and not p.endswith('/AxisSynthSystem.v') and '/keyboard-performance/src/' not in p]
sources += [p.as_posix() for p in sorted((ROOT/'src').glob('*.v'))]
sources.append((ROOT/'src/KeyboardLoudness.v').as_posix()) if not any(p.endswith('/KeyboardLoudness.v') for p in sources) else None
(ROOT/'sources.json').write_text(json.dumps(sources,indent=2))
project=(ROOT/'keyboard_axis.gprj').read_text()
start=project.index('<FileList>');end=project.index('</FileList>')
project=project[:start]+'<FileList>\n'+''.join(f'<File path="{p}" type="file.verilog" enable="1"/>\n' for p in sources)+'<File path="src/keyboard_axis.cst" type="file.cst" enable="1"/>\n<File path="src/keyboard_axis.sdc" type="file.sdc" enable="1"/>\n'+project[end:]
(ROOT/'keyboard_axis.gprj').write_text(project)
project=project.replace('</FileList>','<File path="D:/Projects/ai/Gowin/demo1/constraints/surge_svf_sample.gsc" type="file.gsc" enable="1"/>\n</FileList>')
(ROOT/'keyboard_axis.gprj').write_text(project)
build=ROOT/'build.tcl';build.write_text('\n'.join(line for line in build.read_text().splitlines() if not line.startswith('add_file -type gsc'))+'\n')
(ROOT/'normalization_case.txt').write_text('\n'.join(f"   6'd{n}:enc_norm=19'd{norm[n]};" for n in range(33)))
print('Prepared isolated performance build and independent loudness contract')
subprocess.run([sys.executable,str(ROOT/'pipeline_repair.py')],check=True)
