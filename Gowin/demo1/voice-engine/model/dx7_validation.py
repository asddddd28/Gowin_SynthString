"""Generate DX arithmetic/whole-engine vectors and validate binary bank transport."""
import json
import random
from pathlib import Path
from dx7_bank import ROOT, INITIAL, factory, decode_sysex, encode_sysex, convert, algorithm_routes
from dx7_model import envelope, roms, UNITY
from compile_voice_patch import compile_patch, RATE
from voice_engine_model import operator, VoiceModel, packet


def rows(program):
    return [(program['commands'][1+2*i]['words'][:6],program['commands'][2+2*i]['words'][:8]) for i in range(6)]


def binary_tests():
    data=(ROOT/'assets/fm1/factory.vmem').read_bytes()
    source=[data[i:i+128] for i in range(0,len(data),128)]
    messages=[encode_sysex(source[i:i+32]) for i in range(0,128,32)]
    assert decode_sysex(b''.join(messages))==source
    for n in INITIAL: assert decode_sysex(encode_sysex([source[n]]))==[source[n]]
    corrupt=[b'',messages[0][:-1],messages[0]+b'!',bytes([0])+messages[0][1:],
             messages[0][:6]+bytes([messages[0][6]^1])+messages[0][7:],
             messages[0][:6]+bytes([128])+messages[0][7:]]
    for raw in corrupt:
        try:decode_sysex(raw)
        except ValueError:pass
        else:raise AssertionError('corrupt SysEx accepted')
    assert algorithm_routes(31)==([[],[],[],[],[],[]],[0,1,2,3,4,5])
    assert algorithm_routes(4)==([[],[0],[],[2],[],[4]],[1,3,5])
    for a in range(32):
        sources,carriers=algorithm_routes(a)
        assert carriers and all(all(n<i for n in s) for i,s in enumerate(sources))
    for index in (3,35,34):
        try:convert(source[index])
        except ValueError:pass
        else:raise AssertionError('unsupported original voice silently converted')
    return source


