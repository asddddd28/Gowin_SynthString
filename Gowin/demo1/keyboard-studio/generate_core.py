"""隔离改造：同步声部 RAM、双包络和可加权的两振荡器。"""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parent
OLD=ROOT.parent/'keyboard-performance'

store='''`timescale 1ns/1ps
// StudioVoiceStore: synchronous banks. Boot writes clear state before audio starts.
module StudioVoiceStore #(parameter C_VOICES=32)(
 input i_clk,input i_rstn,input i_cfg_write,input [4:0] i_cfg_voice,input [511:0] i_cfg_data,
 input [4:0] i_read_voice,output [511:0] o_profile,output [383:0] o_state,
 input i_write,input [4:0] i_write_voice,input [2:0] i_write_stage,input [191:0] i_write_data,
 input i_event_consume,input [4:0] i_event_voice
);
 reg [511:0] mem_profile[0:C_VOICES-1],reg_profile;
 reg [1:0] mem_event[0:C_VOICES-1],reg_event;
 integer idx;
 assign o_profile={reg_profile[511:171],reg_event,reg_profile[168:0]};
 always @(posedge i_clk) begin
  if(i_cfg_write&&!i_cfg_data[483])mem_profile[i_cfg_voice]<=i_cfg_data;
  reg_profile<=mem_profile[i_read_voice];reg_event<=mem_event[i_read_voice];
 end
 always @(posedge i_clk or negedge i_rstn) begin
  if(!i_rstn)begin for(idx=0;idx<C_VOICES;idx=idx+1)mem_event[idx]<=0;end
  else if(i_cfg_write)mem_event[i_cfg_voice]<=i_cfg_data[170:169];
  else if(i_event_consume)mem_event[i_event_voice]<=0;
 end
'''
# A field bank has one write port and one registered read, with no RAM reset.
for name,lo,width,stage,result_lo in [('phase_mod',0,32,0,0),('phase_carrier',32,32,2,0),('envelope',64,35,4,0),('filter',99,154,6,32),('wave_mod',253,32,1,0),('wave_carrier',285,32,3,0),('audio',317,32,5,0),('mod_envelope',349,35,7,0)]:
    store+=f''' reg [{width-1}:0] mem_{name}[0:C_VOICES-1],reg_{name};
 assign o_state[{lo+width-1}:{lo}]=reg_{name};
 always @(posedge i_clk)begin
  if(i_cfg_write&&i_cfg_data[482])mem_{name}[i_cfg_voice]<=0;
  else if(i_write&&i_write_stage==3'd{stage})mem_{name}[i_write_voice]<=i_write_data[{result_lo+width-1}:{result_lo}];
  reg_{name}<=mem_{name}[i_read_voice];
 end
'''
(ROOT/'src/StudioVoiceStore.v').write_text(store+'endmodule\n')

engine=(OLD/'src/KeyboardSynthEngine.v').read_text()
engine=engine.replace('[375:0]','[511:0]').replace('[348:0] wire_state','[383:0] wire_state').replace('SynthVoiceStore #','StudioVoiceStore #')
engine=engine.replace('.C_ADDR_WIDTH(6)', '.C_ADDR_WIDTH(5)')
engine=engine.replace('reg [2:0] reg_stage;','''reg [2:0] reg_stage;
 wire flag_run;
 reg [1:0] cnt_prefetch;
 reg [49:0] reg_fm_depth,reg_am_depth;
 wire flag_prefetched=cnt_prefetch==2;
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin cnt_prefetch<=0;reg_fm_depth<=0;reg_am_depth<=0;end
  else begin
   if(!flag_run||flag_issue||flag_last)cnt_prefetch<=0;
   else if(cnt_prefetch!=2)cnt_prefetch<=cnt_prefetch+1'b1;
   reg_fm_depth<=wire_profile[95:64]*wire_state[380:363];
   reg_am_depth<=wire_profile[227:196]*wire_state[380:363];
  end
 end''')
