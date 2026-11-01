"""从已验证的单功能工程生成独立综合副本；原工程保持可回退。"""
from pathlib import Path
root=Path(__file__).resolve().parent

def replace(text,old,new):
    if old not in text:raise ValueError('Expected source fragment missing: '+old[:80])
    return text.replace(old,new)
def save(name,text):(root/'src'/name).write_text(text,encoding='utf8')

for source,target in [('encoder/src/EncoderDebug.v','HardwareEncoders'),('joystick/src/JoystickDebug.v','HardwareJoystick')]:
    text=(root.parent/source).read_text(encoding='utf8')
    text=text.replace(Path(source).stem,target)
    text=replace(text,'output o_uart_tx','input i_tx_ready, output o_tx_valid, output [7:0] o_tx_data')
    text=text.replace('EncoderUartTx #(.C_BAUD_CYCLES(C_BAUD_CYCLES))','TelemetryByte')
    text=replace(text,'.o_tx(o_uart_tx)', '.i_ready(i_tx_ready), .o_valid(o_tx_valid), .o_data(o_tx_data)')
    save(target+'.v',text)

text=(root.parent/'touchpad_guitar/src/TouchpadGuitar.v').read_text(encoding='utf8').replace('TouchpadGuitar','HardwareTouchpad')
text=replace(text,'output o_uart_tx','input i_tx_ready, output o_tx_valid, output [7:0] o_tx_data, output o_priority')
text=replace(text,'reg uart_start;', 'reg uart_start;\nreg event_frame;\nassign o_priority=event_frame;')
text=replace(text,'EncoderUartTx #(.C_BAUD_CYCLES(C_BAUD)) uart', 'TelemetryByte uart')
text=replace(text,'.o_tx(o_uart_tx)', '.i_ready(i_tx_ready),.o_valid(o_tx_valid),.o_data(o_tx_data)')
text=replace(text,'report_count<=0; report_side<=1;', 'event_frame<=0; report_count<=0; report_side<=1;')
text=replace(text,'active<=1; short_frame<=1; side<=choose_right;', 'event_frame<=1; active<=1; short_frame<=1; side<=choose_right;')
text=replace(text,'active<=1; short_frame<=1; heartbeat_pending<=0;', 'event_frame<=0; active<=1; short_frame<=1; heartbeat_pending<=0;')
text=replace(text,'active<=1; short_frame<=0; heartbeat_pending<=1;', 'event_frame<=0; active<=1; short_frame<=0; heartbeat_pending<=1;')
save('HardwareTouchpad.v',text)

text=(root.parent/'keyboard_games/src/KeyboardTelemetry.v').read_text(encoding='utf8').replace('KeyboardTelemetry','HardwareKeyboardTelemetry')
text=replace(text,'output o_tx','input i_tx_ready, output o_tx_valid, output [7:0] o_tx_data, output o_priority')
text=replace(text,"assign o_tx=state_current==ST_SEND ? reg_shift[0] : 1'b1;", "assign o_tx_valid=state_current==ST_SEND;\nassign o_tx_data=reg_shift[8:1];\nassign o_priority=flag_response && !flag_game_response;")
text=replace(text,'cnt_baud==C_UART_CYCLES-1 && cnt_bit==9', 'i_tx_ready')
start=text.index('   ST_SEND:begin\n    if(cnt_baud==C_UART_CYCLES-1)')
end=text.index('   default:begin end',start)
text=text[:start]+'''   ST_SEND:begin
    if(i_tx_ready)begin cnt_char<=cnt_char+1'b1; end
   end
'''+text[end:]
save('HardwareKeyboardTelemetry.v',text)

