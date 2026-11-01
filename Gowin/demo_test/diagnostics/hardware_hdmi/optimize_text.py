"""Replace coordinate division with fixed text-cell decode to shorten pixel path."""
from pathlib import Path
p=Path(__file__).parent/'src/DashboardVideo.v'
s=p.read_text(encoding='utf-8')
start=s.index('        if(dec_column>=3 && dec_column<49')
end=s.index('        if(cnt_x>=848',start)
cases=['        // Fixed cells eliminate coordinate division from the pixel critical path.','        case ({dec_row,dec_column})']
for key in range(32):
    row=11+(key//8)*4
    for digit in range(3):
        col=3+(key%8)*6+digit
        lo=key*12+(2-digit)*4
        cases.append(f"            13'd{row*128+col}: begin dec_character=hex_character(reg_keys[{lo+3}:{lo}]); flag_override=1; end")
cases+=['            default: begin end','        endcase','']
s=s[:start]+'\n'.join(cases)+s[end:]
s=s.replace('    integer dec_tile_column, dec_tile_row, dec_key;\n','').replace('    reg [11:0] dec_adc;\n','')
s=s.replace('        dec_tile_column=0; dec_tile_row=0; dec_key=0; dec_adc=0; dec_encoder=0;','        dec_encoder=0;')
p.write_text(s,encoding='utf-8')
