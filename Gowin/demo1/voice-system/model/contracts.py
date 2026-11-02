"""Declare board wrapper interfaces before RTL and publish governed specifications."""
from pathlib import Path
import copy
import json
ROOT=Path(__file__).resolve().parents[1]
BASE=json.loads((ROOT.parent/'voice-engine/spec/AxisPhasePm_contract.json').read_text(encoding='utf-8'))['modules'][0]
CLOCK=[('input','i_clk',1),('input','i_rstn',1)]
REQUEST=[('input','i_request',392),('input','i_request_valid',1),('output','o_request_ready',1),
    ('output','o_response',136),('output','o_response_valid',1),('input','i_response_ready',1)]
SOURCE=[('output','o_request',392),('output','o_request_valid',1),('input','i_request_ready',1),
    ('input','i_response',136),('input','i_response_valid',1),('output','o_response_ready',1)]
AXI=[('output','o_axi_awaddr',16),('output','o_axi_awvalid',1),('input','i_axi_awready',1),
    ('output','o_axi_wdata',32),('output','o_axi_wvalid',1),('input','i_axi_wready',1),
    ('input','i_axi_bresp',2),('input','i_axi_bvalid',1),('output','o_axi_bready',1),
    ('output','o_axi_araddr',16),('output','o_axi_arvalid',1),('input','i_axi_arready',1),
    ('input','i_axi_rdata',32),('input','i_axi_rresp',2),('input','i_axi_rlast',1),('input','i_axi_rvalid',1),('output','o_axi_rready',1)]
PORTS={
    'SynthAxiMaster':CLOCK+REQUEST+AXI+[('output','o_fault',1),('output','o_completed',32)],
    'SynthBootSequencer':CLOCK+SOURCE+[('output','o_done',1),('output','o_fault',1)],
    'SynthKeyboardSource':CLOCK+SOURCE+[('input','i_enabled',1),('input','i_pressed',32),('output','o_delivered',32),('output','o_events',32),('output','o_fault',1)],
    'SynthUartControl':CLOCK+SOURCE+[('input','i_rx',1),('output','o_tx',1),('input','i_initialized',1),('input','i_status',128),('output','o_bad_packets',32),('output','o_replayed',32)],
    'SynthPcmOutput':CLOCK+[('input','i_valid',1),('input','i_data',64),('output','o_ready',1),('output','o_bclk',1),('output','o_ws',1),('output','o_data',1),('output','o_frames',32),('output','o_underruns',32)],
    'SynthSystemTop':CLOCK+[('input','i_adc_dout',1),('input','i_uart_rx',1),('output','o_mux_sel',3),('output','o_mux_en',1),('output','o_adc_cs_n',1),('output','o_adc_sclk',1),('output','o_adc_din',1),('output','o_uart_tx',1),('output','HP_BCK',1),('output','HP_WS',1),('output','HP_DIN',1),('output','PA_EN',1)]}
arb=CLOCK+SOURCE+[('input','i_boot_done',1)]
for source in ('boot','key','host'):
    arb.extend([(d,n.replace('i_request',f'i_{source}_request').replace('o_request',f'o_{source}_request').replace('o_response',f'o_{source}_response').replace('i_response',f'i_{source}_response'),w) for d,n,w in REQUEST])