engine=engine.replace('flag_run&&(cnt_issue<C_VOICES)&&flag_input_ready','flag_run&&flag_prefetched&&(cnt_issue<C_VOICES)&&flag_input_ready')
for family in ['wave','phase','env','am','tail']:
    engine=engine.replace(f'flag_{family}_stage&&(cnt_issue<C_VOICES)',f'flag_{family}_stage&&flag_prefetched&&(cnt_issue<C_VOICES)')
engine=engine.replace('flag_run&&(reg_stage==4)','flag_run&&((reg_stage==4)||(reg_stage==7))')
engine=engine.replace('flag_env_stage&&flag_issue','flag_env_stage&&(reg_stage==4)&&flag_issue')
engine=engine.replace('reg_stage<=0;','reg_stage<=7;')
engine=engine.replace('else reg_stage<=reg_stage+1\'b1;','else if(reg_stage==7)reg_stage<=0;else reg_stage<=reg_stage+1\'b1;')
engine=engine.replace('wire_profile[95:64],wire_state[284:253]','reg_fm_depth[49:18],wire_state[284:253]')
engine=engine.replace('assign wire_env_input={2\'d0,wire_profile[170:169],wire_profile[168:96],wire_state[98:64]};',"assign wire_env_input=reg_stage==7?{2'd0,wire_profile[170:169],wire_profile[448:376],wire_state[383:349]}:{2'd0,wire_profile[170:169],wire_profile[168:96],wire_state[98:64]};")
engine=engine.replace('   4:begin flag_input_ready=', '   4,7:begin flag_input_ready=')
engine=engine.replace('if(flag_commit)reg_stages[reg_stage]<=1;','if(flag_commit&&reg_stage!=7)reg_stages[reg_stage]<=1;')
engine=engine.replace('if(flag_env_output_valid&&flag_env_stage&&!flag_fault', 'if(flag_env_output_valid&&flag_env_stage&&reg_stage==4&&!flag_fault')
engine=engine.replace('wire [103:0] wire_am_input','wire [135:0] wire_am_input').replace('AxisAmplitudeMod #','StudioOscMixer #')
engine=engine.replace("{6'd0,wire_profile[229:196],wire_state[284:253],wire_state[316:285]}","{5'd0,wire_profile[480:449],wire_profile[481],wire_profile[229:228],reg_am_depth[49:18],wire_state[284:253],wire_state[316:285]}")
start=engine.index(' always @(posedge i_clk or negedge i_rstn)begin');end=engine.index(' reg [5:0] cnt_issue',start)
block=engine[start:end];engine=engine[:start]+engine[end:];pos=engine.index(' assign flag_run=');engine=engine[:pos]+block+engine[pos:]
(ROOT/'src/KeyboardSynthEngine.v').write_text(engine)
system=(OLD/'src/KeyboardAudioSystem.v').read_text().replace('[375:0]','[511:0]')
(ROOT/'src/KeyboardAudioSystem.v').write_text(system)

