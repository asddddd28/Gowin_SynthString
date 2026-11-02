"""Independent integer reference and pin-level integration regression cases."""
from pathlib import Path
import math,random,json
ROOT=Path(__file__).resolve().parent
tb=(ROOT.parent/'keyboard-axis/sim/tb_keyboard_audio.v').read_text()
tb=tb.replace('packet[0:31]','packet[0:63]').replace('packet_index==31','packet_index==63').replace('uart_byte<30','uart_byte<62').replace('packet[2]!=1','packet[2]!=2').replace('packet[3]!=32','packet[3]!=64').replace('packet[31]!=13','packet[63]!=13').replace('packet[30]!=checksum','packet[62]!=checksum')
tb=tb.replace('for(k=0;k<32;k=k+1)raw[k]=rest[k];\n  wait_frames(180);', '''for(k=0;k<32;k=k+1)raw[k]=bottom[k];
  wait_frames(700);
  if(dut.enc_pressed!==32'hffffffff||dut.enc_active_count!=32)$fatal(1,"32 simultaneous physical voices");
  if(dut.enc_stages!=127||dut.enc_env_peak==0||dut.enc_wave_peak==0||dut.enc_mod_peak==0)$fatal(1,"missing accepted pipeline stage activity");
  if(dut.enc_clips!=0)$fatal(1,"musical chord unexpectedly clipped");
  for(k=0;k<32;k=k+1)raw[k]=rest[k];
  wait_frames(180);
  if(dut.enc_active_count==0)$fatal(1,"release voices excluded from normalization");''')
tb=tb.replace('dut.enc_events!=6','dut.enc_events!=64').replace('wait_frames(6000)','wait_frames(10000)')
(ROOT/'sim/tb_keyboard_audio.v').write_text(tb)
rng=random.Random(91);gain=0;rows=[];clipped=0
for active,volume,count in [(1,8,22000),(32,8,1500),(4,8,12000),(0,0,2000),(2,4,18000)]:
    target=math.floor(4*65536/math.sqrt(max(active,1)))*volume//8
    for j in range(count):
        sample=rng.choice([0,8388607,-8388608,128,-128,rng.randrange(-8388608,8388608)])
        value=(abs(sample*gain)+32768)//65536
        if value>0x700000:clipped+=1
        expected=min(value,0x700000)*(-1 if sample<0 else 1)
        rows.append(f'{active:x} {volume:x} {sample&0xffffff:06x} {expected&0xffffff:06x} {gain:x} {clipped:x}')
        if gain>target:gain-=(gain-target+63)//64
        elif gain<target:gain+=(target-gain+4095)//4096
assert gain>0 and clipped>0
(ROOT/'loudness_vectors.txt').write_text('\n'.join(rows)+'\n')
(ROOT/'reports/loudness_cases.json').write_text(json.dumps({'samples':len(rows),'clip_events_expected':clipped,'cases':'positive/negative full scale, random signed PCM, 1/32/4/0/2 active envelope counts, volume 8/0/4, exact mute, saturation and smoothing'},indent=2))
print('Generated',len(rows),'loudness reference samples and expanded ADC-to-DAC test')
