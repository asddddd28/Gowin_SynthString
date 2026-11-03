"""Freeze HDMI unit simulation assets and exact fixed-point comparison vectors."""
from pathlib import Path
import math
import shutil
from display_model import spectrum,wave_shift,triggered_capture

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT.parent / "reports/synthui-hdmi/sim"
OUT.mkdir(parents=True, exist_ok=True)
(OUT / "hdmi").mkdir(exist_ok=True)
for source in (ROOT / "assets").glob("*.hex"):
    shutil.copyfile(source, OUT / "hdmi" / source.name)
streams=[
    [round(28000*math.sin(math.tau*(i+offset)/32)) for i in range(2304)] for offset in (3,13,25)
]
streams += [[round(128*math.sin(math.tau*(i+9)/32)) for i in range(2304)], [0]*2304, [400]*2304]
streams += [[round(28000*math.sin(math.tau*(i+400)/1600)) for i in range(2304)]]
blocks=[];counts=[];starts=[];previous_peak=0
for stream in streams:
    start,block,triggered=triggered_capture(stream,previous_peak)
    starts.append(start);counts.append(start+256);blocks.append(block);previous_peak=max(map(abs,block))
assert blocks[0]==blocks[1]==blocks[2], 'Phase-shifted input must acquire an identical waveform'
(OUT / "samples.hex").write_text("\n".join(f"{x & 65535:04x}" for samples in streams for x in samples), encoding="utf-8")
(OUT / "input_counts.hex").write_text("\n".join(f"{x:04x}" for x in counts),encoding="utf-8")
(OUT / "trigger_starts.hex").write_text("\n".join(f"{x:04x}" for x in starts),encoding="utf-8")
(OUT / "spectrum.hex").write_text("\n".join(f"{x:02x}" for samples in blocks for x in spectrum(samples)), encoding="utf-8")
(OUT / "waves.hex").write_text("\n".join(f"{(((x<<wave_shift(samples))>>8)&255)^128:02x}" for samples in blocks for x in samples),encoding="utf-8")
sources = [p for p in (ROOT / "rtl").glob("*.v") if p.stem != "SynthHdmiTop"]
sources += list((ROOT / "sim").glob("*.v"))
(OUT / "sources.prj").write_text("\n".join(f'verilog work "{p.as_posix()}"' for p in sources), encoding="utf-8")
(OUT / "run.tcl").write_text("run all\nquit\n", encoding="utf-8")
print(OUT)
