"""键盘到 AXIS 合成器的独立整数合同；不访问串口或修改原工程。"""
from pathlib import Path
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent
CLOCK_HZ = 50_000_000
FRAME_CLOCKS = 1024


def threshold_sample(pressed, qualify, raw, press, release, decreasing):
    """同一键连续两个完整扫描越过迟滞门限才改变按下状态。"""
    crossed = (raw >= release if decreasing else raw <= release) if pressed else (raw <= press if decreasing else raw >= press)
    return ((not pressed, False) if qualify else (pressed, True)) if crossed else (pressed, False)


def make_profile(note, event):
    """50 MHz / 1024 采样率、正弦载波、线性包络和已验证的 SVF 系数。"""
    frequency = 440.0 * 2.0 ** ((note - 69) / 12.0)
    phase_step = round(frequency * (2**32) * FRAME_CLOCKS / CLOCK_HZ)
    fields = [(phase_step,32),(540,97),(54,115),(196608,133),(27,151),
              (event,169),(0x00cccccd,230),(0x10000000,262),
              (0x0051eb85,294),(0x10000000,326),(1,358),(96,361),(1,368)]
    return sum(value << shift for value,shift in fields)


def prepare():
    """冻结源文件哈希和实测校准，并生成可复现 ROM、工程及构建脚本。"""
    for name in ['src','sim','reports','spec','rtl/synth','baseline']:
        (ROOT/name).mkdir(parents=True,exist_ok=True)
    calibration = json.loads((SOURCE.parent/'demo_test/desktop/measured_profile.json').read_text(encoding='utf-8'))
    thresholds=[]
    for item in calibration['keys']:
        key=item['calibration']; rest=key['rest']; bottom=key['bottom']
        assert abs(bottom-rest)>=100
        press=round(rest+(bottom-rest)*calibration['press_threshold'])
        release=round(rest+(bottom-rest)*calibration['release_threshold'])
        thresholds.append((int(bottom<rest)<<24)|(release<<12)|press)
        pressed,qualify=False,False
        for sample in [round(rest),round(bottom),round(rest),round(bottom)]:
            pressed,qualify=threshold_sample(pressed,qualify,sample,press,release,bottom<rest)
        assert not pressed and qualify
        pressed,qualify=threshold_sample(pressed,qualify,round(bottom),press,release,bottom<rest)
        assert pressed and not qualify
        for sample in [round(rest),round(rest)]:
            pressed,qualify=threshold_sample(pressed,qualify,sample,press,release,bottom<rest)
        assert not pressed
    (ROOT/'key_thresholds.hex').write_text(''.join(f'{x:07x}\n' for x in thresholds))
    (ROOT/'note_profiles.hex').write_text(''.join(f'{make_profile(48+i,0):094x}\n' for i in range(32)))
    (ROOT/'calibration.json').write_text(json.dumps(calibration,ensure_ascii=False,indent=2),encoding='utf-8')
    sine=SOURCE/'rtl/synth/sine.mem'
    (ROOT/'rtl/synth/sine.mem').write_bytes(sine.read_bytes())
    sources=[SOURCE/p.strip().strip('"') for p in (SOURCE/'sources-axis-system.f').read_text().splitlines() if p.strip()]
    sources += [SOURCE.parent/'demo_test/diagnostics/keyboard_games/src/KeyboardSampler.v',
                SOURCE.parent/'demo_test/diagnostics/keyboard_games/src/UartRx.v',
                SOURCE.parent/'demo_test/diagnostics/encoder/src/EncoderUartTx.v']
    baseline={p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (ROOT/'baseline/source_hashes.json').write_text(json.dumps(baseline,indent=2))
    for p in sources:
        dest=ROOT/'baseline'/p.relative_to(SOURCE.parent)
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(p.read_bytes())
    sources += sorted((ROOT/'src').glob('*.v'))
    file_xml='\n'.join(f'<File path="{p.as_posix()}" type="file.verilog" enable="1"/>' for p in sources)
    file_xml+='\n<File path="src/keyboard_axis.cst" type="file.cst" enable="1"/>\n<File path="src/keyboard_axis.sdc" type="file.sdc" enable="1"/>'
    (ROOT/'keyboard_axis.gprj').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE gowin-fpga-project>\n<Project><Template>FPGA</Template><Version>5</Version><Device name="GW5AT-60B" pn="GW5AT-LV60PG484AC1/I0">gw5at60b-002</Device><FileList>\n'+file_xml+'\n</FileList></Project>\n')
    (ROOT/'build.tcl').write_text('open_project {'+(ROOT/'keyboard_axis.gprj').as_posix()+'}\nset_option -top_module KeyboardAxisTop\nset_option -verilog_std v2001\nset_option -use_cpu_as_gpio 1\nadd_file -type gsc {'+(SOURCE/'constraints/surge_svf_sample.gsc').as_posix()+'}\nrun all\nexit\n')
    (ROOT/'sources.json').write_text(json.dumps([p.as_posix() for p in sources],indent=2))
    (ROOT/'reports/model.json').write_text(json.dumps({'passed':True,'keys':32,'midi_range':[48,79],
        'clock_hz':CLOCK_HZ,'sample_rate':CLOCK_HZ/FRAME_CLOCKS,'debounce':'two scans with hysteresis',
        'initialization':'configure all 32 voices before run; silence until a qualified press',
        'events':'hold full snapshot until ready; wait for frame completion before another event',
        'source_calibration':'historical measured 2026-10-29, not a new calibration'},indent=2))
    print('MODEL PASS: 32 key thresholds; C3-G5 profiles; frozen source hashes')


if __name__ == '__main__':
    prepare()