PORTS['SynthCommandArbiter']=arb
BEHAVIOR={
    'SynthAxiMaster':['Single-outstanding AXI4 master; aligned 32-bit single-beat INCR, ID=0 and full strobes tied at top.',
        '392-bit request words: payload[319:0], opcode[327:320], argument[335:328], read flag[336], register[359:344], tag[391:360].',
        'Commands stage 15 register writes, poll completion, read result/tag/opcode, verify ownership, then POP. Separate Voice and FX sequences owned here, epoch=1.',
        '136-bit response: result128 and transport status8. Result held under backpressure. AXI channel VALID remains asserted until handshake.',
        'Bus response errors or watchdog set a sticky fault; no new command accepted. Watchdog does not withdraw an outstanding AXI beat. Reset is required to recover.'],
    'SynthBootSequencer':['Synchronous 32-bit ROM contains count followed by opcode/argument plus ten payload words per command.',
        'Four presets, shared FX and safe master level loaded through the same AXI master as live controls. Done only after every success completion; failure prevents amplifier enable.'],
    'SynthKeyboardSource':['Physical key bitmap becomes edge events; holding a key never emits another NoteOn.',
        '32 keys map chromatically to MIDI48..79, slot0; every new press gets a fresh bit31-set NoteID, release uses its saved identity.',
        'DX ABI0x00010005 NoteOn word4 carries marker31, fixed velocity100[13:7], true MIDI note[6:0]. Strike velocity is not measured by the current keybed.',
        'Pending request is immutable; delivered bitmap changes only after successful completion. Input changes coalesce to latest bitmap while busy.'],
    'SynthUartControl':['Protocol5: fixed52-byte request SY/version/kind/sequence/opcode/argument/payload40/CRC16-CCITT, little-endian.',
        'Response32 bytes SR/version/kind/sequence/result128/transport_status/opcode/argument/replayflag/reserved16/CRC16.',
        'Kind0 engine command; kind1 read AXI register (payload W0); kind2 local status. Stop-and-wait, latest exact request cached, conflicts/stale/gaps reject without execution.',
        'Invalid CRC, framing, byte gap or packets while busy never execute. RX and TX use independent byte engines; host retries on timeout.',
        'DECODE registers packet equality and payload-zero chunks; CLASSIFY registers replay/conflict/sequence/payload decisions before CHECK. Adds two control clocks, preserves byte-exact retry semantics.',
        'Host NoteIDs must have bit31 clear; physical key IDs reserved. Boot-not-ready rejects engine/read requests. Local status is accepted while the parser is idle; a permanently stalled AXI request holds WAIT_REPLY until handshake or reset.'],
    'SynthCommandArbiter':['Boot has exclusive command ownership until initialized. Afterwards round-robin arbitration between physical keys and host.',
        'Owner held until its response is accepted; samples run independently of command arbitration.'],
    'SynthPcmOutput':['Q26 stereo to saturated signed16 with symmetric nearest rounding; consume PCM only at fixed1024-clock frame boundaries.',
        'PT8211: 16 BCK per channel, WS high left, MSB first. BCK rises at counts16+32n; serial data changes near preceding falling edge.',
        'Startup silence is not an underrun; after first consumed sample missing frames output zero and increment underrun counter.'],
    'SynthSystemTop':['Single50MHz board hierarchy: ADC scanner and hysteresis → note source; UART → framed control; boot/keys/host → arbiter → AXI master → AxiSynthEndpoint → PT8211.',
        'Reset synchronously released after powerup delay; ADC/UART inputs synchronized. PA_EN active low, enabled only after successful boot and amplifier delay and no faults.',
        'Core subsystem is shared with voice-engine. No generic AXI crossbar/DMA or external RAM master is claimed.',
        'C_DELAY_ADDR_BITS=13 board default; core library defaults to15. Capability registers and parameter limits follow the synthesized depth.']}


def publish(name,ports,behavior,path=None):
    m=copy.deepcopy(BASE)
    m.update(name=name,rtl_path=path or f'rtl/{name}.v',description=behavior[0],behavior=behavior)
    m['interfaces']['ports']=[dict(name=n,direction=d,width=w,role='clock' if n=='i_clk' else 'reset' if n=='i_rstn' else 'data' if w>1 else 'control',description=n) for d,n,w in ports]
    m['constraints']=['Verilog-2001, single50MHz clock; asynchronous reset assertion, externally synchronized release.',
        'See SYSTEM.md and model/system_model.py for ABI, numerical behavior, memory images and validation scope.']
    m['verification_cases']=['Independent protocol/PCM model','Real UART/ADC pins to serial DAC simulation',
        'AXI stalls, transaction ownership, duplicate/conflicting/invalid requests and reset','Boot, physical chord, release, host voice/FX commands and resource/timing checks']
    m['timing_diagrams'][0]['description']='事件或命令稳定保持至握手，执行后完成返回；音频按固定帧节拍独立运行。示意图不表示绝对运算周期。'
    (ROOT/f'spec/{name}_contract.json').write_text(json.dumps({'modules':[m]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def generate():
    for name,ports in PORTS.items():publish(name,ports,BEHAVIOR[name])
    plan=dict(classes=['generate','analyze','validate'],existing_core='../voice-engine',board_baseline='../keyboard-latency',
        changes='New isolated board top, boot ROM, event arbitration, UART framing/cache, AXI master and PCM serializer; original proven board top unchanged',
        gates=['compile','ast','readability','comment','naming','profile','testbench','toolchain'],
        review=dict(interface='Single owner on AXI mailbox; no interleaved staging writes',reset='ROM and RAM initialized/qualified; reset cancels all protocol state',
            timing='Fixed1024-cycle audio frame; master bounded watchdog separate from DSP',handshake='Hold all request/result/bus fields under stall',
            widths='Q26 to PCM16, 392-bit internal commands, UART CRC and monotonic identities',synthesis='Full-board placement required: 15-bit delay exceeded BSRAM; 14-bit delay plus synchronous program RAM used to reduce pressure',
            testbench='ADC wire model, UART bytes/CRC and decoded PT8211 samples, deadline and continuity',
            risks=['Pin/clock constraints inherited from tested board','General program/DMA and independent slave windows not implemented','Strict style gate is already failing in shared candidate core']))
    (ROOT/'system-plan.json').write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':generate()
