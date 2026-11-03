"""Independent signed quantizer oracle and frozen-RTL pin equivalence."""
from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'sequencer/model'))
from run_tests import run

OUT = ROOT/'reports/sequencer/tabs-pcm-unit'
OUT.mkdir(parents=True, exist_ok=True)


def old_quantize(value):
    magnitude = (abs(value)+1024)//2048
    signed = -magnitude if value < 0 else magnitude
    return max(-32768, min(32767, signed))


def staged_expression(value):
    increment = bool(value&1024) and (value >= 0 or bool(value&1023))
    return max(-32768, min(32767, (value>>11)+increment))


def main():
    # Enumerate every discarded-bit pattern at each sign/clipping/carry boundary.
    uppers = (-1048576,-32770,-32769,-32768,-32767,-2,-1,0,1,2,32766,32767,32768,1048575)
    values = [upper*2048+fraction for upper in uppers for fraction in range(2048)]
    random_source = random.Random(20261103)
    values += [random_source.randrange(-2**31,2**31) for _ in range(100000)]
    with (OUT/'rounding.txt').open('w',encoding='ascii') as stream:
        for index, value in enumerate(values):
            assert old_quantize(value) == staged_expression(value), value
            right = values[-index-1]
            click = (-32768,-1024,-1,0,1,1024,32767)[index%7]
            dry = old_quantize(value)
            mixed = max(-32768,min(32767,dry+click))
            stream.write(f'{value&0xffffffff:08x} {right&0xffffffff:08x} {click&65535:04x} {dry&65535:04x} {mixed&65535:04x}\n')
    baseline = ROOT/'reports/hdmi-tabs/baseline/SynthPcmOutput.v'
    reference = OUT/'SynthPcmOutputReference.v'
    reference.write_text(baseline.read_text(encoding='utf-8').replace('module SynthPcmOutput #','module SynthPcmOutputReference #'),encoding='utf-8')
    run('tb_pcm_rounding',[ROOT/'rtl/SynthPcmOutput.v',reference,ROOT/'hdmi/sim/tb_pcm_rounding.v'],'tabs-pcm-unit')
    print('PASS independent quantizer cases',len(values),flush=True)


if __name__ == '__main__':
    main()
