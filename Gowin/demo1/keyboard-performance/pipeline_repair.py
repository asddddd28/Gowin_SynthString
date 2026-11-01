"""Apply evidence-backed observer/mixer register boundaries to this isolated fork."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parent
p=ROOT/'src/KeyboardSynthEngine.v';text=p.read_text().replace('SynthFrameMixer #','KeyboardFrameMixer #')
start=text.index(' reg [31:0] reg_active,reg_wave_peak,reg_mod_peak;')
text=text[:start]+'''
 reg [31:0] reg_active,reg_wave_peak,reg_mod_peak;
 reg [17:0] reg_env_peak;
 reg [6:0] reg_stages;
 reg [31:0] reg_wave_sample,reg_mod_sample,reg_wave_magnitude,reg_mod_magnitude;
 reg [1:0] flag_wave_observe,flag_mod_observe;
 assign o_active=reg_active;assign o_stages=reg_stages;
 assign o_wave_peak=reg_wave_peak;assign o_mod_peak=reg_mod_peak;assign o_env_peak=reg_env_peak;
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin
   reg_active<=0;reg_stages<=0;reg_wave_peak<=0;reg_mod_peak<=0;reg_env_peak<=0;
   reg_wave_sample<=0;reg_mod_sample<=0;reg_wave_magnitude<=0;reg_mod_magnitude<=0;
   flag_wave_observe<=0;flag_mod_observe<=0;
  end else begin
   flag_wave_observe<={flag_wave_observe[0],flag_wave_output_valid&&flag_wave_stage&&reg_stage==3&&!flag_fault};
   flag_mod_observe<={flag_mod_observe[0],flag_am_output_valid&&flag_am_stage&&!flag_fault};
   reg_wave_sample<=wire_wave_output;reg_mod_sample<=wire_am_output[31:0];
   reg_wave_magnitude<=reg_wave_sample[31]?-reg_wave_sample:reg_wave_sample;
   reg_mod_magnitude<=reg_mod_sample[31]?-reg_mod_sample:reg_mod_sample;
   if(flag_wave_observe[1]&&reg_wave_magnitude>reg_wave_peak)reg_wave_peak<=reg_wave_magnitude;
   if(flag_mod_observe[1]&&reg_mod_magnitude>reg_mod_peak)reg_mod_peak<=reg_mod_magnitude;
   if(flag_commit)reg_stages[reg_stage]<=1;
   if(flag_env_output_valid&&flag_env_stage&&!flag_fault&&!wire_env_output[35])begin
    reg_active[wire_env_tag[4:0]]<=wire_env_output[34:32]!=0;
    if(wire_env_output[31:14]>reg_env_peak)reg_env_peak<=wire_env_output[31:14];
   end
  end
 end
endmodule
'''
p.write_text(text)
sources=json.loads((ROOT/'sources.json').read_text());sources=[s for s in sources if not s.endswith('/SynthFrameMixer.v')]
new=(ROOT/'src/KeyboardFrameMixer.v').as_posix()
if new not in sources:sources.append(new)
(ROOT/'sources.json').write_text(json.dumps(sources,indent=2))
p=ROOT/'keyboard_axis.gprj';text=p.read_text()
if new not in text:text=text.replace('</FileList>',f'<File path="{new}" type="file.verilog" enable="1"/>\n</FileList>')
p.write_text(text)
print('Registered tail-to-mixer boundary; isolated observer inputs from result mux')
