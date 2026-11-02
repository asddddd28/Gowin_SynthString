"""FX compiler boundary and executable mailbox image checks."""
import copy
import json
from compile_fx import compile_fx, RATE
from fx_contracts import ROOT


def check():
    count=0
    for name in ('fx_room','fx_pad_space'):
        source=json.loads((ROOT/f'examples/{name}.json').read_text(encoding='utf-8'))
        result=compile_fx(source,epoch=55,sequence=10)
        assert result['next_sequence']==13 and result['domain']=='fx'
        assert [row['opcode'] for row in result['commands']]==[0xc0,0xc1,0xc2]
        for row in result['commands']:
            assert len(row['words'])==10
            writes={w['address']:w['value'] for w in row['axi_writes']}
            assert writes[0x130]==1 and writes[0x138]==row['sequence']
            assert writes[0x134]==55<<8
            assert [writes[0x100+4*n] for n in range(10)]==row['words']
        count+=1
    edge={'delay':{'left_ms':1000/RATE,'right_ms':(32768-1/65536)*1000/RATE,'feedback':-0.95,'wet':1},
        'reverb':{'feedback':0.9,'damping':0.95,'wet':1}}
    result=compile_fx(edge,epoch=0xffffff,sequence=0xfffffffc)
    assert result['commands'][0]['words'][0:2]==[65536,0x7fffffff]
    assert result['commands'][1]['words'][:2]==[60397977,63753420]
    rejects=0
    for group,key,value in [('delay','left_ms',0),('delay','right_ms',700),('delay','feedback',1),
        ('delay','feedback',float('nan')),('delay','wet',-0.1),('delay','enabled',1),
        ('reverb','feedback',-0.01),('reverb','feedback',0.91),('reverb','damping',0.96),('reverb','wet',1.1)]:
        config=copy.deepcopy(edge)
        config[group][key]=value
        try: compile_fx(config)
        except ValueError: rejects+=1
        else: raise AssertionError(f'accepted {group}.{key}={value}')
    for epoch,sequence in [(True,0),(1,-1),(1,0xfffffffd),(0x1000000,0)]:
        try: compile_fx(edge,epoch,sequence)
        except ValueError: rejects+=1
        else: raise AssertionError('accepted invalid transport identity')
    report=dict(status='passed',example_programs=count,boundary_programs=1,rejected_inputs=rejects)
    (ROOT/'reports/fx-compiler-check.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('PASS FX compiler',report)


if __name__=='__main__': check()
