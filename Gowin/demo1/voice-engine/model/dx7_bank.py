"""Strict DX7 SysEx import; 21 qualified presets and four boot slots.

CLI: python model/dx7_bank.py factory | list | import FILE --output JSON |
     export PROGRAM --output PATCH_JSON [--experimental]
No command opens a hardware port. Factory raw data are preserved byte-for-byte.
Algorithm bus flags derive from Google MSFA, Apache-2.0; see DSP_NOTICE.txt.
"""
import argparse
import hashlib
import json
from pathlib import Path
from dx7_model import scale_level

ROOT = Path(__file__).resolve().parents[1]
INITIAL = (4,1,42,68)
QUALIFIED = INITIAL + (32,43,79,106,16,25,28,60,72,80,81,89,97,101,110,118,126)
FACTORY_SHA = 'ecad0b8620f9d784d46c8da1e3c5de02c40214649ed8dec218026431046aad25'
ALGORITHMS = [bytes.fromhex(s) for s in '''
c1 11 11 14 01 14
01 11 11 14 c1 14
c1 11 14 01 11 14
41 11 94 01 11 14
c1 14 01 14 01 14
41 94 01 14 01 14
c1 11 05 14 01 14
01 11 c5 14 01 14
01 11 05 14 c1 14
01 05 14 c1 11 14
c1 05 14 01 11 14
01 05 05 14 c1 14
c1 05 05 14 01 14
c1 05 11 14 01 14
01 05 11 14 c1 14
c1 11 02 25 05 14
01 11 02 25 c5 14
01 11 11 c5 05 14
c1 14 14 01 11 14
01 05 14 c1 14 14
01 14 14 c1 14 14
c1 14 14 14 01 14
c1 14 14 01 14 04
c1 14 14 14 04 04
c1 14 14 04 04 04
c1 05 14 01 14 04
01 05 14 c1 14 04
04 c1 11 14 01 14
c1 14 01 14 04 04
04 c1 11 14 04 04
c1 14 04 04 04 04
c4 04 04 04 04 04
'''.strip().splitlines()]


def algorithm_routes(algorithm):
    if not 0 <= algorithm < 32: raise ValueError('algorithm must be 0..31')
    buses = [set(),set(),set()]
    sources = []
    for index, flags in enumerate(ALGORITHMS[algorithm]):
        bus_in, bus_out = (flags>>4)&3, flags&3
        sources.append(sorted(buses[bus_in]) if bus_in else [])
        if not flags&4: buses[bus_out] = set()
        buses[bus_out].add(index)
    return sources, sorted(buses[0])


def unpack_voice(raw):
    if len(raw) != 128 or any(x>127 for x in raw): raise ValueError('VMEM must be 128 seven-bit bytes')
    ops = []
    for index in range(6):
        p = raw[index*17:index*17+17]
        ops.append(dict(rates=list(p[:4]),levels=list(p[4:8]),breakpoint=p[8],
            left_depth=p[9],right_depth=p[10],left_curve=p[11]&3,right_curve=(p[11]>>2)&3,
            rate_scaling=p[12]&7,detune=p[12]>>3,ams=p[13]&3,velocity=p[13]>>2,
            output=p[14],fixed=bool(p[15]&1),coarse=p[15]>>1,fine=p[16]))
    return dict(name=raw[118:128].decode('ascii').strip(),operators=ops,
        pitch_rates=list(raw[102:106]),pitch_levels=list(raw[106:110]),algorithm=raw[110],
        feedback=raw[111]&7,osc_sync=bool(raw[111]&8),lfo_speed=raw[112],
        lfo_delay=raw[113],lfo_pmd=raw[114],lfo_amd=raw[115],lfo_sync=bool(raw[116]&1),
        lfo_wave=(raw[116]>>1)&7,pms=raw[116]>>4,transpose=raw[117],
        reserved_bits=bool(raw[111]&0x70 or any(raw[i*17+11]&0x70 for i in range(6))))


