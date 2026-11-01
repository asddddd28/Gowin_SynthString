from pathlib import Path
import random
from studio_model import packet,profile,mix
ROOT=Path(__file__).resolve().parent
base=(ROOT.parent/'keyboard-performance/sim/tb_keyboard_audio.v').read_text()
base=base.replace('packet[0:63]','packet[0:79]').replace('packet_index==63','packet_index==79').replace('uart_byte<62','uart_byte<78')
base=base.replace('packet[2]!=2||packet[3]!=64||packet[63]!=13||packet[62]!=checksum','packet[2]!=3||packet[3]!=80||packet[79]!=13||packet[78]!=checksum')
base=base.replace('dut.enc_cycles!=448','dut.enc_cycles>=1000')
packets=[]
for mode in ['mix','fm','am','ring']:
    patches=profile(60,mode=mode,wave_a=2 if mode=='mix' else 0,wave_b=0,depth=.6,ratio=2,
      attack=1,decay=10,sustain=.6,release=10,mod_attack=3,mod_decay=10,mod_sustain=.3,mod_release=20,gain_b=.3 if mode=='mix' else 0)
    packets.append(packet(1,len(packets)+1,12,patches.to_bytes(64,'little')))
    packets.append(packet(2,len(packets)+1,12,bytes([96])))
    packets.append(packet(3,len(packets)+1,12))
# A checksum failure must not commit. Payload embeds all legacy ASCII commands.
bad=bytearray(packet(1,90,12,b'TP012345678'));bad[-1]^=1;packets.append(bytes(bad))
data=b''.join(packets)
(ROOT/'studio_packets.hex').write_text(''.join(f'{b:02x}\n' for b in data))
base=base.replace(' task wait_frames;',f''' reg [7:0] studio_packets[0:{len(data)-1}];
 reg [511:0] held_profile;
 integer packet_number,byte_number,old_commits;
 task send_packet;
  input integer number;
  begin for(byte_number=0;byte_number<71;byte_number=byte_number+1)send_byte(studio_packets[number*71+byte_number]);end
 endtask
 task wait_frames;''')
extra='''
  $readmemh("studio_packets.hex",studio_packets);
  wait_frames(30);
  for(packet_number=0;packet_number<12;packet_number=packet_number+3)begin
   send_packet(packet_number);wait_frames(3);
   if(dut.ack_status!=0||dut.ack_seq!=packet_number+1)$fatal(1,"patch not acknowledged");
   send_packet(packet_number+1);wait_frames(100);
   if(dut.enc_active_count!=1||dut.enc_delivered!=32'h1000)$fatal(1,"remote note on");
   if(dut.Synth_Inst.Engine_Inst.Store_Inst.mem_mod_envelope[12][34:32]==0)$fatal(1,"mod envelope inactive");
   held_profile=dut.Synth_Inst.Engine_Inst.Store_Inst.mem_profile[12];
   if(packet_number==0)begin
    send_packet(3);wait_frames(3);
    if(dut.Synth_Inst.Engine_Inst.Store_Inst.mem_profile[12]!==held_profile)$fatal(1,"patch changed held voice");
   end
   send_packet(packet_number+2);wait_frames(5);
   if(dut.Synth_Inst.Engine_Inst.Store_Inst.mem_profile[12]!==held_profile)$fatal(1,"note off changed release profile");
   wait_frames(895);
   if(dut.enc_active_count!=0||dut.enc_delivered!=0)$fatal(1,"remote note release");
  end
  old_commits=dut.enc_commits;send_packet(12);wait_frames(3);
  if(dut.enc_commits!=old_commits||dut.ack_status!=1||dut.cnt_test!=0||dut.reg_volume!=6)$fatal(1,"CRC packet altered audio control");
'''
base=base.replace('  $display("PASS keyboard ADC',extra+'  $display("PASS keyboard ADC').replace('cycles=448','Studio dual-envelope cycles=%0d').replace('uart_packets,conversions);','uart_packets,conversions,dut.enc_cycles);')
base=base.replace('[0:19999]','[0:39999]').replace('#500000000','#900000000')
(ROOT/'sim/tb_keyboard_audio.v').write_text(base)
rng=random.Random(729)
vectors=[]
for i in range(400):
    a=rng.randrange(-2**26,2**26);b=rng.randrange(-2**26,2**26);d=rng.randrange(2**26+1)
    mode=i%3;ga=rng.randrange(65536);gb=rng.randrange(65536-ga);blend=i%2
    x=(a&0xffffffff)|((b&0xffffffff)<<32)|(d<<64)|(mode<<96)|(blend<<98)|(ga<<99)|(gb<<115)
    expected=((((a*((2**26-((d-((d*b)>>26))>>1)) if mode==1 else (2**26-d+((d*b)>>26)) if mode==2 else 2**26))>>26)*ga)+(b*gb if blend else 0))>>16
    vectors.append(f'{x:034x}{expected&0xffffffff:08x}\n')
(ROOT/'mix_vectors.hex').write_text(''.join(vectors))
print('Prepared real UART + full audio integration and 400 mixer vectors')
