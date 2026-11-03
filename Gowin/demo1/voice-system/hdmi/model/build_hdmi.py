"""Create an isolated 50 MHz audio / 73.333 MHz video candidate, never flash."""
from pathlib import Path
import hashlib
import json
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
SYSTEM = ROOT.parent
WORK = SYSTEM.parents[1]
OUT = SYSTEM / "reports/synthui-hdmi" / (sys.argv[1] if len(sys.argv) > 1 else "build")
OUT.mkdir(parents=True, exist_ok=True)
reference = WORK / "demo_test/diagnostics/hardware_hdmi"
sources = [Path(x) for x in (SYSTEM / "sources.f").read_text(encoding="utf-8").splitlines() if x.strip()]
sources += list((ROOT / "rtl").glob("*.v")) + list((reference / "vendor").glob("*.v"))
files = []
manifest = []
for source in sources:
    dest = OUT / "snapshot" / source.relative_to(WORK)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
    # OpenCores I2C includes travel with the isolated source snapshot.
    if source.name.startswith("i2c_master_"):
        for header in ("i2c_master_defines.v", "timescale.v"):
            shutil.copyfile(source.parent / header, dest.parent / header)
            manifest.append({"path":str(source.parent/header),"sha256":hashlib.sha256((source.parent/header).read_bytes()).hexdigest()})
    manifest.append({"path":str(source),"sha256":hashlib.sha256(source.read_bytes()).hexdigest()})
    files.append(f'<File path="{dest.as_posix()}" type="file.verilog" enable="1"/>')
pins = (SYSTEM / "system.cst").read_text(encoding="utf-8")
lines = (reference / "src/hdmi.cst").read_text(encoding="utf-8").splitlines()
display_pins=[x for x in lines if any(n in x for n in ('"tmds_', '"hpd_en"', '"u_tmds_pll/', '"i_encoder_', '"i_joystick', '"i_buttons'))]
# Preserve electrical H/L ordering. RTL decodes comparator pairs as three
# regions; swapping individual H/L pins is not a valid direction inversion.
pins += "\n" + "\n".join(display_pins)
pins += "\n" + (ROOT / "touch.cst").read_text(encoding="utf-8")
pins += "\n" + (ROOT / "rgb.cst").read_text(encoding="utf-8")
pins += "\n" + (SYSTEM / "storage/sd.cst").read_text(encoding="utf-8")
(OUT / "hdmi.cst").write_text(pins, encoding="utf-8")
sdc = (reference / "src/hdmi.sdc").read_text(encoding="utf-8").replace("# UART observation is the only data crossing; UartRx contains a two-flop synchronizer.", "# Toggle handshakes hold status/sample banks; metadata uses dual-clock RAM.")
(OUT / "hdmi.sdc").write_text(sdc, encoding="utf-8")
for name in ("hdmi.cst", "hdmi.sdc"):
    files.append(f'<File path="{(OUT/name).as_posix()}" type="file.{Path(name).suffix[1:]}" enable="1"/>')
assets = [(p,OUT / p.relative_to(SYSTEM)) for p in (SYSTEM / "rom").glob("*.hex")]
assets += [(SYSTEM / p,OUT / p) for p in ("key_thresholds.hex", "raw_rest.hex", "raw_bottom.hex")]
assets += [(p,OUT / "hdmi" / p.name) for p in (ROOT / "assets").glob("*.hex")]
for source,dest in assets:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source,dest)
    manifest.append({"path":str(source),"sha256":hashlib.sha256(source.read_bytes()).hexdigest()})
project=OUT / "synth_hdmi.gprj"
project.write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Project><Template>FPGA</Template><Version>5</Version>\n<Device name="GW5AT-60B" pn="GW5AT-LV60PG484AC1/I0">gw5at60b-002</Device>\n<FileList>\n'+"\n".join(files)+'\n</FileList></Project>\n',encoding="utf-8")
(OUT / "build.tcl").write_text(f'open_project {{{project.as_posix()}}}\nset_option -top_module SynthHdmiTop\nset_option -verilog_std v2001\nset_option -use_cpu_as_gpio 1\nset_option -global_freq 50\nset_option -convert_sdp32_36_to_sdp16_18 1\nrun all\nexit\n',encoding="utf-8")
(OUT / "inputs.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
print(OUT)