bridge='''`timescale 1ns/1ps
// Studio patches are committed to program RAM; sounding snapshots live in the engine.
module KeyboardVoiceBridge(
 input i_clk,input i_rstn,input [31:0] i_pressed,input i_frame_done,
 input i_patch_valid,output o_patch_ready,input [4:0] i_patch_key,input [511:0] i_patch_data,
 input [223:0] i_velocity,
 output o_cfg_valid,input i_cfg_ready,output [4:0] o_cfg_voice,
 output [511:0] o_cfg_data,output o_initialized,output [31:0] o_delivered,output [31:0] o_events
);
 localparam [2:0] C_BOOT=0,C_BOOT_LOAD=1,C_BOOT_SEND=2,C_SCAN=3,C_LOAD=4,C_SEND=5,C_WAIT=6;
 reg [2:0] state_current,state_next;
 reg [4:0] cnt_key,reg_voice;
 reg [511:0] mem_profile[0:31],reg_read,reg_profile;
 reg [31:0] reg_delivered,cnt_events;
 reg flag_target,flag_initialized;
 wire flag_transfer=o_cfg_valid&&i_cfg_ready;
 wire flag_changed=i_pressed[cnt_key]!=reg_delivered[cnt_key];
 initial $readmemh("note_profiles.hex",mem_profile);
 assign o_patch_ready=state_current==C_SCAN&&!flag_changed;
 assign o_cfg_valid=state_current==C_BOOT_SEND||state_current==C_SEND;
 assign o_cfg_voice=reg_voice;assign o_cfg_data=reg_profile;
 assign o_initialized=flag_initialized;assign o_delivered=reg_delivered;assign o_events=cnt_events;
 always @(posedge i_clk)begin
  reg_read<=mem_profile[cnt_key];
  if(i_patch_valid&&o_patch_ready)mem_profile[i_patch_key]<=i_patch_data;
 end
 always @(*)begin
  state_next=state_current;
  case(state_current)
   C_BOOT:state_next=C_BOOT_LOAD;
   C_BOOT_LOAD:state_next=C_BOOT_SEND;
   C_BOOT_SEND:if(flag_transfer)state_next=cnt_key==31?C_SCAN:C_BOOT;
   C_SCAN:if(flag_changed)state_next=C_LOAD;
   C_LOAD:state_next=C_SEND;
   C_SEND:if(flag_transfer)state_next=C_WAIT;
   C_WAIT:if(i_frame_done)state_next=C_SCAN;
   default:state_next=C_BOOT;
  endcase
 end
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)state_current<=C_BOOT;else state_current<=state_next;
 end
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin cnt_key<=0;reg_voice<=0;reg_profile<=0;reg_delivered<=0;cnt_events<=0;flag_target<=0;flag_initialized<=0;end
  else case(state_current)
   C_BOOT_LOAD:begin reg_voice<=cnt_key;reg_profile<=reg_read;reg_profile[482]<=1;end
   C_BOOT_SEND:if(flag_transfer)begin cnt_key<=cnt_key+1'b1;if(cnt_key==31)flag_initialized<=1;end
   C_SCAN:if(!flag_changed)cnt_key<=cnt_key+1'b1;
   C_LOAD:begin
    reg_voice<=cnt_key;reg_profile<=reg_read;flag_target<=i_pressed[cnt_key];
    reg_profile[170:169]<=i_pressed[cnt_key]?2'd1:2'd2;
    reg_profile[367:361]<=i_velocity[cnt_key*7+:7];
    reg_profile[483]<=!i_pressed[cnt_key];
   end
   C_SEND:if(flag_transfer)begin reg_delivered[reg_voice]<=flag_target;cnt_events<=cnt_events+1'b1;end
   C_WAIT:if(i_frame_done)cnt_key<=cnt_key+1'b1;
   default:begin end
  endcase
 end
endmodule
'''
(ROOT/'src/KeyboardVoiceBridge.v').write_text(bridge)

