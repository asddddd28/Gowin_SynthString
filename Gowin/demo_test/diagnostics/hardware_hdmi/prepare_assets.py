"""Generate deterministic display ROMs and the isolated Gowin project; no hardware access."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
for folder in ('src', 'vendor', 'spec', 'sim', 'reports'):
    (ROOT / folder).mkdir(exist_ok=True)

# Own 5x7 bitmap alphabet; no external font license or runtime dependencies.
FONT = {
'A':['01110','10001','10001','11111','10001','10001','10001'],
'B':['11110','10001','10001','11110','10001','10001','11110'],
'C':['01111','10000','10000','10000','10000','10000','01111'],
'D':['11110','10001','10001','10001','10001','10001','11110'],
'E':['11111','10000','10000','11110','10000','10000','11111'],
'F':['11111','10000','10000','11110','10000','10000','10000'],
'G':['01111','10000','10000','10111','10001','10001','01111'],
'H':['10001','10001','10001','11111','10001','10001','10001'],
'I':['11111','00100','00100','00100','00100','00100','11111'],
'J':['00111','00010','00010','00010','10010','10010','01100'],
'K':['10001','10010','10100','11000','10100','10010','10001'],
'L':['10000','10000','10000','10000','10000','10000','11111'],
'M':['10001','11011','10101','10101','10001','10001','10001'],
'N':['10001','11001','10101','10011','10001','10001','10001'],
'O':['01110','10001','10001','10001','10001','10001','01110'],
'P':['11110','10001','10001','11110','10000','10000','10000'],
'Q':['01110','10001','10001','10001','10101','10010','01101'],
'R':['11110','10001','10001','11110','10100','10010','10001'],
'S':['01111','10000','10000','01110','00001','00001','11110'],
'T':['11111','00100','00100','00100','00100','00100','00100'],
'U':['10001','10001','10001','10001','10001','10001','01110'],
'V':['10001','10001','10001','10001','10001','01010','00100'],
'W':['10001','10001','10001','10101','10101','10101','01010'],
'X':['10001','10001','01010','00100','01010','10001','10001'],
'Y':['10001','10001','01010','00100','00100','00100','00100'],
'Z':['11111','00001','00010','00100','01000','10000','11111'],
'0':['01110','10001','10011','10101','11001','10001','01110'],
'1':['00100','01100','00100','00100','00100','00100','01110'],
'2':['01110','10001','00001','00010','00100','01000','11111'],
'3':['11110','00001','00001','01110','00001','00001','11110'],
'4':['00010','00110','01010','10010','11111','00010','00010'],
'5':['11111','10000','10000','11110','00001','00001','11110'],
'6':['01110','10000','10000','11110','10001','10001','01110'],
'7':['11111','00001','00010','00100','01000','01000','01000'],
'8':['01110','10001','10001','01110','10001','10001','01110'],
'9':['01110','10001','10001','01111','00001','00001','01110'],
'-':['00000','00000','00000','11111','00000','00000','00000'],
':':['00000','00100','00100','00000','00100','00100','00000'],
'/':['00001','00010','00010','00100','01000','01000','10000'],
'.':['00000','00000','00000','00000','00000','00100','00100'],
'+':['00000','00100','00100','11111','00100','00100','00000'],
}

canvas = [' '] * 4096
def text(x, y, s):
    assert x + len(s) <= 80
    canvas[y * 80 + x:y * 80 + x + len(s)] = s
text(2, 2, 'TANG / HARDWARE LAB')
text(2, 4, 'PURE FPGA   /   LIVE HARDWARE MONITOR')
text(61, 2, '1280 X 720')
text(61, 4, 'VIDEO 59.26 HZ')
text(2, 7, 'KEYBOARD / 32 KEYS')
text(54, 7, 'ENCODERS / HEX COUNT')
for k in range(32):
    x, y = 3 + 6*(k%8), 10+4*(k//8)
    text(x, y, f'K{k+1:02d}')
for k in range(5):
    text(55, 10+3*k, f'E{k+1}   0000')
text(2, 26, 'DUAL TOUCHPADS')
text(27, 26, 'JOYSTICK')
text(44, 26, 'KEY 01 ADC TRACE')
text(4, 40, 'LEFT')
text(14, 40, 'RIGHT')
text(44, 40, '6.4 SEC / 0-4095')
text(2, 43, 'CAL: -   FX: -   LINK: -   VALUES: HEX')
text(54, 43, 'TANG MEGA 60K / NO CPU')
(ROOT/'src/layout.hex').write_text('\n'.join(f'{ord(c):02x}' for c in canvas)+'\n')

fontcase = '\n'.join(f"            8'd{ord(c)}: dec_glyph = 35'b{''.join(rows)};" for c, rows in FONT.items())
(ROOT/'src/DashboardFont.v').write_text('''`timescale 1ns / 1ps
// DashboardFont: original 5x7 uppercase font, registered bitmap lookup.
// Contract: spec/DashboardFont_spec.md. One pixel clock latency.
module DashboardFont(input i_clk, input [7:0] i_character, output [34:0] o_glyph);
    reg [34:0] dec_glyph;
    reg [34:0] reg_glyph_o;
    assign o_glyph = reg_glyph_o;
    always @(*) begin
        dec_glyph = 35'd0;
        case (i_character)
'''+fontcase+'''
            default: dec_glyph = 35'd0;
        endcase
    end
    always @(posedge i_clk) begin
        reg_glyph_o <= dec_glyph;
    end
endmodule
''')

base = ROOT.parent/'hardware_lab'
project = ET.parse(base/'hardware_lab.gprj')
files = project.getroot().find('FileList')
for f in list(files):
    if f.attrib['type'] in ('file.cst','file.sdc'):
        files.remove(f)
    elif f.attrib['path'].startswith('src/'):
        f.set('path', '../hardware_lab/'+f.attrib['path'])
for name in ['HardwareHdmi','DashboardTelemetry','DashboardVideo','DashboardFont']:
    ET.SubElement(files,'File',path=f'src/{name}.v',type='file.verilog',enable='1')
for name in ['TMDS_PLL','DVI_TX_Top']:
    ET.SubElement(files,'File',path=f'vendor/{name}.v',type='file.verilog',enable='1')
for ext in ['cst','sdc']:
    ET.SubElement(files,'File',path=f'src/hdmi.{ext}',type=f'file.{ext}',enable='1')
project.write(ROOT/'hardware_hdmi.gprj',encoding='UTF-8',xml_declaration=True)
reference = ROOT.parents[2]/'reference/TangMega-60K-example-main/cam_dvi/src'
(ROOT/'vendor/TMDS_PLL.v').write_bytes((reference/'gowin_pll/TMDS_PLL_60HZ.v').read_bytes())
(ROOT/'vendor/DVI_TX_Top.v').write_bytes((reference/'dvi_tx/DVI_TX_Top.v').read_bytes())
(ROOT/'src/hdmi.cst').write_text((base/'src/hardware.cst').read_text()+'''
IO_LOC "tmds_d_p_0[0]" J14,H14;
IO_PORT "tmds_d_p_0[0]" PULL_MODE=NONE DRIVE=3.5 BANK_VCCIO=3.3;
IO_LOC "tmds_d_p_0[1]" J15,H15;
IO_PORT "tmds_d_p_0[1]" PULL_MODE=NONE DRIVE=3.5 BANK_VCCIO=3.3;
IO_LOC "tmds_d_p_0[2]" K17,J17;
IO_PORT "tmds_d_p_0[2]" PULL_MODE=NONE DRIVE=3.5 BANK_VCCIO=3.3;
IO_LOC "tmds_clk_p_0" G15,G16;
IO_PORT "tmds_clk_p_0" PULL_MODE=NONE DRIVE=3.5 BANK_VCCIO=3.3;
IO_LOC "hpd_en" K13;
IO_PORT "hpd_en" PULL_MODE=UP DRIVE=12 BANK_VCCIO=3.3;
INS_LOC "u_tmds_pll/PLLA_inst" PLL_R[0];
''')
(ROOT/'src/hdmi.sdc').write_text('''create_clock -name clk -period 20.000 [get_ports {i_clk}]
# Match actual reference PLL: 50 MHz *22 /3 and /15; pixel and serial are RELATED.
create_generated_clock -name serial_clk -source [get_ports {i_clk}] -master_clock clk -divide_by 3 -multiply_by 22 [get_pins {u_tmds_pll/PLLA_inst/CLKOUT0}]
create_generated_clock -name pixel_clk -source [get_ports {i_clk}] -master_clock clk -divide_by 15 -multiply_by 22 [get_pins {u_tmds_pll/PLLA_inst/CLKOUT1}]
# UART observation is the only data crossing; UartRx contains a two-flop synchronizer.
set_clock_groups -asynchronous -group [get_clocks {clk}] -group [get_clocks {pixel_clk serial_clk}]
''')
(ROOT/'build.tcl').write_text(f'''open_project {{{(ROOT/'hardware_hdmi.gprj').as_posix()}}}
set_option -top_module HardwareHdmi
set_option -verilog_std v2001
set_option -use_cpu_as_gpio 1
set_option -include_path {{{(ROOT.parent/'touchpad/vendor').as_posix()}}}
run all
exit
''')

# Freeze requirements, decomposition, and executable reference expectations before RTL.
contract = {'resolution':[1280,720], 'total':[1650,750], 'pixel_hz':73333333.333333,
 'serial_hz':366666666.666667, 'fps':59.2592592593, 'softcore':False,
 'source':'read-only internal UART observer at 115200 8N1', 'original_rtl_modified':False,
 'graphics':['32 key ADC hex values and pressed mask','5 signed counts shown as 16-bit hex',
 'two transposed 5x7 touch grids','joystick raw direction and switch','64 samples of K01 ADC, not audio'],
 'verification':['parser known and malformed frames','one full frame sync and active-pixel counts',
 'RTL frame capture','Gowin synthesis/PnR timing','SRAM download','user confirms actual screen']}
(ROOT/'spec/requirements.json').write_text(json.dumps(contract,indent=2))
modules = {
 'HardwareHdmi': 'Unchanged HardwareLab at 50 MHz; reference TMDS_PLL and DVI_TX_Top. Dashboard reset asynchronously asserts on key reset or PLL unlock and releases after 3 pixel clocks. Vendor DVI IP separately uses its documented asynchronous reset, key reset AND PLL lock, as in the official example. HPD enable stays high. No CPU, DDR or framebuffer.',
 'DashboardTelemetry': 'Pixel-domain UART byte parser. One complete line commits values at LF, except key bank writes commit one additional cycle later through registered address/data; invalid length/CR/hex drops the line. Serial input synchronized by existing UartRx. Local trusted TX source: CRC fields are NOT rechecked. 1 s without a recognized frame clears live; no writes to HardwareLab.',
 'DashboardVideo': '1650x750 raster, 1280x720 active; +HS 1390..1429, +VS 725..729. Three-cycle pixel/sync pipeline. Snapshot all live state on vertical blank to avoid tearing. 64-entry K01 ADC history, one entry per K01 line, rendered at 8 px/sample. 16x16 text cells, 5x7 doubled glyphs. Telemetry/renderer share pixel clock.',
 'DashboardFont': 'Synchronous original 5x7 uppercase ASCII bitmap lookup; one clock latency; unsupported character is blank.'}
for module, description in modules.items():
    (ROOT/f'spec/{module}_spec.md').write_text(f'# {module}\n\n{description}\n\nReset is active low where present. Video never backpressures telemetry.\n\n```wavedrom\n'+json.dumps({'signal':[{'name':'clk','wave':'p....'},{'name':'input','wave':'x=...','data':['A']},{'name':'registered','wave':'x.=..','data':['A']}]})+'\n```\n',encoding='utf-8')
(ROOT/'spec/semantic_model.py').write_text('''"""Reference raster and telemetry field checks, independent of RTL."""
def raster(x,y):
    return x<1280 and y<720, 1390<=x<1430, 725<=y<730
assert sum(raster(x,0)[0] for x in range(1650)) == 1280
assert sum(raster(x,0)[1] for x in range(1650)) == 40
assert sum(raster(0,y)[2] for y in range(750)) == 5
assert abs(50_000_000*22/15/1650/750-59.2592592593)<1e-6
def key(line):
    assert len(line)==9 and line[0]=="K" and line[3]==":" and line[-2:]=="\\r\\n"
    return int(line[1:3])-1,int(line[4:7],16)
assert key("K32:ABC\\r\\n")== (31,2748)
print("PASS semantic model")
''')
print(ROOT)