def arithmetic_vectors(source):
    rng=random.Random(0x445837)
    compiled=[compile_patch(convert(source[n],n)) for n in INITIAL]
    programs=[rows(p) for p in compiled]
    env_vectors=[];op_vectors=[]
    for n in range(6000):
        core,eg=programs[n%4][(n//4)%6]
        # Include all curve signs/kinds, KRS/KVS, breakpoints and rate extremes.
        shape=rng.randrange(100) | rng.randrange(100)<<7 | rng.randrange(100)<<14 | rng.randrange(4)<<21 | rng.randrange(4)<<23 | rng.randrange(8)<<25 | rng.randrange(8)<<28
        metadata=rng.randrange(128) | rng.randrange(128)<<7 | rng.randrange(128)<<14
        if n%3==0:eg=[rng.randrange(64)*64 for _ in range(3)]+[0]+[rng.randrange(64) for _ in range(4)]
        level=rng.randrange(16<<24)
        control=n%8 | ((n//8)%4)<<3 | ((n//32)%2)<<5
        words=[level,control,*eg]
        result=envelope(words,metadata,shape)
        env_vectors.append((packet(*words,metadata,shape),packet(*result)))
        if n<1600:
            w=[rng.getrandbits(32),rng.getrandbits(31),rng.randrange(-UNITY*3,UNITY*3),0,UNITY,
               *words,rng.randrange(-UNITY,UNITY),rng.randrange(-UNITY,UNITY),n%8,1,
               32|(metadata<<6),shape]
            op_vectors.append((packet(*w),operator(w)))
    # Sequential fast and slow release, including rate0 and maximum scaling.
    for rate in (0,20,40,63):
        level=stage=0
        for n in range(1024):
            event=1 if n==0 else 2 if n==512 else 0
            words=[level,stage|event<<3|32,4032,3904,3808,0,63,40,rate,rate]
            meta=127|127<<7|127<<14;shape=7<<25|7<<28
            result=envelope(words,meta,shape)
            env_vectors.append((packet(*words,meta,shape),packet(*result)))
            level,stage=result[0],result[1]&7
    for name,items,wi,wo in [('dx_envelope',env_vectors,96,24),('dx_operator',op_vectors,168,40)]:
        (ROOT/f'vectors/{name}.txt').write_text(''.join(f'{a:0{wi}x} {b:0{wo}x}\n' for a,b in items),encoding='ascii')
        bench(name,wi*4,wo*4,len(items))
    return dict(envelope_vectors=len(env_vectors),operator_vectors=len(op_vectors))


def bench(name,request_width,result_width,count):
    module='AxisDxEnvelope' if name=='dx_envelope' else 'AxisFmOperator'
    extra='' if name=='dx_envelope' else ',.i_wave_write(1\'b0),.i_wave_address(11\'d0),.i_wave_data(32\'d0),.o_wave_ready(wave_ready)'
    text=f'''`timescale 1ns/1ps
module tb_{name}(output o_done);
    reg clk=0,rstn=0,valid=0,ready=0,done=0;
    reg [{request_width-1}:0] data=0;
    reg [31:0] tag=0;
    wire accept,result_valid,wave_ready;
    wire [{result_width-1}:0] result;
    wire [31:0] result_tag;
    reg [{result_width-1}:0] expected,held;
    integer fd,code,n,latency,max_latency=0;
    assign o_done=done;
    always #10 clk=!clk;
    {module} Dut(.i_axis_aclk(clk),.i_axis_arstn(rstn),.i_s_axis_tdata(data),.i_s_axis_tuser(tag),
        .i_s_axis_tvalid(valid),.o_s_axis_tready(accept),.o_m_axis_tdata(result),.o_m_axis_tuser(result_tag),
        .o_m_axis_tvalid(result_valid),.i_m_axis_tready(ready){extra});
    initial begin
        repeat(4) @(negedge clk);rstn=1;
        fd=$fopen("vectors/{name}.txt","r");if(!fd)$fatal(1,"missing vectors");
        for(n=0;n<{count};n=n+1) begin
            @(negedge clk);code=$fscanf(fd,"%h %h\\n",data,expected);tag=n;valid=1;
            if(code!=2)$fatal(1,"vector format");
            @(posedge clk);while(!accept)@(posedge clk);
            @(negedge clk);valid=0;latency=1;
            while(!result_valid)begin @(negedge clk);latency=latency+1;if(latency>12)$fatal(1,"deadline");end
            if(latency>max_latency)max_latency=latency;
            if(result!==expected || result_tag!==tag)$fatal(1,"vector %0d expected %h got %h",n,expected,result);
            held=result;
            repeat(n%7)begin @(negedge clk);if(!result_valid || result!==held || result_tag!==tag)$fatal(1,"unstable stall");end
            ready=1;@(negedge clk);ready=0;
        end
        valid=1;@(negedge clk);valid=0;repeat(2)@(negedge clk);rstn=0;
        repeat(2)@(negedge clk);rstn=1;
        repeat(20)begin @(negedge clk);if(result_valid)$fatal(1,"reset ghost");end
        $display("PASS {name} vectors={count} max_latency=%0d stalls=PASS reset=PASS",max_latency);
        done=1;$finish;
    end
    initial begin #10000000;$fatal(1,"watchdog");end
endmodule
'''
    (ROOT/f'sim/tb_{name}.v').write_text(text,encoding='utf-8')


def engine_vectors(source):
    actions=[];patches=[];model=None
    def command(op,address=0,words=(),status=0):
        actions.append(f'0 {op:02x} {address:02x} {packet(*words):080x} {status:02x} 0000000000000000')
    def render(count,off_at=None,identities=()):
        for n in range(count):
            if n==off_at:
                for identity in identities:command(0xa5,words=[identity]);model.off(identity)
            l,r=model.frame();actions.append(f'1 00 00 {0:080x} 00 {packet(l,r):016x}')
    for slot,n in enumerate(INITIAL):
        program=compile_patch(convert(source[n],n),slot)
        patches.append(rows(program))
        for c in program['commands']:command(c['opcode'],c['address'],c['words'])
    model=VoiceModel(patches[0]);model.patches=dict(enumerate(patches))
    command(0xa7,words=[5,UNITY])
    notes=[36,48,60,72,84,55,67,79];velocities=[24,48,64,80,96,127,32,100]
    for v,(note,vel) in enumerate(zip(notes,velocities)):
        inc=round(440*2**((note-69)/12)*(1<<32)/RATE)
        command(0xa4,v%4,[100+v,inc,UNITY,UNITY//2,0x80000000|vel<<7|note])
        model.on(100+v,inc,patch=v%4,note=note,velocity=vel)
    # Exact duplicates do not restart any operator; changed metadata is a conflict.
    inc=round(440*2**((36-69)/12)*(1<<32)/RATE)
    render(256)
    command(0xa4,0,[100,inc,UNITY,UNITY//2,0x80000000|24<<7|36])
    command(0xa4,0,[100,inc,UNITY,UNITY//2,0x80000000|25<<7|36],5)
    command(0xa4,0,[101,inc,UNITY,UNITY//2,1],8)
    render(1280,off_at=512,identities=range(100,108))
    for slot in range(4):
        command(0xa7,words=[5,UNITY]);model.voices=[None]*8
        for note,vel in [(48,48),(60,100),(72,127)]:
            inc=round(440*2**((note-69)/12)*(1<<32)/RATE)
            identity=note+200
            command(0xa4,slot,[identity,inc,UNITY,UNITY//2,0x80000000|vel<<7|note])
            model.on(identity,inc,patch=slot,note=note,velocity=vel)
        render(2048,off_at=1024,identities=[248,260,272])
    command(0xa7,words=[5,UNITY]);model.voices=[None]*8
    # Native and DX programs co-reside; new A1 invalidates an earlier A2 format.
    native=json.loads((ROOT/'examples/FM_Keys.json').read_text(encoding='utf-8'));native['revision']=2
    program=compile_patch(native,3);model.patches[3]=rows(program)
    for c in program['commands']:command(c['opcode'],c['address'],c['words'])
    for slot in range(4):
        inc=23012828
        command(0xa4,slot,[400+slot,inc,UNITY,UNITY//2])
        model.on(400+slot,inc,patch=slot)
    render(512)
    # Live linear/log EG format changes must not reinterpret old voice state.
    replacement=compile_patch(native,0)
    for c in replacement['commands']:
        command(c['opcode'],c['address'],c['words'],10 if c['opcode']==0xa3 else 0)
    command(0xa7,words=[5,UNITY]);model.voices=[None]*8
    command(0xa3,0)
    command(0xa0,0,[3])
    core,eg=patches[0][0]
    invalid=list(core);invalid[4]|=1<<10;command(0xa1,0,invalid,8)
    command(0xa1,0,core)
    invalid=list(eg);invalid[4]=64;command(0xa2,0,invalid,8)
    invalid=list(eg);invalid[3]=1;command(0xa2,0,invalid,8)
    command(0xa2,0,eg)
    command(0xa1,0,core)
    command(0xa3,0,[],9)
    (ROOT/'vectors/fm1_engine.txt').write_text('\n'.join(actions)+'\n',encoding='ascii')
    return dict(pcm_frames=sum(x.startswith('1 ') for x in actions),commands=sum(x.startswith('0 ') for x in actions))


def main():
    factory();roms();source=binary_tests()
    report=arithmetic_vectors(source);report.update(engine_vectors(source))
    report.update(initial_programs=list(INITIAL),library_entries=128,sysEx_roundtrip=True)
    (ROOT/'reports/fm1-vectors.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('PASS DX model/bank generation',report)


if __name__=='__main__':main()
