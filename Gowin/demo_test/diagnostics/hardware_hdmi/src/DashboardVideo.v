`timescale 1ns / 1ps
// DashboardVideo / 扫描式仪表盘，不使用帧缓冲或 CPU。
// Contract: ../spec/DashboardVideo_spec.md. RGB and sync share three pipeline stages.
module DashboardVideo #(
    parameter C_LAYOUT_FILE = "D:/Projects/ai/Gowin/demo_test/diagnostics/hardware_hdmi/src/layout.hex"
)(
    input i_clk, input i_rstn,
    input [383:0] i_keys, input [79:0] i_encoders, input [4:0] i_joystick,
    input [23:0] i_touch, input [1:0] i_touch_ok, input [31:0] i_pressed,
    input i_configured, input [3:0] i_effect, input i_live,
    input i_key_sample, input [11:0] i_key_value,
    output [23:0] o_rgb, output o_hsync, output o_vsync, output o_de
);
    reg [10:0] cnt_x;
    reg [9:0] cnt_y;
    reg [383:0] reg_keys;
    reg [79:0] reg_encoders;
    reg [4:0] reg_joystick;
    reg [23:0] reg_touch;
    reg [1:0] reg_touch_ok;
    reg [31:0] reg_pressed;
    reg flag_configured, flag_live;
    reg [3:0] reg_effect;
    reg [7:0] mem_layout [0:4095];
    reg [6:0] mem_trace [0:63];
    reg [5:0] cnt_write, reg_trace_origin;
    reg [7:0] reg_layout_a, reg_character_a;
    reg flag_override_a;
    reg [23:0] dec_background, dec_foreground;
    reg [7:0] dec_character;
    reg flag_override;
    reg [23:0] reg_background_a, reg_background_b, reg_foreground_a, reg_foreground_b;
    reg [5:0] reg_glyph_index_a, reg_glyph_index_b;
    reg flag_glyph_a, flag_glyph_b;
    reg [6:0] reg_trace_sample_a, reg_trace_y_a;
    reg flag_trace_a;
    reg [2:0] reg_hsync, reg_vsync, reg_de;
    reg [23:0] reg_rgb_o;
    wire [34:0] bus_glyph;
    wire [6:0] dec_column=cnt_x[10:4];
    wire [5:0] dec_row=cnt_y[9:4];
    wire [11:0] dec_address=dec_row*12'd80 + dec_column;
    wire [5:0] dec_trace_offset=(cnt_x-11'd704)>>3;
    wire [5:0] dec_trace_address=reg_trace_origin+dec_trace_offset;
    integer idx_key, idx_pad, idx_band, idx_encoder;
    integer idx_reset;
    reg [15:0] dec_encoder;
    reg [10:0] dec_stick_x;
    reg [9:0] dec_stick_y;
    assign o_rgb=reg_rgb_o;
    assign o_hsync=reg_hsync[2];
    assign o_vsync=reg_vsync[2];
    assign o_de=reg_de[2];
    initial $readmemh(C_LAYOUT_FILE,mem_layout);

    function [7:0] hex_character;
        input [3:0] nibble;
        begin hex_character=nibble<10 ? 8'd48+nibble : 8'd55+nibble; end
    endfunction

    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin cnt_x<=0; cnt_y<=0; end
        else if(cnt_x==1649) begin
            cnt_x<=0;
            if(cnt_y==749) cnt_y<=0;
            else cnt_y<=cnt_y+1'b1;
        end else cnt_x<=cnt_x+1'b1;
    end
    // Display state changes only during vertical blank; no multi-bit CDC here.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            reg_keys<=0; reg_encoders<=0; reg_joystick<=5'b10101;
            reg_touch<=0; reg_touch_ok<=0; reg_pressed<=0;
            flag_configured<=0; flag_live<=0; reg_effect<=0; reg_trace_origin<=0;
        end else if(cnt_x==0 && cnt_y==720) begin
            reg_keys<=i_keys; reg_encoders<=i_encoders; reg_joystick<=i_joystick;
            reg_touch<=i_touch; reg_touch_ok<=i_touch_ok; reg_pressed<=i_pressed;
            flag_configured<=i_configured; flag_live<=i_live; reg_effect<=i_effect;
            reg_trace_origin<=cnt_write;
        end
    end
    // 12-bit uncalibrated key ADC, reduced to 7-bit plot height. Not audio PCM.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            cnt_write<=0;
            for(idx_reset=0;idx_reset<64;idx_reset=idx_reset+1) mem_trace[idx_reset]<=0;
        end else if(i_key_sample) begin
            mem_trace[cnt_write]<=i_key_value[11:5]; cnt_write<=cnt_write+1'b1;
        end
    end

    // Combinational geometry is bounded to simple rectangles and fixed-size grids.
    always @(*) begin
        dec_background=24'h101820;
        dec_foreground=24'hDAE7EE;
        dec_character=8'd32; flag_override=0;
        dec_encoder=0;
        dec_stick_x=536; dec_stick_y=552;
        if(cnt_y<96) dec_background=24'h172A35;
        if(cnt_y>=94 && cnt_y<97) dec_background=24'h44D7BB;
        if(cnt_y>=680) dec_background=24'h172A35;
        if(dec_row==2) dec_foreground=24'h62E6C4;

        for(idx_key=0;idx_key<32;idx_key=idx_key+1) begin
            if(cnt_x>=32+(idx_key%8)*96 && cnt_x<120+(idx_key%8)*96
                && cnt_y>=144+(idx_key/8)*64 && cnt_y<200+(idx_key/8)*64) begin
                dec_background=reg_pressed[idx_key] && flag_live ? 24'h27AC91 : 24'h21333F;
            end
        end
        // Fixed cells eliminate coordinate division from the pixel critical path.
        case ({dec_row,dec_column})
            13'd1411: begin dec_character=hex_character(reg_keys[11:8]); flag_override=1; end
            13'd1412: begin dec_character=hex_character(reg_keys[7:4]); flag_override=1; end
            13'd1413: begin dec_character=hex_character(reg_keys[3:0]); flag_override=1; end
            13'd1417: begin dec_character=hex_character(reg_keys[23:20]); flag_override=1; end
            13'd1418: begin dec_character=hex_character(reg_keys[19:16]); flag_override=1; end
            13'd1419: begin dec_character=hex_character(reg_keys[15:12]); flag_override=1; end
            13'd1423: begin dec_character=hex_character(reg_keys[35:32]); flag_override=1; end
            13'd1424: begin dec_character=hex_character(reg_keys[31:28]); flag_override=1; end
            13'd1425: begin dec_character=hex_character(reg_keys[27:24]); flag_override=1; end
            13'd1429: begin dec_character=hex_character(reg_keys[47:44]); flag_override=1; end
            13'd1430: begin dec_character=hex_character(reg_keys[43:40]); flag_override=1; end
            13'd1431: begin dec_character=hex_character(reg_keys[39:36]); flag_override=1; end
            13'd1435: begin dec_character=hex_character(reg_keys[59:56]); flag_override=1; end
            13'd1436: begin dec_character=hex_character(reg_keys[55:52]); flag_override=1; end
            13'd1437: begin dec_character=hex_character(reg_keys[51:48]); flag_override=1; end
            13'd1441: begin dec_character=hex_character(reg_keys[71:68]); flag_override=1; end
            13'd1442: begin dec_character=hex_character(reg_keys[67:64]); flag_override=1; end
            13'd1443: begin dec_character=hex_character(reg_keys[63:60]); flag_override=1; end
            13'd1447: begin dec_character=hex_character(reg_keys[83:80]); flag_override=1; end
            13'd1448: begin dec_character=hex_character(reg_keys[79:76]); flag_override=1; end
            13'd1449: begin dec_character=hex_character(reg_keys[75:72]); flag_override=1; end
            13'd1453: begin dec_character=hex_character(reg_keys[95:92]); flag_override=1; end
            13'd1454: begin dec_character=hex_character(reg_keys[91:88]); flag_override=1; end
            13'd1455: begin dec_character=hex_character(reg_keys[87:84]); flag_override=1; end
            13'd1923: begin dec_character=hex_character(reg_keys[107:104]); flag_override=1; end
            13'd1924: begin dec_character=hex_character(reg_keys[103:100]); flag_override=1; end
            13'd1925: begin dec_character=hex_character(reg_keys[99:96]); flag_override=1; end
            13'd1929: begin dec_character=hex_character(reg_keys[119:116]); flag_override=1; end
            13'd1930: begin dec_character=hex_character(reg_keys[115:112]); flag_override=1; end
            13'd1931: begin dec_character=hex_character(reg_keys[111:108]); flag_override=1; end
            13'd1935: begin dec_character=hex_character(reg_keys[131:128]); flag_override=1; end
            13'd1936: begin dec_character=hex_character(reg_keys[127:124]); flag_override=1; end
            13'd1937: begin dec_character=hex_character(reg_keys[123:120]); flag_override=1; end
            13'd1941: begin dec_character=hex_character(reg_keys[143:140]); flag_override=1; end
            13'd1942: begin dec_character=hex_character(reg_keys[139:136]); flag_override=1; end
            13'd1943: begin dec_character=hex_character(reg_keys[135:132]); flag_override=1; end
            13'd1947: begin dec_character=hex_character(reg_keys[155:152]); flag_override=1; end
            13'd1948: begin dec_character=hex_character(reg_keys[151:148]); flag_override=1; end
            13'd1949: begin dec_character=hex_character(reg_keys[147:144]); flag_override=1; end
            13'd1953: begin dec_character=hex_character(reg_keys[167:164]); flag_override=1; end
            13'd1954: begin dec_character=hex_character(reg_keys[163:160]); flag_override=1; end
            13'd1955: begin dec_character=hex_character(reg_keys[159:156]); flag_override=1; end
            13'd1959: begin dec_character=hex_character(reg_keys[179:176]); flag_override=1; end
            13'd1960: begin dec_character=hex_character(reg_keys[175:172]); flag_override=1; end
            13'd1961: begin dec_character=hex_character(reg_keys[171:168]); flag_override=1; end
            13'd1965: begin dec_character=hex_character(reg_keys[191:188]); flag_override=1; end
            13'd1966: begin dec_character=hex_character(reg_keys[187:184]); flag_override=1; end
            13'd1967: begin dec_character=hex_character(reg_keys[183:180]); flag_override=1; end
            13'd2435: begin dec_character=hex_character(reg_keys[203:200]); flag_override=1; end
            13'd2436: begin dec_character=hex_character(reg_keys[199:196]); flag_override=1; end
            13'd2437: begin dec_character=hex_character(reg_keys[195:192]); flag_override=1; end
            13'd2441: begin dec_character=hex_character(reg_keys[215:212]); flag_override=1; end
            13'd2442: begin dec_character=hex_character(reg_keys[211:208]); flag_override=1; end
            13'd2443: begin dec_character=hex_character(reg_keys[207:204]); flag_override=1; end
            13'd2447: begin dec_character=hex_character(reg_keys[227:224]); flag_override=1; end
            13'd2448: begin dec_character=hex_character(reg_keys[223:220]); flag_override=1; end
            13'd2449: begin dec_character=hex_character(reg_keys[219:216]); flag_override=1; end
            13'd2453: begin dec_character=hex_character(reg_keys[239:236]); flag_override=1; end
            13'd2454: begin dec_character=hex_character(reg_keys[235:232]); flag_override=1; end
            13'd2455: begin dec_character=hex_character(reg_keys[231:228]); flag_override=1; end
            13'd2459: begin dec_character=hex_character(reg_keys[251:248]); flag_override=1; end
            13'd2460: begin dec_character=hex_character(reg_keys[247:244]); flag_override=1; end
            13'd2461: begin dec_character=hex_character(reg_keys[243:240]); flag_override=1; end
            13'd2465: begin dec_character=hex_character(reg_keys[263:260]); flag_override=1; end
            13'd2466: begin dec_character=hex_character(reg_keys[259:256]); flag_override=1; end
            13'd2467: begin dec_character=hex_character(reg_keys[255:252]); flag_override=1; end
            13'd2471: begin dec_character=hex_character(reg_keys[275:272]); flag_override=1; end
            13'd2472: begin dec_character=hex_character(reg_keys[271:268]); flag_override=1; end
            13'd2473: begin dec_character=hex_character(reg_keys[267:264]); flag_override=1; end
            13'd2477: begin dec_character=hex_character(reg_keys[287:284]); flag_override=1; end
            13'd2478: begin dec_character=hex_character(reg_keys[283:280]); flag_override=1; end
            13'd2479: begin dec_character=hex_character(reg_keys[279:276]); flag_override=1; end
            13'd2947: begin dec_character=hex_character(reg_keys[299:296]); flag_override=1; end
            13'd2948: begin dec_character=hex_character(reg_keys[295:292]); flag_override=1; end
            13'd2949: begin dec_character=hex_character(reg_keys[291:288]); flag_override=1; end
            13'd2953: begin dec_character=hex_character(reg_keys[311:308]); flag_override=1; end
            13'd2954: begin dec_character=hex_character(reg_keys[307:304]); flag_override=1; end
            13'd2955: begin dec_character=hex_character(reg_keys[303:300]); flag_override=1; end
            13'd2959: begin dec_character=hex_character(reg_keys[323:320]); flag_override=1; end
            13'd2960: begin dec_character=hex_character(reg_keys[319:316]); flag_override=1; end
            13'd2961: begin dec_character=hex_character(reg_keys[315:312]); flag_override=1; end
            13'd2965: begin dec_character=hex_character(reg_keys[335:332]); flag_override=1; end
            13'd2966: begin dec_character=hex_character(reg_keys[331:328]); flag_override=1; end
            13'd2967: begin dec_character=hex_character(reg_keys[327:324]); flag_override=1; end
            13'd2971: begin dec_character=hex_character(reg_keys[347:344]); flag_override=1; end
            13'd2972: begin dec_character=hex_character(reg_keys[343:340]); flag_override=1; end
            13'd2973: begin dec_character=hex_character(reg_keys[339:336]); flag_override=1; end
            13'd2977: begin dec_character=hex_character(reg_keys[359:356]); flag_override=1; end
            13'd2978: begin dec_character=hex_character(reg_keys[355:352]); flag_override=1; end
            13'd2979: begin dec_character=hex_character(reg_keys[351:348]); flag_override=1; end
            13'd2983: begin dec_character=hex_character(reg_keys[371:368]); flag_override=1; end
            13'd2984: begin dec_character=hex_character(reg_keys[367:364]); flag_override=1; end
            13'd2985: begin dec_character=hex_character(reg_keys[363:360]); flag_override=1; end
            13'd2989: begin dec_character=hex_character(reg_keys[383:380]); flag_override=1; end
            13'd2990: begin dec_character=hex_character(reg_keys[379:376]); flag_override=1; end
            13'd2991: begin dec_character=hex_character(reg_keys[375:372]); flag_override=1; end
            default: begin end
        endcase
        if(cnt_x>=848 && cnt_x<1248 && cnt_y>=144 && cnt_y<400) dec_background=24'h1B2B36;
        for(idx_encoder=0;idx_encoder<5;idx_encoder=idx_encoder+1) begin
            if(dec_row==10+3*idx_encoder && dec_column>=60 && dec_column<64) begin
                dec_encoder=reg_encoders[idx_encoder*16 +: 16];
                flag_override=1;
                case(dec_column)
                    60: dec_character=hex_character(dec_encoder[15:12]);
                    61: dec_character=hex_character(dec_encoder[11:8]);
                    62: dec_character=hex_character(dec_encoder[7:4]);
                    default: dec_character=hex_character(dec_encoder[3:0]);
                endcase
            end
        end
        // Physical pad transpose: five original row electrodes are vertical bands;
        // seven original column electrodes are horizontal bands, on BOTH pads.
        for(idx_pad=0;idx_pad<2;idx_pad=idx_pad+1) begin
            if(cnt_x>=64+idx_pad*160 && cnt_x<184+idx_pad*160 && cnt_y>=464 && cnt_y<632) begin
                dec_background=reg_touch_ok[idx_pad] && flag_live ? 24'h21333F : 24'h452D36;
                for(idx_band=0;idx_band<5;idx_band=idx_band+1) begin
                    if(cnt_x>=66+idx_pad*160+idx_band*24 && cnt_x<86+idx_pad*160+idx_band*24
                        && reg_touch[idx_pad*12+idx_band] && flag_live && reg_touch_ok[idx_pad]) dec_background=24'h28668C;
                end
                for(idx_band=0;idx_band<7;idx_band=idx_band+1) begin
                    if(cnt_y>=466+idx_band*24 && cnt_y<486+idx_band*24
                        && reg_touch[idx_pad*12+5+idx_band] && flag_live && reg_touch_ok[idx_pad]) dec_background=24'hB38B37;
                end
            end
        end
        // Same center/up/down mapping as the App: region 11=+1, 00=-1, 01=center.
        case(reg_joystick[1:0])
            2'b11: dec_stick_x=584;
            2'b00: dec_stick_x=488;
            default: dec_stick_x=536;
        endcase
        case(reg_joystick[3:2])
            2'b11: dec_stick_y=504;
            2'b00: dec_stick_y=600;
            default: dec_stick_y=552;
        endcase
        if((cnt_x>=512 && cnt_x<560 && cnt_y>=480 && cnt_y<624)
            || (cnt_x>=464 && cnt_x<608 && cnt_y>=528 && cnt_y<576)) dec_background=24'h293D49;
        if(cnt_x>=dec_stick_x-16 && cnt_x<dec_stick_x+16 && cnt_y>=dec_stick_y-16 && cnt_y<dec_stick_y+16)
            dec_background=!reg_joystick[4] ? 24'hE6AE55 : 24'h51D7BE;

        if(cnt_x>=704 && cnt_x<1216 && cnt_y>=496 && cnt_y<624) begin
            dec_background=24'h14242E;
            if(cnt_x[5:0]==0 || cnt_y[4:0]==16) dec_background=24'h293D49;
        end
        if(dec_row==43) begin
            case(dec_column)
                7: begin flag_override=1; dec_character=flag_configured ? "Y" : "N"; end
                15: begin flag_override=1; dec_character=hex_character(reg_effect); end
                25: begin flag_override=1; dec_character=flag_live ? "Y" : "N"; end
                default: begin end
            endcase
        end
    end

    // Stage A: ROM fetch, geometry and subpixel address. Stage B: glyph lookup.
    always @(posedge i_clk) begin
        reg_layout_a<=mem_layout[dec_address];
        reg_character_a<=dec_character; flag_override_a<=flag_override;
        reg_background_a<=dec_background; reg_foreground_a<=dec_foreground;
        flag_glyph_a<=cnt_x[3:0]>=2 && cnt_x[3:0]<12 && cnt_y[3:0]>=1 && cnt_y[3:0]<15;
        reg_glyph_index_a<=34-((cnt_y[3:0]-1)>>1)*5-((cnt_x[3:0]-2)>>1);
        reg_trace_sample_a<=mem_trace[dec_trace_address];
        reg_trace_y_a<=623-cnt_y;
        flag_trace_a<=cnt_x>=704 && cnt_x<1216 && cnt_y>=496 && cnt_y<624;
        reg_background_b<=flag_trace_a && reg_trace_y_a==reg_trace_sample_a ? 24'h62E6C4 : reg_background_a;
        reg_foreground_b<=reg_foreground_a;
        reg_glyph_index_b<=reg_glyph_index_a; flag_glyph_b<=flag_glyph_a;
    end
    DashboardFont Font_Inst(.i_clk(i_clk),.i_character(flag_override_a ? reg_character_a : reg_layout_a),.o_glyph(bus_glyph));
    // Stage C: RGB and every sync signal advance together; blanking is explicitly black.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin reg_hsync<=0; reg_vsync<=0; reg_de<=0; reg_rgb_o<=0; end
        else begin
            reg_hsync<={reg_hsync[1:0],cnt_x>=1390 && cnt_x<1430};
            reg_vsync<={reg_vsync[1:0],cnt_y>=725 && cnt_y<730};
            reg_de<={reg_de[1:0],cnt_x<1280 && cnt_y<720};
            if(!reg_de[1]) reg_rgb_o<=0;
            else reg_rgb_o<=flag_glyph_b && bus_glyph[reg_glyph_index_b] ? reg_foreground_b : reg_background_b;
        end
    end
endmodule
