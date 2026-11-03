"""Apply the reviewed board-local extension to the saved pre-change sources."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'reports/unified-studio/before'

def edit(relative, replacements):
    text = (BASE/relative).read_text(encoding='utf-8')
    for old, new in replacements:
        assert old in text, (relative, old[:100])
        text = text.replace(old, new, 1)
    (ROOT.parents[1]/relative).write_text(text, encoding='utf-8')

edit('demo1/voice-system/rtl/SynthKeyboardSource.v', [
('output [31:0] o_events,output o_fault', '''output [31:0] o_events,output o_fault,
    input i_config_write,input [4:0] i_config_key,input [47:0] i_config_data,output [47:0] o_config_data,
    output o_event_start,output o_event_finish,output o_event_failed,output [4:0] o_event_key,output [31:0] o_event_frame'''),
('reg [31:0] mem_phase[0:31];\n    reg [31:0] reg_phase;', '''(* syn_ramstyle = "block_ram" *) reg [47:0] mem_mapping[0:31];
    reg [47:0] reg_mapping,reg_config_read;'''),
('initial $readmemh("rom/keyboard_phase.hex",mem_phase);', '''initial $readmemh("rom/keyboard_mapping.hex",mem_mapping);
    assign o_config_data=reg_config_read;
    assign o_event_start=reg_state==PREPARE && flag_press;
    assign o_event_finish=reg_state==WAIT_REPLY && i_response_valid && flag_press;
    assign o_event_failed=i_response[135:128]!=0 || i_response[71:64]!=0;
    assign o_event_key=reg_key;
    assign o_event_frame=i_response[63:32];'''),
('if (reg_state==SCAN) reg_phase<=mem_phase[reg_key];', '''if (reg_state==SCAN) reg_mapping<=mem_mapping[reg_key];
        if (i_config_write) mem_mapping[i_config_key]<=i_config_data;
        else reg_config_read<=mem_mapping[i_config_key];'''),
('reg_request[327:320]<=8\'ha4;', 'reg_request[335:328]<={6\'d0,reg_mapping[33:32]};\n                        reg_request[327:320]<=8\'ha4;'),
('reg_request[63:32]<=reg_phase;', 'reg_request[63:32]<=reg_mapping[31:0];'),
('// Fixed velocity until the keybed measures strike speed; retain true MIDI pitch for DX key scaling.\n                        reg_request[159:128]<=32\'h80003200 | (32\'d48+{27\'d0,reg_key});', '''// Host mapping is latched before dispatch; Note-Off keeps the original identity.
                        reg_request[159:128]<={1'b1,17'd0,reg_mapping[47:41],reg_mapping[40:34]};'''),
])
edit('demo1/voice-system/rtl/SynthUartControl.v', [
('output [31:0] o_bad_packets,output [31:0] o_replayed', '''output [31:0] o_bad_packets,output [31:0] o_replayed,
    output o_local_request,output [7:0] o_local_opcode,output [7:0] o_local_argument,output [63:0] o_local_words,
    input i_local_valid,input [135:0] i_local_response'''),
('localparam DECODE=7,CLASSIFY=8;', 'localparam DECODE=7,CLASSIFY=8,LOCAL_SEND=9,LOCAL_WAIT=10;'),
('assign o_request=reg_request;', '''assign o_local_request=reg_state==LOCAL_SEND;
    assign o_local_opcode=wire_opcode;
    assign o_local_argument=wire_argument;
    assign o_local_words=reg_packet[143:80];
    assign o_request=reg_request;'''),
('else next_state=SEND;', 'else next_state=wire_kind==3 ? LOCAL_SEND : SEND;\n            LOCAL_SEND: next_state=LOCAL_WAIT;\n            LOCAL_WAIT: if(i_local_valid) next_state=PREPARE_TX;'),
('flag_bad_request<=wire_kind>2 ||', 'flag_bad_request<=wire_kind>3 ||\n                        (wire_kind==3 && !(&reg_zero_words[9:2])) ||'),
('WAIT_REPLY: if (i_response_valid) begin\n                    reg_tx_image', '''LOCAL_WAIT: if(i_local_valid) begin
                    reg_tx_image[191:64]<=i_local_response[127:0];reg_tx_image[199:192]<=i_local_response[135:128];
                end
                WAIT_REPLY: if (i_response_valid) begin
                    reg_tx_image'''),
])
edit('demo1/voice-system/rtl/SynthPcmOutput.v', [
('output o_bclk,output o_ws,output o_data,output [31:0] o_frames,output [31:0] o_underruns', 'output o_bclk,output o_ws,output o_data,output [31:0] o_frames,output [31:0] o_underruns,\n    output o_sample_valid,output [15:0] o_sample'),
('assign o_ready=cnt_frame==0;', 'assign o_ready=cnt_frame==0;\n    assign o_sample_valid=o_ready && i_valid;\n    assign o_sample=wire_pcm_left;'),
])
edit('demo1/voice-engine/rtl/VoiceSynthEngine.v', [
('reg_signature<=wire_signature; reg_cached_address<=wire_address; reg_cached<=reg_checked_completion;', '''reg_signature<=wire_signature; reg_cached_address<=wire_address; reg_cached<=reg_checked_completion;
                    // The next rendered frame is the first affected by this accepted Note-On.
                    // Cache the same tag so a retransmission cannot move the observation boundary.
                    if(reg_checked_status==0 && i_s_axis_tdest==8'ha4) begin
                        reg_completion[63:32]<=cnt_frame+32'd1;
                        reg_cached[63:32]<=cnt_frame+32'd1;
                    end'''),
])
edit('demo1/voice-system/rtl/SynthSystemTop.v', [
('wire flag_pcm_valid,flag_pcm_ready;', '''wire flag_pcm_valid,flag_pcm_ready;
    wire flag_local_request,flag_local_response,flag_key_write,flag_monitor_sample;
    wire flag_key_start,flag_key_finish,flag_key_failed;
    wire [7:0] wire_local_opcode,wire_local_argument;
    wire [63:0] wire_local_words;
    wire [135:0] wire_local_response;
    wire [4:0] wire_config_key,wire_event_key;
    wire [47:0] wire_config_data,wire_config_read;
    wire [15:0] wire_monitor_sample;
    wire [31:0] wire_event_frame;'''),
('.o_fault(flag_key_fault)', '''.o_fault(flag_key_fault),
        .i_config_write(flag_key_write),.i_config_key(wire_config_key),.i_config_data(wire_config_data),.o_config_data(wire_config_read),
        .o_event_start(flag_key_start),.o_event_finish(flag_key_finish),.o_event_failed(flag_key_failed),.o_event_key(wire_event_key),.o_event_frame(wire_event_frame)'''),
('.o_replayed(wire_replayed)', '''.o_replayed(wire_replayed),
        .o_local_request(flag_local_request),.o_local_opcode(wire_local_opcode),.o_local_argument(wire_local_argument),.o_local_words(wire_local_words),
        .i_local_valid(flag_local_response),.i_local_response(wire_local_response)'''),
('.o_underruns(wire_underruns)', '.o_underruns(wire_underruns),.o_sample_valid(flag_monitor_sample),.o_sample(wire_monitor_sample)'),
('endmodule', '''    SynthStudioMonitor Monitor_Inst(
        .i_clk(i_clk),.i_rstn(flag_rstn),
        .i_request(flag_local_request),.i_opcode(wire_local_opcode),.i_argument(wire_local_argument),.i_words(wire_local_words),
        .o_response_valid(flag_local_response),.o_response(wire_local_response),
        .o_key_write(flag_key_write),.o_key_index(wire_config_key),.o_key_data(wire_config_data),.i_key_data(wire_config_read),
        .i_pcm_valid(flag_monitor_sample),.i_pcm_sample(wire_monitor_sample),.i_pcm_frame(wire_pcm_frame),
        .i_key_start(flag_key_start),.i_key_finish(flag_key_finish),.i_key_failed(flag_key_failed),.i_event_key(wire_event_key),.i_event_frame(wire_event_frame)
    );
endmodule'''),
])
from studio_monitor_model import key_row, verify
verify()
(ROOT/'rom/keyboard_mapping.hex').write_text(''.join(f'{key_row(0,48+k,100):012x}\n' for k in range(32)),encoding='ascii')
sources=ROOT/'sources.f'
lines=sources.read_text().splitlines()
new=(ROOT/'rtl/SynthStudioMonitor.v').as_posix()
if new not in lines:
    sources.write_text('\n'.join(lines+[new])+'\n')
print('Integrated mapping and passive PCM monitor, preserved DSP pool sizes')
