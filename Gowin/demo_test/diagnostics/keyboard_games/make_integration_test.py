"""Extend the established UART/ADC regression with autonomous game telemetry."""
import sys
from pathlib import Path
root=Path(__file__).resolve().parent
sys.path.insert(0,str(root.parents[1]/'desktop'))
from board_protocol import command,GAME_START,GAME_STOP
source=(root.parent/'keyboard_reactive/sim/tb_keyboard_reactive.v').read_text()
source=source.replace('tb_keyboard_reactive','tb_keyboard_games').replace('KeyboardReactive #','KeyboardGames #')
source=source.replace('vectors[0:50]','vectors[0:54]').replace('line_bytes[0:22]','line_bytes[0:36]')
source=source.replace('reg [71:0] status_payload;', 'reg [71:0] status_payload;\nreg [127:0] game_payload=0;\ninteger game_count=0,play_key,wrong_key;')
source=source.replace('else if(rx_byte==64)line_len=23;', 'else if(rx_byte==64)line_len=23;else if(rx_byte==35)line_len=37;')
source=source.replace('end else begin\n   status_payload=0;', 'end else if(line_len==23)begin\n   status_payload=0;')
source=source.replace('ack_count=ack_count+1;end\n  end', '''ack_count=ack_count+1;end
  end else begin
   game_payload=0;
   for(checks=1;checks<=32;checks=checks+1)game_payload={game_payload[123:0],nibble(line_bytes[checks])};
   crc=0;for(checks=15;checks>=0;checks=checks-1)crc=crc_byte(crc,game_payload>>(checks*8));
   if(line_bytes[33]!=42 || crc!={nibble(line_bytes[34]),nibble(line_bytes[35])})begin $display("FAIL game CRC");$finish;end
   game_count=game_count+1;
  end''')
source=source.replace(' @(negedge cs);#150;rstn=0;', '''
 transact(51,0);transact(52,0);transact(53,3);
 wait(game_payload[119:112]==2);
 if(game_payload[127:120]!=3 || game_payload[71:64]!=1)begin $display("FAIL game start/idempotent epoch");$finish;end
 play_key=24;
 for(i=24;i<32;i=i+1)if(game_payload[i*2+:2]==1)play_key=i;
 raw[play_key]=900;
 wait(game_payload[95:80]==1);
 raw[play_key]=100;wait_mask(0);
 wrong_key=24;
 for(i=24;i<32;i=i+1)if(game_payload[i*2+:2]==0)wrong_key=i;
 raw[wrong_key]=900;
 wait(game_payload[119:112]==3);
 if(game_payload[103:96]!=3 || game_payload[95:80]!=1)begin $display("FAIL ADC piano wrong-key result");$finish;end
 raw[wrong_key]=100;
 transact(54,0);
 if(last_mode!=8'h20)begin $display("FAIL game stop restores normal effect");$finish;end
 wait(game_payload[119:112]==0);
 if(game_count<10)begin $display("FAIL missing game telemetry");$finish;end
 $display("PASS games over real UART framing: CRC128, start, duplicate epoch, invalid game, ADC calibrated bottom-key hit, wrong-key game over, stop restores effect; game_frames=%0d",game_count);
 @(negedge cs);#150;rstn=0;''')
source=source.replace('#100000000;','#1000000000;')
(root/'sim/tb_keyboard_games.v').write_text(source,encoding='utf-8')
vectors=(root.parent/'keyboard_reactive/sim/command_vectors.hex').read_text().splitlines()
vectors += [command(49,GAME_START,key=3).hex(),command(49,GAME_START,key=3).hex(),command(50,GAME_START,key=4).hex(),command(51,GAME_STOP,mode=2).hex()]
(root/'sim/command_vectors.hex').write_text('\n'.join(vectors)+'\n')
