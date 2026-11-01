from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parent;BIN=Path('D:/Xilinx/2025.1/Vivado/bin')
name=sys.argv[1] if len(sys.argv)>1 else 'studio_mixer'
for tool,args in [('xvlog',[str(ROOT.parent/'rtl/axis/AxisFixedCore.v'),str(ROOT/'src/StudioOscMixer.v'),str(ROOT/'src/StudioControl.v'),str(ROOT/'sim'/f'tb_{name}.v')]),('xelab',['work.tb_'+name,'-s',name]),('xsim',[name,'-runall'])]:
 p=ROOT/'reports'/f'{name}_{tool}.log'
 with p.open('w') as f:r=subprocess.run(subprocess.list2cmdline([str(BIN/(tool+'.bat')),*args]),shell=True,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 text=p.read_text(errors='replace')
 if r.returncode or 'ERROR:' in text or 'Fatal:' in text:print(text[-4000:]);raise SystemExit(1)
print(text[-1000:])
assert 'PASS' in text