mix='''`timescale 1ns/1ps
// Weighted oscillator mix or AM/ring. Q26 audio, Q16 oscillator gains.
module StudioOscMixer #(parameter C_ADDR_WIDTH=5)(
 input i_axis_aclk,input i_axis_arstn,input [135:0] i_s_axis_tdata,input [20:0] i_s_axis_tuser,
 input i_s_axis_tvalid,output o_s_axis_tready,output [63:0] o_m_axis_tdata,
 output [20:0] o_m_axis_tuser,output o_m_axis_tvalid,input i_m_axis_tready
);
 wire [135:0] data;wire launch;
 reg [6:0] valid;
 reg signed [31:0] modulator;
 reg [31:0] depth;
 reg signed [64:0] product;
 reg signed [31:0] factor;
 reg signed [63:0] carrier_product;
 reg signed [48:0] gain_carrier,gain_modulator;
 reg signed [49:0] sum;
 reg [31:0] result;
 reg [135:0] context_first,context_second,context_third,context_fourth;
 reg mix_delayed;
 wire signed [64:0] scaled=product>>>26;
 wire signed [64:0] distance=$signed({1'b0,context_second[95:64]})-scaled;
 wire signed [31:0] carrier_scaled=carrier_product>>>26;
 wire signed [49:0] output_scaled=sum>>>16;
 AxisFixedCore #(.C_INPUT_WIDTH(136),.C_OUTPUT_WIDTH(64),.C_USER_WIDTH(21),.C_ADDR_WIDTH(C_ADDR_WIDTH)) Queue_Inst(
 .i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(i_s_axis_tdata),.i_s_axis_tuser(i_s_axis_tuser),
 .i_s_axis_tvalid(i_s_axis_tvalid),.o_s_axis_tready(o_s_axis_tready),.o_m_axis_tdata(o_m_axis_tdata),
 .o_m_axis_tuser(o_m_axis_tuser),.o_m_axis_tvalid(o_m_axis_tvalid),.i_m_axis_tready(i_m_axis_tready),
 .o_core_valid(launch),.o_core_data(data),.i_core_valid(valid[6]),.i_core_data({32'd0,result}));
 always @(posedge i_axis_aclk or negedge i_axis_arstn)begin
  if(!i_axis_arstn)begin
   valid<=0;modulator<=0;depth<=0;product<=0;factor<=0;carrier_product<=0;
   gain_carrier<=0;gain_modulator<=0;sum<=0;result<=0;
   context_first<=0;context_second<=0;context_third<=0;context_fourth<=0;mix_delayed<=0;
  end else begin
   valid<={valid[5:0],launch};
   modulator<=$signed(data[63:32]);depth<=data[95:64];context_first<=data;
   product<=$signed({1'b0,depth})*modulator;context_second<=context_first;
   case(context_second[97:96])
    1:factor<=65'sd67108864-(distance>>>1);
    2:factor<=65'sd67108864-distance;
    default:factor<=32'sd67108864;
   endcase
   context_third<=context_second;
   carrier_product<=$signed(context_third[31:0])*factor;context_fourth<=context_third;
   gain_carrier<=carrier_scaled*$signed({1'b0,context_fourth[114:99]});
   gain_modulator<=$signed(context_fourth[63:32])*$signed({1'b0,context_fourth[130:115]});
   mix_delayed<=context_fourth[98];
   sum<=gain_carrier+(mix_delayed?gain_modulator:49'sd0);
   if(output_scaled>50'sd2147483647)result<=32'h7fffffff;
   else if(output_scaled< -50'sd2147483648)result<=32'h80000000;
   else result<=output_scaled[31:0];
  end
 end
endmodule
'''
(ROOT/'src/StudioOscMixer.v').write_text(mix)
sources=json.loads((OLD/'sources.json').read_text())
sources=[s.replace('/keyboard-performance/','/keyboard-studio/') for s in sources if not s.endswith('/SynthVoiceStore.v')]
for p in sorted((ROOT/'src').glob('*.v')):
    if p.as_posix() not in sources:sources.append(p.as_posix())
(ROOT/'sources.json').write_text(json.dumps(sources,indent=2))
project=(OLD/'keyboard_axis.gprj').read_text().replace('/keyboard-performance/','/keyboard-studio/')
start=project.index('<FileList>');end=project.index('</FileList>')
project=project[:start]+'<FileList>\n'+''.join(f'<File path="{s}" type="file.verilog" enable="1"/>\n' for s in sources)+'''<File path="src/keyboard_axis.cst" type="file.cst" enable="1"/>
<File path="src/keyboard_axis.sdc" type="file.sdc" enable="1"/>
<File path="D:/Projects/ai/Gowin/demo1/constraints/surge_svf_sample.gsc" type="file.gsc" enable="1"/>
'''+project[end:]
(ROOT/'keyboard_axis.gprj').write_text(project)
(ROOT/'build.tcl').write_text((OLD/'build.tcl').read_text().replace('/keyboard-performance/','/keyboard-studio/'))
print('Generated isolated Studio core')
