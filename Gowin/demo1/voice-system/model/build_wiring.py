"""Emit explicit named-port board wiring from the interface contracts."""
from contracts import PORTS, ROOT
import json
import hashlib


def header(name,parameters=''):
    declarations=[f"    {d} "+(f'[{w-1}:0] ' if w>1 else '')+n for d,n,w in PORTS[name]]
    return f'`timescale 1ns / 1ps\n// Contract: spec/{name}_spec.md.\nmodule {name}{parameters}(\n'+',\n'.join(declarations)+'\n);\n'


def instance(module,name,mapping,parameters=''):
    return f'    {module} {parameters} {name}(\n'+',\n'.join(f'        .{port}({signal})' for port,signal in mapping.items())+'\n    );\n'


def generate():
    arb=header('SynthCommandArbiter')+'''
    reg flag_owned,flag_prefer_host,flag_offered;
    reg [1:0] reg_owner,reg_offer_owner;
    reg [391:0] reg_offer;
    wire [1:0] wire_choice=!i_boot_done ? 2'd0 :
        (i_host_request_valid && (!i_key_request_valid || flag_prefer_host) ? 2'd2 : 2'd1);
    wire flag_offer=!flag_owned && !flag_offered && (wire_choice==0 ? i_boot_request_valid : wire_choice==1 ? i_key_request_valid : i_host_request_valid);
    assign o_request=reg_offer;
    assign o_request_valid=flag_offered;
    assign o_boot_request_ready=!flag_owned && !flag_offered && wire_choice==0;
    assign o_key_request_ready=!flag_owned && !flag_offered && wire_choice==1;
    assign o_host_request_ready=!flag_owned && !flag_offered && wire_choice==2;
    assign o_boot_response=i_response;
    assign o_key_response=i_response;
    assign o_host_response=i_response;
    assign o_boot_response_valid=flag_owned && reg_owner==0 && i_response_valid;
    assign o_key_response_valid=flag_owned && reg_owner==1 && i_response_valid;
    assign o_host_response_valid=flag_owned && reg_owner==2 && i_response_valid;
    assign o_response_ready=flag_owned && (reg_owner==0 ? i_boot_response_ready : reg_owner==1 ? i_key_response_ready : i_host_response_ready);
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin flag_owned<=0;reg_owner<=0;flag_prefer_host<=0;flag_offered<=0;reg_offer_owner<=0;reg_offer<=0;end
        else begin
            if (flag_offer) begin
                reg_offer<=wire_choice==0 ? i_boot_request : wire_choice==1 ? i_key_request : i_host_request;
                reg_offer_owner<=wire_choice;flag_offered<=1;
                if (wire_choice!=0) flag_prefer_host<=wire_choice==1;
            end
            if (o_request_valid && i_request_ready) begin
                flag_owned<=1;reg_owner<=reg_offer_owner;flag_offered<=0;
            end
            if (i_response_valid && o_response_ready) flag_owned<=0;
        end
    end
endmodule
'''
    (ROOT/'rtl/SynthCommandArbiter.v').write_text(arb,encoding='utf-8')
    top=header('SynthSystemTop',' #(parameter C_UART_CYCLES=434,parameter C_SETTLE_CYCLES=10000,parameter C_HALF_CYCLES=6,parameter C_POWERUP_CYCLES=65535,parameter C_AMP_CYCLES=1048576,parameter C_DELAY_ADDR_BITS=13)')
    top+='''
    reg [31:0] cnt_powerup=0;
    reg [1:0] reg_reset=0,reg_adc=0;
    wire flag_rstn=reg_reset[1];
    wire flag_boot_done,flag_boot_fault,flag_key_fault,flag_master_fault;
    wire [31:0] wire_pressed,wire_delivered,wire_key_events,wire_completed,wire_pcm_frames,wire_underruns,wire_bad_packets,wire_replayed;
    wire [4:0] wire_key;
    wire [11:0] wire_raw;
    wire flag_sample;
    reg [31:0] cnt_amplifier;
    wire [63:0] wire_pcm;
    wire [31:0] wire_pcm_frame;
    wire flag_pcm_valid,flag_pcm_ready;
    wire flag_amplifier=flag_rstn && flag_boot_done && cnt_amplifier==C_AMP_CYCLES && !flag_boot_fault && !flag_key_fault && !flag_master_fault && wire_underruns==0;
    wire [127:0] wire_status={wire_bad_packets[15:0],wire_underruns[15:0],wire_pcm_frames,wire_pressed,24'h535905,3'd0,flag_amplifier,flag_boot_fault,flag_key_fault,flag_master_fault,flag_boot_done};
    assign PA_EN=!flag_amplifier;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin cnt_powerup<=0;reg_reset<=0;end
        else begin
            if (cnt_powerup<C_POWERUP_CYCLES) cnt_powerup<=cnt_powerup+1'b1;
            reg_reset<={reg_reset[0],cnt_powerup==C_POWERUP_CYCLES};
        end
    end
    always @(posedge i_clk or negedge flag_rstn) begin
        if (!flag_rstn) begin reg_adc<=0;cnt_amplifier<=0;end
        else begin
            reg_adc<={reg_adc[0],i_adc_dout};
            if (cnt_amplifier<C_AMP_CYCLES) cnt_amplifier<=cnt_amplifier+1'b1;
        end
    end
'''
    for source in ('boot','key','host','master'):
        top+=f'    wire [391:0] {source}_request;\n    wire {source}_request_valid,{source}_request_ready;\n    wire [135:0] {source}_response;\n    wire {source}_response_valid,{source}_response_ready;\n'
    from contracts import AXI
    for _,name,width in AXI:top+='    wire '+(f'[{width-1}:0] ' if width>1 else '')+name[2:]+';\n'
    def stream(source,producer):
        return {('o_' if producer else 'i_')+'request':source+'_request',('o_' if producer else 'i_')+'request_valid':source+'_request_valid',
            ('i_' if producer else 'o_')+'request_ready':source+'_request_ready',('i_' if producer else 'o_')+'response':source+'_response',
            ('i_' if producer else 'o_')+'response_valid':source+'_response_valid',('o_' if producer else 'i_')+'response_ready':source+'_response_ready'}
    clock={'i_clk':'i_clk','i_rstn':'flag_rstn'}
    top+=instance('KeyboardSampler','Scanner_Inst',{**clock,'i_adc_dout':'reg_adc[1]','i_ready':"1'b1",'o_mux_sel':'o_mux_sel','o_mux_en':'o_mux_en','o_adc_cs_n':'o_adc_cs_n','o_adc_sclk':'o_adc_sclk','o_adc_din':'o_adc_din','o_key':'wire_key','o_raw':'wire_raw','o_valid':'flag_sample'},'#(.C_SETTLE_CYCLES(C_SETTLE_CYCLES),.C_HALF_CYCLES(C_HALF_CYCLES))')
    top+=instance('LatencyKeyThresholds','Thresholds_Inst',{**clock,'i_key':'wire_key','i_raw':'wire_raw','i_valid':'flag_sample','o_candidate':'','o_confirm':'','o_cancel':'','o_pressed':'wire_pressed'})
    top+=instance('SynthBootSequencer','Boot_Inst',{**clock,**stream('boot',True),'o_done':'flag_boot_done','o_fault':'flag_boot_fault'})
    top+=instance('SynthKeyboardSource','Keys_Inst',{**clock,**stream('key',True),'i_enabled':'flag_boot_done','i_pressed':'wire_pressed','o_delivered':'wire_delivered','o_events':'wire_key_events','o_fault':'flag_key_fault'})
    top+=instance('SynthUartControl','Host_Inst',{**clock,**stream('host',True),'i_rx':'i_uart_rx','o_tx':'o_uart_tx','i_initialized':'flag_boot_done && !flag_master_fault','i_status':'wire_status','o_bad_packets':'wire_bad_packets','o_replayed':'wire_replayed'},'#(.C_UART_CYCLES(C_UART_CYCLES))')
    mapping={**clock,**stream('master',True),'i_boot_done':'flag_boot_done'}
    for source in ('boot','key','host'):
        mapping.update({k.replace('i_request',f'i_{source}_request').replace('o_request',f'o_{source}_request').replace('o_response',f'o_{source}_response').replace('i_response',f'i_{source}_response'):v for k,v in stream(source,False).items()})
    top+=instance('SynthCommandArbiter','Arbiter_Inst',mapping)
    top+=instance('SynthAxiMaster','Master_Inst',{**clock,**stream('master',False),**{n:n[2:] for _,n,_ in AXI},'o_fault':'flag_master_fault','o_completed':'wire_completed'})
    ports=json.loads((ROOT.parent/'voice-engine/spec/AxiSynthEndpoint_contract.json').read_text(encoding='utf-8'))['modules'][0]['interfaces']['ports']
    mapping={'i_axi_aclk':'i_clk','i_axi_arstn':'flag_rstn','o_pcm_valid':'flag_pcm_valid','i_pcm_ready':'flag_pcm_ready','o_pcm_data':'wire_pcm','o_pcm_frame':'wire_pcm_frame'}
    constants={'awid':"4'd0",'arid':"4'd0",'awlen':"8'd0",'arlen':"8'd0",'awsize':"3'd2",'arsize':"3'd2",'awburst':"2'd1",'arburst':"2'd1",'awlock':"1'b0",'arlock':"1'b0",'wstrb':"4'hf",'wlast':"1'b1",'bid':'','rid':''}
    for p in ports:
        name=p['name']
        if name not in mapping:
            channel=name.split('_axi_')[-1]
            mapping[name]=constants.get(channel,'axi_'+channel)
    top+=instance('AxiSynthEndpoint','Endpoint_Inst',mapping,'#(.C_DELAY_ADDR_BITS(C_DELAY_ADDR_BITS))')
    top+=instance('SynthPcmOutput','Audio_Inst',{**clock,'i_valid':'flag_pcm_valid','i_data':'wire_pcm','o_ready':'flag_pcm_ready','o_bclk':'HP_BCK','o_ws':'HP_WS','o_data':'HP_DIN','o_frames':'wire_pcm_frames','o_underruns':'wire_underruns'})
    (ROOT/'rtl/SynthSystemTop.v').write_text(top+'endmodule\n',encoding='utf-8')
    engine=ROOT.parent/'voice-engine'
    sources=[(engine/line).resolve() for line in (engine/'sources.f').read_text(encoding='utf-8').splitlines() if line]
    sources.extend((ROOT/'rtl'/f'{name}.v').resolve() for name in PORTS)
    sources.extend([ROOT.parents[1]/'demo_test/diagnostics/keyboard_games/src/KeyboardSampler.v',ROOT.parents[1]/'demo_test/diagnostics/keyboard_games/src/UartRx.v',ROOT.parents[1]/'demo_test/diagnostics/encoder/src/EncoderUartTx.v',ROOT.parent/'keyboard-latency/src/LatencyKeyThresholds.v'])
    assert all(p.is_file() for p in sources)
    (ROOT/'sources.f').write_text('\n'.join(p.as_posix() for p in sources)+'\n',encoding='utf-8')
    if not (ROOT/'reports/shared-baseline.json').exists():
        (ROOT/'reports/shared-baseline.json').write_text(json.dumps({p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources if ROOT not in p.parents},indent=2)+'\n',encoding='utf-8')
    print('Wired',len(sources),'RTL definitions')


if __name__=='__main__':generate()