def blockers(voice):
    errors = []
    for i,o in enumerate(voice['operators']):
        for key in ('rates','levels'):
            if any(n>99 for n in o[key]): errors.append(f'op{6-i}: invalid {key} >99')
        if any(o[k]>99 for k in ('breakpoint','left_depth','right_depth','output','fine')) or o['detune']>14 or o['velocity']>7 or o['coarse']>31:
            errors.append(f'op{6-i}: invalid parameter range')
        if o['levels'][3] and o['output']: errors.append(f'op{6-i}: nonzero release level')
    if voice['pitch_levels'] != [50]*4: errors.append('pitch EG')
    if voice['lfo_pmd'] and voice['pms']: errors.append('DX LFO pitch modulation/delay')
    if voice['lfo_amd'] and any(o['ams'] and o['output'] for o in voice['operators']): errors.append('DX LFO amplitude modulation/delay')
    if voice['algorithm'] not in range(32): errors.append('invalid algorithm')
    elif voice['algorithm'] in (3,5) and voice['feedback']: errors.append('multi-operator feedback loop')
    if voice['transpose'] != 24: errors.append('global transpose')
    if not voice['osc_sync']: errors.append('free-running oscillator phase')
    if (any(x>99 for x in voice['pitch_rates']) or voice['lfo_wave']>5 or voice['pms']>7 or
        any(voice[k]>99 for k in ('lfo_speed','lfo_delay','lfo_pmd','lfo_amd')) or voice['reserved_bits']):
        errors.append('invalid global parameter range')
    return errors


def convert(raw, program_id=None):
    v = unpack_voice(raw)
    missing = blockers(v)
    if missing: raise ValueError(f"{v['name']}: "+'; '.join(missing))
    sources, carriers = algorithm_routes(v['algorithm'])
    operators = []
    for i,o in enumerate(v['operators']):
        profile = (o['breakpoint'] | o['left_depth']<<7 | o['right_depth']<<14 |
                   o['left_curve']<<21 | o['right_curve']<<23 | o['rate_scaling']<<25 | o['velocity']<<28)
        feedback = v['feedback'] if ALGORITHMS[v['algorithm']][i]&0xc0 == 0xc0 else 0
        dx = dict(levels=[(scale_level(x)>>1)<<6 for x in o['levels']],
                  rates=[(x*41)>>6 for x in o['rates']],output=scale_level(o['output']),
                  profile=profile,feedback=feedback)
        # A zero-output row is inaudible and need not execute its otherwise-unused EG.
        if o['output']==0: dx['levels'][3]=0
        row = dict(wave='sine',mode='pm',enabled=bool(o['output']),carrier=i in carriers,
                   sources=sources[i],gain=1,dx7=dx)
        if o['fixed']:
            row['fixed_hz'] = 10**(((o['coarse']&3)*100+o['fine'])/100)*2**(max(0,o['detune']-7)*13457/(1<<24))
        else:
            row['ratio'] = (o['coarse'] or 0.5)*(1+o['fine']/100)*2**(12606*(o['detune']-7)/(1<<24))
        operators.append(row)
    return dict(name=v['name'],revision=1,engine_profile='dx7-subset-1',operators=operators,
        source=dict(kind='DX7 VMEM',program=program_id,sha256=hashlib.sha256(raw).hexdigest(),raw_vmem=raw.hex()),
        compatibility=dict(bit_exact=False,limitations=['sample-stepped EG','quantized exp2/sine','normalized carrier/voice gain','FM1 effects not in DX7 voice data']))


def vced_to_vmem(data):
    if len(data)!=155 or any(v>127 for v in data): raise ValueError('VCED length/data')
    out = bytearray()
    for i in range(6):
        o=data[i*21:i*21+21]
        if o[11]>3 or o[12]>3 or o[13]>7 or o[14]>3 or o[15]>7 or o[17]>1 or o[18]>31 or o[20]>14:
            raise ValueError('VCED packed field out of range')
        out.extend(o[:11]);out.extend([o[11]|o[12]<<2,o[13]|o[20]<<3,o[14]|o[15]<<2,o[16],o[17]|o[18]<<1,o[19]])
    if data[134]>31 or data[135]>7 or data[136]>1 or data[141]>1 or data[142]>5 or data[143]>7:
        raise ValueError('VCED global field out of range')
    out.extend(data[126:135]);out.append(data[135]|data[136]<<3)
    out.extend(data[137:141]);out.append(data[141]|data[142]<<1|data[143]<<4)
    out.extend(data[144:155]);return bytes(out)


def vmem_to_vced(raw):
    unpack_voice(raw)
    out=bytearray()
    for i in range(6):
        o=raw[i*17:i*17+17]
        out.extend(o[:11]);out.extend([o[11]&3,(o[11]>>2)&3,o[12]&7,o[13]&3,o[13]>>2,o[14],o[15]&1,o[15]>>1,o[16],o[12]>>3])
    out.extend(raw[102:111]);out.extend([raw[111]&7,(raw[111]>>3)&1]);out.extend(raw[112:116])
    out.extend([raw[116]&1,(raw[116]>>1)&7,raw[116]>>4]);out.extend(raw[117:128]);return bytes(out)


