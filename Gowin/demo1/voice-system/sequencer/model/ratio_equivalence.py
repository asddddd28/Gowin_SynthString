"""Compare the staged ratio path with the frozen RTL using real AXIS commands."""
from pathlib import Path
from run_tests import ROOT, OUT, run

engine = ROOT.parent / 'voice-engine'
work = OUT / 'dsp'
baseline = OUT / 'window-baseline/VoiceSynthEngine.v'
reference = work / 'VoiceSynthEngineReference.v'
reference.write_text(baseline.read_text(encoding='utf-8').replace(
    'module VoiceSynthEngine #', 'module VoiceSynthEngineReference #'), encoding='utf-8')
source = (engine / 'sim/tb_voice_engine.v').read_text(encoding='utf-8')
source = source.replace('module tb_voice_engine(', 'module tb_ratio_equivalence(')
start = source.index('    VoiceSynthEngine Dut(')
end = source.index('    task request;', start)
ports = ('command_ready', 'response_valid', 'pcm_valid', 'response', 'response_tag',
         'response_opcode', 'frame', 'overruns', 'cycles', 'active', 'pcm')
instance = source[start:end].replace('VoiceSynthEngine Dut(', 'VoiceSynthEngineReference Ref(')
for port in ports:
    instance = instance.replace('(' + port + ')', '(ref_' + port + ')')
declarations = '''
    wire ref_command_ready, ref_response_valid, ref_pcm_valid;
    wire [127:0] ref_response;
    wire [31:0] ref_response_tag, ref_frame, ref_overruns, ref_cycles;
    wire [7:0] ref_response_opcode, ref_active;
    wire [63:0] ref_pcm;
    integer fixed_seen=0, clamp_seen=0, ratio_seen=0;
    always @(negedge clk) if(rstn) begin
        if({command_ready,response_valid,pcm_valid,active} !==
           {ref_command_ready,ref_response_valid,ref_pcm_valid,ref_active})
            $fatal(1,"pipeline changed interface timing");
        if(response_valid && response!==ref_response) $fatal(1,"completion mismatch");
        if(pcm_valid && {pcm,cycles}!=={ref_pcm,ref_cycles}) $fatal(1,"PCM or latency mismatch");
        if(Dut.reg_state==2) begin
            if(Dut.reg_operator_request!==Ref.reg_operator_request) $fatal(1,"operator request mismatch");
            if(Dut.flag_fixed_increment) fixed_seen=fixed_seen+1;
            else if(Dut.reg_operator_request[63:32]==32'h7fffffff) clamp_seen=clamp_seen+1;
            else ratio_seen=ratio_seen+1;
        end
    end
'''
source = source[:end] + declarations + instance + source[end:]
# Alternate fixed and relative parameters in every current/next prefetch row.
source = source.replace('command(8\'ha1,op,core[op],0);', '''
            core[op][141]=(op%2==0);
            core[op][31:0]=(op%2==0) ? 32'd31415926 : (op==1 ? 32'h00100000 : 32'd98304);
            command(8'ha1,op,core[op],0);''')
source = source.replace('command(8\'ha1,8+op,core[op],0);', '''
            core[op][141]=(op%2==1);
            core[op][31:0]=(op%2==1) ? 32'd27182818 : (op==2 ? 32'h00100000 : 32'd32768);
            command(8'ha1,8+op,core[op],0);''')
source = source.replace('pcm!==expected', 'pcm!==ref_pcm')
source = source.replace('20000000+v*1234567', '200000000+v*1234567')
source = source.replace("32'd20000000,32'd100", "32'd200000000,32'd100")
source = source.replace('done=1;', '''
        if(fixed_seen==0 || clamp_seen==0 || ratio_seen==0) $fatal(1,"missing frequency coverage");
        $display("PASS ratio_equivalence fixed=%0d clamp=%0d relative=%0d exact_requests=PASS exact_PCM=PASS latency=UNCHANGED",fixed_seen,clamp_seen,ratio_seen);
        done=1;''')
test = work / 'tb_ratio_equivalence.v'
test.write_text(source, encoding='utf-8')
sources = [engine / Path(s) for s in (engine/'sources.f').read_text().splitlines() if s.strip()]
run('tb_ratio_equivalence', sources + [reference, test], 'dsp')
