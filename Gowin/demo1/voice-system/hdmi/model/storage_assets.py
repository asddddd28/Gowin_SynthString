"""Small ROM for autonomous SD display text. No framebuffer or pixel changes."""
from pathlib import Path
lines=[
 '', 'SD WORKING - PLEASE WAIT', 'OPERATION FAILED', 'SD CARD INITIALIZING',
 'CATALOG NOT READY','SCANNING NUMBERED FILES','SD LIBRARY READY',
 'SEQUENCE 00000000.SSQ','PRESET   00000000.SSP','FILES 000  DEST SLOT 0',
 'RECORDING / OVERDUB','LOOP PLAYING','LOOP STOPPED','BPM 000',
 'UNSAVED LOOP: SW3 SAVE FIRST','CURRENT LOOP HAS NO UNSAVED EDIT',
 'SW3 SAVE NEXT / SW2 CLEAR RAM','PRESS AGAIN TO DELETE THIS FILE',
 'SAVE OR CLEAR BEFORE REPLACING','ERROR 0X00','SEQUENCE LIBRARY','PRESET LIBRARY',
 'STANDALONE / APP NOT REQUIRED','SW5 / SW6 LOAD PREVIOUS / NEXT',
 'E2 DELETE / PRESS TWICE','PRESS JOYSTICK TO LOAD','E1 SELECTS DESTINATION SLOT','SLOT 0',
]
assert all(len(line)<=32 for line in lines)
out=Path(__file__).resolve().parents[1]/'assets/storage-lines.hex'
data=b''.join(line.ljust(32).encode('ascii') for line in lines).ljust(1024,b' ')
out.write_text('\n'.join(f'{x:02x}' for x in data)+'\n')
print(out)
