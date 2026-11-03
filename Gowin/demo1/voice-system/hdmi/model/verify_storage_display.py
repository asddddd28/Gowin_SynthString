"""Check the autonomous text renderer independently of the HDMI serializer."""
from pathlib import Path
import subprocess,shutil,json
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'reports/storage-integration/display-sim';OUT.mkdir(parents=True,exist_ok=True)
(OUT/'hdmi').mkdir(exist_ok=True)
shutil.copyfile(ROOT/'hdmi/assets/storage-lines.hex',OUT/'hdmi/storage-lines.hex')
(OUT/'run.tcl').write_text('run all\nquit\n')
TOOLS=Path('D:/Xilinx/2025.1/Vivado/bin')
result={'ok':False}
try:
    for tool,args in [('xvlog',[str(ROOT/'hdmi/rtl/SynthStorageDisplay.v'),str(ROOT/'hdmi/sim/tb_storage_display.v')]),('xelab',['tb_storage_display','-s','storage_display']),('xsim',['storage_display','-tclbatch','run.tcl'])]:
        run=subprocess.run([str(TOOLS/(tool+'.bat')),*args],cwd=OUT,capture_output=True,text=True,errors='replace',timeout=120)
        log=run.stdout+run.stderr;(OUT/(tool+'-console.log')).write_text(log,encoding='utf-8')
        if run.returncode or 'FATAL' in log.upper() or 'ERROR:' in log:raise RuntimeError(log[-3000:])
        print(tool,'PASS',flush=True)
    assert 'PASS storage display' in log;result['ok']=True
finally:(OUT/'result.json').write_text(json.dumps(result,indent=2))