text=(root.parent/'keyboard_games/src/KeyboardGames.v').read_text(encoding='utf8').replace('KeyboardGames','HardwareKeyboard')
text=replace(text,'parameter integer C_UART_CYCLES=434,parameter integer C_FRAME_CYCLES=1000000', 'parameter integer C_UART_CYCLES=434,parameter integer C_FRAME_CYCLES=1000000, parameter integer C_REPORT_CYCLES=5000000')
text=replace(text,'output o_adc_din,output o_uart_tx,output o_rgb', 'output o_adc_din,output o_rgb,input i_tx_ready,output o_tx_valid,output [7:0] o_tx_data,output o_priority')
text=replace(text,'assign flag_sample_transfer=flag_sample_valid && flag_sample_ready;', 'assign flag_sample_transfer=flag_sample_valid;\nwire [4:0] report_key;\nwire [11:0] report_raw;\nwire report_valid;')
text=replace(text,'.i_ready(flag_sample_ready)',".i_ready(1'b1)")
text=text.replace('KeyController KeyState_Inst', 'HardwareKeyController KeyState_Inst').replace('KeyLightEffects Effects_Inst','HardwareKeyLightEffects Effects_Inst')
text=replace(text,'KeyboardTelemetry #', 'HardwareKeyboardTelemetry #')
text=replace(text,'.i_key(enc_key),.i_raw(enc_raw),.i_valid(flag_sample_valid),.o_ready(flag_sample_ready)', '.i_key(report_key),.i_raw(report_raw),.i_valid(report_valid),.o_ready(flag_sample_ready)')
text=replace(text,'.o_tx(o_uart_tx)', '.i_tx_ready(i_tx_ready),.o_tx_valid(o_tx_valid),.o_tx_data(o_tx_data),.o_priority(o_priority)')
text=replace(text,'endmodule', '''KeyboardSnapshot #(.C_REPORT_CYCLES(C_REPORT_CYCLES)) Snapshot_Inst(
 .i_clk(i_clk),.i_rstn(flag_reset_n),.i_key(enc_key),.i_raw(enc_raw),.i_valid(flag_sample_valid),
 .i_ready(flag_sample_ready),.o_key(report_key),.o_raw(report_raw),.o_valid(report_valid));
endmodule''')
save('HardwareKeyboard.v',text)

text=(root.parent/'keyboard_games/src/KeyController.v').read_text(encoding='utf8').replace('KeyController','HardwareKeyController')
text=text.replace('i_command[7:4]>4', '(i_command[7:4]>4 && i_command[7:4]!=6)')
save('HardwareKeyController.v',text)
text=(root.parent/'keyboard_games/src/KeyLightEffects.v').read_text(encoding='utf8').replace('KeyLightEffects','HardwareKeyLightEffects')
text=replace(text,'reg [3:0] reg_mode_snapshot;', 'reg [3:0] reg_mode_snapshot;\nreg [6:0] flow_motion,flow_motion_snapshot;\nreg [7:0] flow_hue,flow_hue_snapshot;')
text=replace(text,'reg_age<=63;reg_age_snapshot<=63;', 'flow_motion<=0;flow_motion_snapshot<=0;flow_hue<=0;flow_hue_snapshot<=0;\n  reg_age<=63;reg_age_snapshot<=63;')
text=replace(text,'reg_age_snapshot<=reg_age;', "flow_motion<=flow_motion+1'b1;flow_motion_snapshot<=flow_motion;\n   flow_hue<=flow_hue==191 ? 0 : flow_hue+1'b1;flow_hue_snapshot<=flow_hue;\n   reg_age_snapshot<=reg_age;")
text=replace(text,'  default:begin enc_weight=0; end', '''  6:begin
   enc_distance=(flow_motion_snapshot[6:4]+8-enc_col)%8;
   case(enc_distance)
    0:enc_weight=32;1:enc_weight=16;2:enc_weight=4;default:enc_weight=0;
   endcase
  end
  default:begin enc_weight=0; end''')
text=replace(text,' enc_phase=reg_mode_snapshot==1 ?', ' enc_phase=reg_mode_snapshot==6 ? flow_hue_snapshot : reg_mode_snapshot==1 ?')
save('HardwareKeyLightEffects.v',text)

# 合并已验证的物理约束，重复定义必须完全一致，物理焊盘不得复用。
constraints=[];definitions={};locations={}
for source in ('keyboard_games/keyboard.cst','encoder/src/encoder.cst','joystick/src/joystick.cst','touchpad_guitar/src/touchpad.cst'):
    for line in (root.parent/source).read_text(encoding='utf8').splitlines():
        if not line.strip():continue
        token=line.split('"')[1];kind=line.split()[0];key=(kind,token)
        if key in definitions:
            assert definitions[key]==line,(key,definitions[key],line)
            continue
        definitions[key]=line;constraints.append(line)
        if kind=='IO_LOC':
            pin=line.split()[-1].strip(';')
            assert pin not in locations,(pin,token,locations.get(pin))
            locations[pin]=token
save('hardware.cst','\n'.join(constraints)+'\n')
save('hardware.sdc','create_clock -name clk -period 20.000 [get_ports {i_clk}]\n')
print(f'Prepared isolated sources; {len(locations)} unique pins')
