"""在原键盘全功能台架上加入并发外设与混合串口解码。"""
from pathlib import Path
root=Path(__file__).resolve().parent
t=(root.parent/'keyboard_games/sim/tb_keyboard_games.v').read_text(encoding='utf8')
t=t.replace('module tb_keyboard_games;','module tb_hardware_lab;').replace('dut.','dut.keyboard.')
t=t.replace('line_bytes[0:36]','line_bytes[0:99]')
t=t.replace('KeyboardGames #(.C_SETTLE_CYCLES(30),.C_HALF_CYCLES(6),.C_UART_CYCLES(16),.C_FRAME_CYCLES(65000)) dut(','''HardwareLab #(.C_SETTLE_CYCLES(30),.C_UART_CYCLES(16),.C_FRAME_CYCLES(65000),
 .C_KEY_REPORT(200000),.C_ENCODER_REPORT(300000),.C_JOY_REPORT(150000),.C_TOUCH_REPORT(100000),.C_ID_REPORT(400000),
 .C_ENCODER_FILTER(3),.C_JOY_FILTER(10),.C_I2C_DIVIDER(4),.C_TOUCH_BOOT(100),.C_TOUCH_RETRY(5000),.C_TOUCH_RESET(200),.C_TOUCH_TIMEOUT(100000)) dut(''')
t=t.replace('.o_uart_tx(tx),.o_rgb(rgb));',".o_uart_tx(tx),.o_rgb(rgb),.i_encoder_a(encoder_a),.i_encoder_b(encoder_b),.i_joystick(joystick),.i_irq(2'b11),.io_scl(pad_scl),.io_sda(pad_sda));")
t=t.replace('reg clk=0,rstn=0,dout=0,rx=1;', '''reg clk=0,rstn=0,dout=0,rx=1;
reg [4:0] encoder_a=31,encoder_b=31,joystick=16;
tri1 [1:0] pad_scl,pad_sda;
wire [31:0] reads_left,reads_right;
integer output_file;
initial output_file=$fopen("all_uart.bin","wb");
MprBehavior left_pad(pad_scl[0],pad_sda[0],1'b1,reads_left);
MprBehavior right_pad(pad_scl[1],pad_sda[1],1'b1,reads_right);''')
t=t.replace('  else begin $display("FAIL line prefix %h",rx_byte);$finish;end', '''  else if(rx_byte==69)line_len=34;
  else if(rx_byte==74)line_len=21;
  else if(rx_byte==84)line_len=100;
  else if(rx_byte==71)line_len=37;
  else if(rx_byte==72)line_len=15;
  else begin $display("FAIL line prefix %h",rx_byte);$finish;end''')
t=t.replace(' line_bytes[byte_index]=rx_byte;',' line_bytes[byte_index]=rx_byte;\n $fwrite(output_file,"%c",rx_byte);')
t=t.replace('  end else begin\n   game_payload=0;', '  end else if(line_bytes[0]==35)begin\n   game_payload=0;')
t=t.replace(' #101;rstn=1;', ' #101;rstn=1;\n wait(dut.resetn);repeat(4)@(negedge clk);')
t=t.replace('timeout_count<100000','timeout_count<600000').replace('timeout_count<400000','timeout_count<1500000')
t=t.replace(' // Exactly one outlying sample cannot trigger a key.', ''' // Concurrent encoders, joystick and dual-pad events while calibrated keyboard commands continue.
 encoder_a=0;#1000;encoder_b=0;#1000;encoder_a=31;#1000;encoder_b=31;
 joystick=0;#2000;joystick=16;
 wait(dut.touchpad.left_sequence>3 && dut.touchpad.right_sequence>3);
 left_pad.memory[0]=8'h10;left_pad.memory[1]=1;
 right_pad.memory[0]=8'h10;right_pad.memory[1]=1;
 #2000000;
 // Exactly one outlying sample cannot trigger a key.''')
t=t.replace(' @(negedge cs);#150;rstn=0;', ' $fclose(output_file);\n @(negedge cs);#150;rstn=0;')
pad=(root.parent/'touchpad/sim/tb_touchpad.v').read_text(encoding='utf8').split('module tb_touchpad;')[0]
(root/'sim/tb_hardware_lab.v').write_text(pad+t,encoding='utf8')
(root/'sim/command_vectors.hex').write_bytes((root.parent/'keyboard_games/sim/command_vectors.hex').read_bytes())
