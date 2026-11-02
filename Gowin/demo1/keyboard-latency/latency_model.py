"""Independent time contract for capture-to-DAC supervision (50 MHz)."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
MASK = (1 << 32) - 1

def record(capture, detect, commit, first_result, nonzero_result, pcm, dac):
    difference = lambda a,b: (a-b) & MASK
    parts = dict(qualify=difference(detect,capture),queue=difference(commit,detect),
                 compute=difference(first_result,commit),onset_wait=difference(nonzero_result,first_result),
                 output=difference(dac,nonzero_result),mix=difference(pcm,nonzero_result))
    total = difference(dac,capture)
    assert total == sum(parts[k] for k in ('qualify','queue','compute','onset_wait','output'))
    assert parts['mix'] <= parts['output']
    return dict(total=total,**parts)

def validate():
    a = record(10,110,130,170,200,210,250)
    assert a == dict(total=240,qualify=100,queue=20,compute=40,onset_wait=30,output=50,mix=10)
    # Subtraction must work across the 85.9-second timestamp wrap.
    b = record(*[((MASK-99)+x)&MASK for x in (0,100,120,160,190,200,240)])
    assert b == a
    simultaneous = [record(100,100,130+i,170+i,200+i,250,300) for i in range(32)]
    assert all(r['total']==200 for r in simultaneous)
    # An unsuccessful threshold crossing is canceled, not counted as a note.
    states={'candidate':'qualifying','cancel':'idle','confirm':'detected','commit':'voice',
            'zero_voice':'voice','nonzero_voice':'pcm','zero_pcm':'voice','nonzero_pcm':'load',
            'frame_load':'play','left_word_latch':'complete'}
    contract=dict(route=['generate','modify','validate'],clock_hz=50_000_000,
      start='physical: first ADC sample crossing press threshold; remote: effective gate rising inside FPGA',
      detect='physical second qualifying scan; remote same cycle as start',
      end='WS falling edge latching the left PT8211 word of the first nonzero voice contribution in a nonzero rounded DAC frame',
      limits='No pre-scan mechanical delay, analog DAC/amplifier delay or acoustic propagation measurement; nonzero digital data is not an audibility guarantee',
      per_key_capacity=1,voices=32,states=states,timeout_cycles=50_000_000,budget_cycles=500_000,
      arithmetic='32-bit modular timestamps; duration limited to 1 second; snapshot/difference/commit pipeline',
      report='protocol 4, 192 bytes, common 0..77 prefix, latency 80..189, XOR 190, CR 191',
      observation_only=True,
      review=dict(interface='Audio result and actual serializer boundary taps; no ready/valid feedback from monitor',
        reset='Cancel all monitor transactions; L resets monitor only',timing='Shared scanner serializes 32 simultaneous completions',
        collision='New note replaces old transaction with overwrite accounting; generation guards stale report/timeout',
        width='32-bit durations, 64-bit sum, fixed 50 MHz conversion',
        testbench=['exact timestamps','wrap','debounce cancel','silent/slow onset','32 keys','timeout','retrigger','PT8211 pin correlation','protocol fragmentation']),
      gates=['compile','ast','readability','comment','naming','profile','testbench','toolchain'],model_vectors=[a,b,*simultaneous])
    (ROOT/'reports/design_contract.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS independent latency arithmetic, wrap and 32-key contract')

if __name__=='__main__':validate()
