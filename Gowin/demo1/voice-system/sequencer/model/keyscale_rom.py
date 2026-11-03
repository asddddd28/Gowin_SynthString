"""Fold the constant 329 into the DX keyboard curve ROM, without rounding changes."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ENGINE=ROOT.parent/'voice-engine'
curve=[int(x,16) for x in (ENGINE/'rom/dx_keyscale.hex').read_text().split()]
table=[(curve[min(i,32)]&511)*329 for i in range(64)]+[(i*8)*329 for i in range(64)]
assert max(table)<1<<18
for group in range(64):
    for shape in range(4):
        for depth in range(128):
            base=group*8 if shape in (0,3) else curve[min(group,32)]&511
            old=(base*depth*329)>>15
            new=(table[group+64*int(shape in (0,3))]*depth)>>15
            assert old==new
text=''.join(f'{v:05x}\n' for v in table)
for folder in (ENGINE/'rom',ROOT/'rom'):(folder/'dx_keyscale_product.hex').write_text(text)
print('PASS all 32768 group/curve/depth combinations: keyscale multiplication is exact')
