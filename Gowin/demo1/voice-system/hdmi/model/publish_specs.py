"""Publish explicit display interface contracts and governed timing diagrams."""
from pathlib import Path
import copy
import json
import os
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
SYSTEM=ROOT.parent
template=json.loads((SYSTEM/'spec/SynthKeyboardSource_contract.json').read_text(encoding='utf-8'))['modules'][0]
definitions={
 'SynthDisplayAudio':('i_clk i_rstn i_sample_valid i_sample:16 i_pixel_clk i_pixel_rstn i_blank_start i_wave_address:8 i_spectrum_address:6 o_wave:8 o_spectrum:7 o_available o_publish', ['64-bin 256-sample rectangular-window fixed-point DFT; logarithmic magnitude model is display_model.spectrum.','Two pipelined signed products and shared accumulators; 448 clocks/sample, no audio backpressure.','Dual-clock ping-pong waveform/spectrum RAM publishes only at vertical blank; producer waits for acknowledged bank and discards observation samples meanwhile.','Frozen waveform peak selects1..128 display gain, unity below64 counts. Gain and bank are held together through CDC; actual audio is unchanged.','TRIGGER waits for a negative excursion then a rising zero crossing before collecting256 consecutive samples. Threshold=max(4,previous_peak/16);2048-sample timeout forces fresh DC/silence capture. No synthesized-audio backpressure or circular sample rotation.']),
 'SynthDisplayControl':('i_clk i_rstn i_joystick:5 i_encoder_a:5 i_encoder_b:5 i_request i_opcode:8 i_argument:8 i_words:64 o_response_valid o_response:136 o_text_write o_text_address:10 o_text_data:8 o_page:3 o_focus:8 o_confirm:16 o_host_live', ['Protocol5 kind3 opcodes0x10..0x13 implement capability, page, eight-byte metadata write and absolute input counters.','Five encoder inputs pass two synchronizers and50us filtering; illegal Gray transitions do not count. Joystick requires5ms stable.','Electrical bit0=H/bit1=L:00 low,01 centre,11 high,10 invalid. Startup settling and centre-to-arm prevent held inputs, releases or invalid transitions from generating actions.','X high advances page, low reverses; Y high decrements focus, low increments. Horizontal has priority for diagonal moves. Switch low emits one confirmation after release-to-arm.','Page bounds checked; text writes acknowledge after all eight write edges. UART exact replay belongs to existing SynthUartControl. Host-live expires2seconds after last input query.']),
 'SynthDisplaySnapshot':('i_clk i_rstn i_pixel_clk i_pixel_rstn i_blank_start i_keys:32 i_latency:32 i_underruns:32 i_errors:32 i_frames:32 i_page:3 o_fields:160 o_page:3', ['Pixel blank requests a held source-domain snapshot; two-flop toggle synchronizers acknowledge stable bundled data.','Iterative divide-by-50 and packed decimal conversion render microseconds without a wide combinational divider.','Audio/key collection never waits for snapshot conversion.']),
 'SynthDisplayVideo':('i_clk i_rstn i_system_clk i_calibrating i_host_live i_page:3 i_fields:160 i_text_write i_text_address:10 i_text_data:8 i_wave:8 i_spectrum:7 i_audio_available i_publish o_wave_address:8 o_spectrum_address:6 o_blank_start o_rgb:24 o_hsync o_vsync o_de', ['1280x720 active; totals1650x750; HS1390..1429, VS725..729, positive polarity. Pixel clock73.333333MHz.','Deduplicated12x16 character cells use SynthUI palette and original5x7 bitmap font, six pages, real32-key highlight. Footer order is E5,E4,E3,E2,E1 matching physical placement.','Five pixel pipeline stages align RGB and timing. No framebuffer or external RAM. Text metadata may become visible during the current frame; whole-page geometry changes in blanking.','Host-live synchronizes to pixel clock; expired connection selects offline banner. 64x64 spectrum history updates in blanking; DFT display covers190.735Hz..12.207kHz.']),
 'SynthHdmiTop':('i_clk i_rstn i_adc_dout i_uart_rx i_encoder_a:5 i_encoder_b:5 i_joystick:5 o_mux_sel:3 o_mux_en o_adc_cs_n o_adc_sclk o_adc_din o_uart_tx HP_BCK HP_WS HP_DIN PA_EN tmds_clk_p_0 tmds_clk_n_0 tmds_d_p_0:3 tmds_d_n_0:3 hpd_en', ['Existing50MHz audio and key engine plus independent73.333MHz pixel/366.666MHz serializer clocks.','Official DVI-compatible HDMI video output; headphone PT8211 remains the audio output.','Display local commands share existing durable CRC/sequence/replay UART; no second serial owner.','FX remains disabled. No display ready signal can stall synthesis or audio.'])
}
env=os.environ.copy();env['PYTHONPATH']='C:/Users/asddddd28/.agents/skills/readable-verilog-generator';env['PYTHONIOENCODING']='utf-8'
(ROOT/'spec').mkdir(exist_ok=True)
for name,(ports,behavior) in definitions.items():
    module=copy.deepcopy(template)
    module.update(name=name,rtl_path=f'rtl/{name}.v',description=behavior[0],behavior=behavior)
    module['interfaces']['ports']=[]
    for item in ports.split():
        n,_,width=item.partition(':')
        domain='i_clk'
        if name=='SynthDisplayAudio' and n not in ('i_clk','i_rstn','i_sample_valid','i_sample'):domain='i_pixel_clk'
        if name=='SynthDisplaySnapshot' and (n.startswith('o_') or n in ('i_pixel_clk','i_pixel_rstn','i_blank_start')):domain='i_pixel_clk'
        if name=='SynthDisplayVideo' and n in ('i_system_clk','i_text_write','i_text_address','i_text_data','i_host_live'):domain='i_system_clk'
        if name=='SynthDisplayControl' and n in ('i_joystick','i_encoder_a','i_encoder_b'):domain='asynchronous'
        module['interfaces']['ports'].append(dict(name=n,direction='input' if n.startswith('i_') else 'output',width=int(width or 1),clock_domain=domain,role='clock' if n in ('i_clk','i_pixel_clk','i_system_clk') else 'reset' if 'rstn' in n else 'data',description=n))
    module['clock']['name']='i_clk';module['reset']['name']='i_rstn'
    module['constraints']=['50MHz system; 73.333333MHz pixel; related5x serializer. Hold multi-bit CDC payload through toggle acknowledgement.','ROM/RAM contents generated by prepare_assets.mjs; no asynchronous array reset.']
    module['corner_cases']=['Reset while transfer pending; invalid opcode/argument; sustained key; missing display consumer.','No host connection: monitoring and page navigation continue; metadata edits require connected App.']
    module['verification_cases']=['tb_display_audio: phase-invariant triggered captures, bounded quiet/silence/DC timeout,448 spectral bins and1792 waveform values including30.5Hz exact vs Python, dual-clock publication.','tb_display_control: valid/invalid local commands, text ACK ordering and decimal CDC.','tb_display_video: six921600-pixel frames with no unknown RGB; visually inspect actual RTL images.','Full SynthSystemTop UART/keyboard/PCM regression and actual Gowin place-and-route.']
    module['timing_diagrams']=[dict(id='pipeline',title='显示旁路与提交',scenario='pipeline',description='音频独立推进，显示仅消费快照并在消隐时提交。',wavejson={'signal':[{'name':'clk','wave':'p.........'},{'name':'audio_sample','wave':'010....10.'},{'name':'observe','wave':'0.1.....1.'},{'name':'publish','wave':'0....1....'},{'name':'vblank','wave':'0.....10..'},{'name':'display_bank','wave':'0......1..'}]})]
    if name=='SynthDisplayControl':
        module['timing_diagrams']=[dict(id='navigation',title='中位解锁与单次方向动作',scenario='navigation',description='每格代表稳定去抖后的观察点；首次见中位解锁，右拨产生一次事件，保持和回中不切页。',wavejson={'signal':[{'name':'clock','wave':'p.......'},{'name':'region','wave':'=.=..=.=','data':['centre','right','centre','left']},{'name':'armed','wave':'01.0..10'},{'name':'right_event','wave':'0..10...'},{'name':'left_event','wave':'0......1'}]})]
    path=ROOT/f'spec/{name}_contract.json';path.write_text(json.dumps({'modules':[module]},ensure_ascii=False,indent=2),encoding='utf-8')
    log=SYSTEM/f'reports/synthui-hdmi/{name}-spec.log'
    with log.open('w',encoding='utf-8') as stream:
        result=subprocess.run([sys.executable,'-m','scripts.python.workflow.cli','write-spec','--spec',str(path),'--out-dir',str(ROOT),'--language','zh'],cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT)
    if result.returncode: raise RuntimeError(str(log))
print('Published five HDMI module contracts')
