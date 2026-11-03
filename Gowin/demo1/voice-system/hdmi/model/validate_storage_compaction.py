"""在独立工作目录重跑显示和真实 I2C 总线回归，保留原有证据。"""
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / 'reports/resource-preserving'
TOOLS = Path('D:/Xilinx/2025.1/Vivado/bin')
DIAGNOSTICS = ROOT.parents[1] / 'demo_test/diagnostics'


def run(work, top, sources):
    work.mkdir(parents=True, exist_ok=True)
    (work / 'sources.prj').write_text('\n'.join(f'verilog work "{p.as_posix()}"' for p in sources), encoding='utf-8')
    (work / 'run.tcl').write_text('run all\nquit\n', encoding='utf-8')
    with (REPORT / f'{top}.log').open('w', encoding='utf-8') as log:
        for tool, args in [
            ('xvlog', ['-i', str(DIAGNOSTICS/'touchpad/vendor'), '-prj', 'sources.prj']),
            ('xelab', [top, '-s', top+'_sim']),
            ('xsim', [top+'_sim', '-tclbatch', 'run.tcl']),
        ]:
            subprocess.run([str(TOOLS/(tool+'.bat')), *args], cwd=work, stdout=log,
                           stderr=subprocess.STDOUT, timeout=240, check=True)
    text = (REPORT / f'{top}.log').read_text(encoding='utf-8', errors='replace')
    assert 'PASS' in text and 'Fatal:' not in text and 'ERROR:' not in text, top
    print('PASS', top, flush=True)


if __name__ == '__main__':
    if '--mpr' in sys.argv:
        sources = list((DIAGNOSTICS/'touchpad/vendor').glob('i2c_master_*ctrl.v'))
        sources += [DIAGNOSTICS/'encoder/src/EncoderUartTx.v', DIAGNOSTICS/'touchpad/src/I2cRegister.v']
        sources += list((DIAGNOSTICS/'touchpad_guitar/src').glob('*.v'))
        sources += [DIAGNOSTICS/'touchpad_guitar/sim/tb_touchpad_guitar.v']
        run(REPORT/'mpr-sim', 'tb_touchpad_guitar', sources)
    else:
        work = REPORT/'display-sim'
        # Existing reference vectors preserve the phase-locked waveform, quiet
        # signal auto-range, all 64 DFT bins and cross-clock publication tests.
        work.mkdir(exist_ok=True)
        for source in (ROOT/'reports/synthui-hdmi/sim').glob('*.hex'):
            shutil.copyfile(source, work/source.name)
        shutil.copytree(ROOT/'hdmi/assets', work/'hdmi', dirs_exist_ok=True)
        sources = [p for p in (ROOT/'hdmi/rtl').glob('*.v') if p.stem != 'SynthHdmiTop']
        sources += list((ROOT/'hdmi/sim').glob('*.v'))
        for top in ('tb_display_audio', 'tb_display_control', 'tb_display_video'):
            run(work, top, sources)