def encode_sysex(voices, channel=0):
    if not 0<=channel<16 or len(voices) not in (1,32): raise ValueError('single or 32-voice bank required')
    for raw in voices: unpack_voice(raw)
    data = b''.join(voices) if len(voices)==32 else vmem_to_vced(voices[0])
    return bytes([0xf0,0x43,channel,9 if len(voices)==32 else 0,len(data)>>7,len(data)&127])+data+bytes([(-sum(data))&127,0xf7])


def decode_sysex(data):
    """Accept complete single/bulk messages only; reject truncation and garbage."""
    voices=[];offset=0
    while offset<len(data):
        if data[offset:offset+2] != b'\xf0\x43' or len(data)-offset<8: raise ValueError('bad Yamaha SysEx header')
        _,_,channel,fmt,msb,lsb=data[offset:offset+6]
        if channel>15 or msb>127 or lsb>127: raise ValueError('unsupported channel/length')
        length=(msb<<7)|lsb;end=offset+length+8
        if (fmt,length) not in ((9,4096),(0,155)) or end>len(data) or data[end-1]!=0xf7:
            raise ValueError('unsupported or truncated DX7 message')
        body=data[offset+6:end-2]
        if any(x>127 for x in body) or data[end-2]>127 or (sum(body)+data[end-2])&127:
            raise ValueError('DX7 seven-bit/checksum error')
        voices.extend([body[i:i+128] for i in range(0,4096,128)] if fmt==9 else [vced_to_vmem(body)])
        offset=end
    if not voices or len(voices)>128: raise ValueError('library must contain 1..128 voices')
    return voices


def catalog(voices, origin):
    entries=[]
    factory_source=origin=='FM1 factory' and hashlib.sha256(b''.join(voices)).hexdigest()==FACTORY_SHA
    for n,raw in enumerate(voices):
        v=unpack_voice(raw);missing=blockers(v)
        entries.append(dict(program=n,bank=n//32,index=n%32,name=v['name'],algorithm=v['algorithm']+1,
            raw_vmem=raw.hex(),sha256=hashlib.sha256(raw).hexdigest(),blocked_by=missing,
            status='initial-four' if factory_source and n in INITIAL and not missing else
                   'qualified-dry' if factory_source and n in QUALIFIED and not missing else
                   'blocked' if missing else 'unqualified'))
    return dict(schema='synthstring.dx7-library.v1',capacity=128,resident_slots=4,origin=origin,entries=entries)


def factory():
    folder=ROOT/'assets/fm1';data=(folder/'factory.vmem').read_bytes()
    if hashlib.sha256(data).hexdigest()!=FACTORY_SHA: raise ValueError('factory source checksum mismatch')
    voices=[data[n:n+128] for n in range(0,len(data),128)]
    result=catalog(voices,'FM1 factory')
    (folder/'library.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for slot,n in enumerate(INITIAL):
        patch=convert(voices[n],n)
        (ROOT/f'examples/FM1_{slot}_{patch["name"].replace(" ","_")}.json').write_text(json.dumps(patch,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for n in range(4): (folder/f'factory_{chr(65+n)}.syx').write_bytes(encode_sysex(voices[n*32:(n+1)*32]))
    print('Generated 128-entry library, four qualified candidate patches, four lossless SysEx banks')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['factory','list','import','export'])
    parser.add_argument('input',nargs='?');parser.add_argument('--output',type=Path)
    parser.add_argument('--library',type=Path,default=ROOT/'assets/fm1/library.json')
    parser.add_argument('--experimental',action='store_true')
    args=parser.parse_args()
    if args.action=='factory': factory();return
    if args.action=='import':
        if not args.input or not args.output:parser.error('import needs FILE and --output')
        result=catalog(decode_sysex(Path(args.input).read_bytes()),Path(args.input).name)
        args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');return
    library=json.loads(args.library.read_text(encoding='utf-8'))
    if args.action=='list':
        for e in library['entries']: print(f"{e['program']:03d} {e['name']:10} {e['status']:12} {'; '.join(e['blocked_by'])}")
    else:
        if args.input is None or not args.output:parser.error('export needs PROGRAM and --output')
        n=int(args.input);entry=next((x for x in library['entries'] if x['program']==n),None)
        if entry is None:raise ValueError('program not found')
        if entry['status'] not in ('initial-four','qualified-dry') and not args.experimental:raise ValueError('not a qualified preset; use --experimental only for explicit evaluation')
        patch=convert(bytes.fromhex(entry['raw_vmem']),n)
        args.output.write_text(json.dumps(patch,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
