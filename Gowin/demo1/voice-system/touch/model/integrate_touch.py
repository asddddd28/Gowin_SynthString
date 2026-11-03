"""Apply the reviewed, backed-up touch sidebands to the current hardware hierarchy."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];ENGINE=ROOT.parent/'voice-engine/rtl'
def edit(path,changes):
    s=path.read_text(encoding='utf-8')
    for old,new in changes:
        assert old in s,(path,old[:100]);s=s.replace(old,new)
    path.write_text(s,encoding='utf-8')
ports='    input [17:0] i_touch_gain,input [31:0] i_touch_pitch,input [19:0] i_touch_cutoff,input i_touch_cutoff_active,\n'
connections='        .i_touch_gain(i_touch_gain),.i_touch_pitch(i_touch_pitch),.i_touch_cutoff(i_touch_cutoff),.i_touch_cutoff_active(i_touch_cutoff_active),\n'
for name,clock in [('AxiSynthEndpoint','i_axi_aclk'),('AxiVoiceEndpoint','i_axi_aclk'),('AxisSynthSystem','i_axis_aclk')]:
    p=ENGINE/(name+'.v');s=p.read_text(encoding='utf-8');s=s.replace('parameter C_FX_ENABLE=1','parameter C_TOUCH_ENABLE=0,parameter C_FX_ENABLE=1')
    marker='input '+clock+',';assert marker in s;s=s.replace(marker,ports+marker,1)
    child='AxiVoiceEndpoint' if name=='AxiSynthEndpoint' else 'AxisSynthSystem' if name=='AxiVoiceEndpoint' else None
    if child:
        s=s.replace(child+' #(',child+' #(.C_TOUCH_ENABLE(C_TOUCH_ENABLE),',1)
        marker='.i_'+('axi' if child=='AxiVoiceEndpoint' else 'axis')+'_aclk('+clock+'),'
        assert marker in s;s=s.replace(marker,connections+marker,1)
    else:
        s=s.replace('VoiceSynthEngine Voice_Inst(','VoiceSynthEngine #(.C_TOUCH_ENABLE(C_TOUCH_ENABLE)) Voice_Inst(\n        .i_touch_gain(i_touch_gain),.i_touch_pitch(i_touch_pitch),')
        s=s.replace('AxisMasterLowpass Filter_Inst(','AxisMasterLowpass #(.C_TOUCH_ENABLE(C_TOUCH_ENABLE)) Filter_Inst(\n        .i_touch_cutoff(i_touch_cutoff),.i_touch_cutoff_active(i_touch_cutoff_active),')
    p.write_text(s,encoding='utf-8')
edit(ENGINE/'AxiVoiceEndpoint.v',[("32'h00010006","C_TOUCH_ENABLE ? 32'h00010007 : 32'h00010006")])
edit(ENGINE/'VoiceSynthEngine.v',[
 ('module VoiceSynthEngine(', 'module VoiceSynthEngine #(parameter C_TOUCH_ENABLE=0)(\n    input [17:0] i_touch_gain,input [31:0] i_touch_pitch,'),
 ('reg [31:0] reg_master;', '''reg [31:0] reg_master;
    reg [49:0] reg_touch_master_product;
    reg [31:0] reg_touch_master,reg_frame_master;
    reg signed [31:0] reg_frame_pitch;
    reg signed [32:0] reg_combined_pitch;
    wire signed [32:0] wire_combined_pitch=C_TOUCH_ENABLE ? reg_combined_pitch : $signed({wire_modulation[31],wire_modulation[31:0]});
    // Free-running registered gain preparation stays outside the audio FSM.
    always @(posedge i_axis_aclk or negedge i_axis_arstn)begin
        if(!i_axis_arstn)begin reg_touch_master_product<=50'd4398046511104;reg_touch_master<=67108864;end
        else begin
            reg_touch_master_product<=reg_master*i_touch_gain;
            reg_touch_master<=reg_touch_master_product[49:16]>67108864 ? 32'd67108864 : reg_touch_master_product[47:16];
        end
    end'''),
 ('$signed(wire_modulation[31:0]) > 32\'sd67108864',"wire_combined_pitch > 33'sd67108864"),
 ('$signed(wire_modulation[31:0]) < -32\'sd67108864',"wire_combined_pitch < -33'sd67108864"),
 (': $signed(wire_modulation[31:0]));',': $signed(wire_combined_pitch[31:0]));'),
 ('reg_pitch_product<=0;','reg_frame_master<=67108864;reg_frame_pitch<=0;reg_combined_pitch<=0;reg_pitch_product<=0;'),
 ('0: if (i_sample_tick) begin\n', '0: if (i_sample_tick) begin\n                    reg_frame_master<=C_TOUCH_ENABLE ? reg_touch_master : reg_master;reg_frame_pitch<=C_TOUCH_ENABLE ? i_touch_pitch : 32\'d0;\n'),
 ('$signed(reg_master);','$signed(C_TOUCH_ENABLE ? reg_frame_master : reg_master);'),
 ('14: begin\n','14: begin\n                    reg_combined_pitch<=$signed({wire_modulation[31],wire_modulation[31:0]})+$signed({reg_frame_pitch[31],reg_frame_pitch});\n')
])
edit(ENGINE/'AxisMasterLowpass.v',[
 ('module AxisMasterLowpass(', 'module AxisMasterLowpass #(parameter C_TOUCH_ENABLE=0)(\n    input [19:0] i_touch_cutoff,input i_touch_cutoff_active,'),
 ('reg [17:0] reg_frame_base,reg_frame_depth;', 'reg [17:0] reg_frame_base,reg_frame_depth;\n    reg signed [19:0] reg_frame_touch;\n    reg signed [31:0] reg_adjusted_base;'),
 ('reg_frame_flags<=0;reg_frame_base<=177296;', 'reg_frame_touch<=0;reg_adjusted_base<=177296;reg_frame_flags<=0;reg_frame_base<=177296;'),
 ('reg_frame_flags<=reg_flags;reg_frame_base<=reg_base;', "reg_frame_touch<=C_TOUCH_ENABLE ? i_touch_cutoff : 20'd0;reg_frame_flags<=reg_flags | ((C_TOUCH_ENABLE && i_touch_cutoff_active) ? 3'd1 : 3'd0);reg_frame_base<=reg_base;"),
 ('AUDIO_DEPTH:reg_depth_product',"AUDIO_WAVE:reg_adjusted_base<=$signed({14'd0,reg_frame_base})+reg_frame_touch;\n            AUDIO_DEPTH:reg_depth_product"),
 ("AUDIO_TARGET:reg_target_sum<=$signed({14'd0,reg_frame_base})+", "AUDIO_TARGET:reg_target_sum<=reg_adjusted_base+")
])
edit(ROOT/'rtl/SynthKeyboardSource.v',[
 ('input i_enabled,input [31:0] i_pressed,','input i_enabled,input [31:0] i_pressed,output o_idle,'),
 ('assign o_velocity_key=reg_key;','assign o_idle=reg_state==SCAN;\n    assign o_velocity_key=reg_key;')
])
edit(ROOT/'rtl/SynthSystemTop.v',[
 ('parameter C_DISPLAY_ENABLE=0)', 'parameter C_DISPLAY_ENABLE=0,parameter C_TOUCH_ENABLE=0)'),
 ('input i_clk,','input i_touch_next,inout [1:0] io_touch_scl,inout [1:0] io_touch_sda,output [1:0] o_touch_mode,\n    input i_clk,'),
 ('wire flag_keyboard_select=', '''wire flag_touch_select=C_TOUCH_ENABLE && wire_local_opcode>=8'h30 && wire_local_opcode<=8'h33;
    wire flag_touch_response,flag_keys_idle;
    wire [135:0] wire_touch_response;
    wire [31:0] wire_performance_keys,wire_touch_pitch;
    wire [17:0] wire_touch_gain;
    wire [19:0] wire_touch_cutoff;
    wire flag_touch_cutoff_active;
    wire flag_keyboard_select='''),
 ('assign flag_local_response=flag_keyboard_select ?', 'assign flag_local_response=flag_touch_select ? flag_touch_response : flag_keyboard_select ?'),
 ('assign wire_local_response=flag_keyboard_select ?', 'assign wire_local_response=flag_touch_select ? wire_touch_response : flag_keyboard_select ?'),
 ('.i_pressed(wire_pressed),','.i_pressed(wire_performance_keys),.o_idle(flag_keys_idle),'),
 ('AxiSynthEndpoint #(', 'AxiSynthEndpoint #(.C_TOUCH_ENABLE(C_TOUCH_ENABLE),'),
 ('.i_axi_aclk(i_clk),', '.i_touch_gain(wire_touch_gain),.i_touch_pitch(wire_touch_pitch),.i_touch_cutoff(wire_touch_cutoff),.i_touch_cutoff_active(flag_touch_cutoff_active),\n        .i_axi_aclk(i_clk),'),
 ('flag_local_request && !flag_display_select && !flag_keyboard_select', 'flag_local_request && !flag_display_select && !flag_keyboard_select && !flag_touch_select'),
 ('endmodule', '''    generate if(C_TOUCH_ENABLE)begin:TouchDomain
        wire [1:0] wire_update,wire_contact;
        wire [19:0] wire_x,wire_y;
        wire [15:0] wire_error;
        SynthTouchInput Input_Inst(.i_clk(i_clk),.i_rstn(flag_rstn),.io_scl(io_touch_scl),.io_sda(io_touch_sda),
            .o_update(wire_update),.o_touch(wire_contact),.o_x(wire_x),.o_y(wire_y),.o_error(wire_error));
        SynthTouchPerformance Performance_Inst(.i_clk(i_clk),.i_rstn(flag_rstn),.i_next_mode(i_touch_next),.i_silent(o_display_calibrating),
            .i_update(wire_update),.i_touch(wire_contact),.i_x(wire_x),.i_y(wire_y),.i_error(wire_error),
            .i_pressed(wire_pressed),.i_delivered(wire_delivered),.i_keys_idle(flag_keys_idle),.o_pressed(wire_performance_keys),.o_mode(o_touch_mode),
            .o_gain(wire_touch_gain),.o_pitch(wire_touch_pitch),.o_cutoff(wire_touch_cutoff),.o_cutoff_active(flag_touch_cutoff_active),
            .i_request(flag_local_request && flag_touch_select),.i_opcode(wire_local_opcode),.i_argument(wire_local_argument),.i_words(wire_local_words),
            .o_response_valid(flag_touch_response),.o_response(wire_touch_response));
    end else begin:NoTouchDomain
        assign wire_performance_keys=wire_pressed;assign wire_touch_gain=18'd65536;assign wire_touch_pitch=0;assign wire_touch_cutoff=0;
        assign flag_touch_cutoff_active=0;assign flag_touch_response=0;assign wire_touch_response=0;assign o_touch_mode=0;
    end endgenerate
endmodule''')
])
edit(ROOT/'hdmi/rtl/SynthHdmiTop.v',[
 ('input i_clk,input i_rstn,','inout [1:0] io_touch_scl,inout [1:0] io_touch_sda,\n    input i_clk,input i_rstn,'),
 ('wire flag_host_live,flag_calibrating;', 'wire flag_host_live,flag_calibrating,flag_touch_next;\n    wire [1:0] wire_touch_mode;'),
 ('#(.C_DISPLAY_ENABLE(1))','#(.C_DISPLAY_ENABLE(1),.C_TOUCH_ENABLE(1))'),
 ('.i_clk(i_clk),.i_rstn(i_rstn),.i_adc_dout', '.i_touch_next(flag_touch_next),.io_touch_scl(io_touch_scl),.io_touch_sda(io_touch_sda),.o_touch_mode(wire_touch_mode),\n        .i_clk(i_clk),.i_rstn(i_rstn),.i_adc_dout'),
 ('.o_page(wire_page),.o_focus()', '.o_touch_next(flag_touch_next),.o_page(wire_page),.o_focus()'),
 ('SynthDisplayVideo Video_Inst(', 'SynthDisplayVideo #(.C_TOUCH_ENABLE(1)) Video_Inst(.i_touch_mode(wire_touch_mode),')
])
edit(ROOT/'hdmi/rtl/SynthDisplayControl.v',[
 ('module SynthDisplayControl(', 'module SynthDisplayControl #(parameter C_LONG_CYCLES=40000000)('),
 ('output o_host_live', 'output o_touch_next,output o_host_live'),
 ('wire flag_confirm=flag_joy_armed[2] && !reg_joy_filter[4];', '''reg flag_switch_tracking,flag_switch_long;
    reg [25:0] cnt_switch;
    reg flag_confirm,flag_touch_next_o;
    assign o_touch_next=flag_touch_next_o;
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin flag_switch_tracking<=0;flag_switch_long<=0;cnt_switch<=0;flag_confirm<=0;flag_touch_next_o<=0;end
        else begin
            flag_confirm<=0;flag_touch_next_o<=0;
            if(flag_joy_armed[2] && !reg_joy_filter[4])begin flag_switch_tracking<=1;flag_switch_long<=0;cnt_switch<=0;end
            else if(flag_switch_tracking)begin
                if(reg_joy_filter[4])begin flag_confirm<=!flag_switch_long;flag_switch_tracking<=0;cnt_switch<=0;end
                else if(!flag_switch_long)begin
                    if(cnt_switch==C_LONG_CYCLES-1)begin flag_switch_long<=1;flag_touch_next_o<=1;end
                    else cnt_switch<=cnt_switch+1'b1;
                end
            end
        end
    end''')
])
# A small independent status field reuses the existing glyph ROM, not a new framebuffer.
edit(ROOT/'hdmi/rtl/SynthDisplayVideo.v',[
 ('module SynthDisplayVideo(', 'module SynthDisplayVideo #(parameter C_TOUCH_ENABLE=0)(\n    input [1:0] i_touch_mode,'),
 ('reg [7:0] reg_text,reg_character;', 'reg [7:0] reg_text,reg_character;\n    reg [1:0] reg_touch_meta,reg_touch_sync;\n    always @(posedge i_clk or negedge i_rstn)begin if(!i_rstn)begin reg_touch_meta<=0;reg_touch_sync<=0;end else begin reg_touch_meta<=C_TOUCH_ENABLE ? i_touch_mode : 2\'d0;reg_touch_sync<=reg_touch_meta;end end'),
 ('else if(reg_cell_meta[10:0]>=128)', 'else if(reg_cell_meta[10:0]==1120) dec_character=8\'d49+{6\'d0,reg_touch_sync};\n        else if(reg_cell_meta[10:0]>=128)')
])
sources=ROOT/'sources.f';s=sources.read_text(encoding='utf-8')
add=list((ROOT/'touch/rtl').glob('*.v'))+[ROOT.parents[1]/'demo_test/diagnostics/touchpad_guitar/src/MprScanner.v',ROOT.parents[1]/'demo_test/diagnostics/touchpad/src/I2cRegister.v']+[ROOT.parents[1]/f'demo_test/diagnostics/touchpad/vendor/{name}' for name in ['i2c_master_byte_ctrl.v','i2c_master_bit_ctrl.v']]
sources.write_text(s+'\n'+'\n'.join(p.as_posix() for p in add)+'\n',encoding='utf-8')
pins=(ROOT.parents[1]/'demo_test/diagnostics/hardware_lab/src/hardware.cst').read_text(encoding='utf-8').splitlines()
pins=[x.replace('io_scl','io_touch_scl').replace('io_sda','io_touch_sda') for x in pins if '"io_scl' in x or '"io_sda' in x]
# Only the HDMI board top has pad pins; non-HDMI diagnostic tops remain unchanged.
edit(ROOT/'hdmi/model/build_hdmi.py', [('pins += "\\n" + "\\n".join(display_pins)', 'pins += "\\n" + "\\n".join(display_pins)\npins += "\\n" + (ROOT / "touch.cst").read_text(encoding="utf-8")')])
(ROOT/'hdmi/touch.cst').write_text('\n'.join(pins)+'\n')
print('Integrated touch sources, DSP sidebands, physical guitar gate and joystick long press')
