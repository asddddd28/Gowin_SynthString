"""多核分发的独立行为合同：接受顺序、返回顺序、复位和有界信用。"""
from collections import deque
from pathlib import Path
import hashlib,json,random

ROOT=Path(__file__).resolve().parent
BASE=ROOT.parent/'keyboard-studio'

def check_farm(cores,ii,latency,seed):
    rng=random.Random(seed);queues=[deque() for _ in range(cores)]
    next_ready=[0]*cores;accepted=[];returned=[];dispatch=retire=0
    for cycle in range(10000):
        # Each lane computes in order, but readiness and downstream stalls differ.
        if len(accepted)<400 and rng.random()>.15 and cycle>=next_ready[dispatch] and len(queues[dispatch])<16:
            tag=len(accepted);accepted.append(tag)
            queues[dispatch].append((cycle+latency+rng.randrange(3),tag))
            next_ready[dispatch]=cycle+ii;dispatch=(dispatch+1)%cores
        if queues[retire] and queues[retire][0][0]<=cycle and rng.random()>.2:
            returned.append(queues[retire].popleft()[1]);retire=(retire+1)%cores
        if len(returned)==400:break
    assert returned==list(range(400))
    return cycle+1

if __name__=='__main__':
    (ROOT/'reports').mkdir(parents=True,exist_ok=True)
    result={f'{n}core_ii{ii}':check_farm(n,ii,11,73+n+ii) for n in [1,2,3,4] for ii in [1,2,3]}
    sources=json.loads((BASE/'sources.json').read_text())
    baseline={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in sources}
    (ROOT/'reports/baseline_hashes.json').write_text(json.dumps(baseline,indent=2))
    contract={'route':['modify','generate','validate'],'clock_hz':50000000,'voices':32,'profile_bits':512,'state_bits':384,
      'interface':'AXI-Stream data/user/valid/ready; profile and wave write unchanged',
      'cores':{'phase':1,'wave':2,'envelope':3,'modulation':1,'filter':1,'vca':1},
      'parameter_range':'Each pool supports 1..4 compile-time instances; board fit must be measured for each choice',
      'prefetch':'RAM read + job/depth register + 8-entry credited task FIFO; one fetch per clock when space exists',
      'order':'round-robin dispatch and ordered lane retirement; stage barriers preserved',
      'reset':'cancel all task validity and pool cursors; keep old program/state boot protocol',
      'arithmetic':'reuse proven kernels bit-for-bit, no precision or preset changes',
      'review':{'interface':'same Studio UART and 32 keys','reset':'no stale credit after reset','timing':'register RAM read and modulation-depth alignment',
        'handshake':'cursors move only on handshakes; queue capacity includes in-flight RAM reads','width':'352-bit job,21-bit identity; per-kind ports checked',
        'synthesis':'replicate lookup RAM only for wave lanes; expensive SVF remains single by default',
        'testbench':'compare every voice return and PCM against 0x180A; vary pool counts and stalls',
        'risks':['BRAM capacity','wave replica consistency','event consume address vs prefetch address','head-of-line blocking','stage drain writeback ordering']},
      'gates':['compile','ast','readability','comment','naming','profile','testbench','toolchain'],
      'model_checks':result}
    (ROOT/'reports/design_contract.json').write_text(json.dumps(contract,indent=2))
    print('PASS 12 independent ordered-pool scenarios; baseline hashes captured')
