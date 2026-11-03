`timescale 1ns / 1ps
// SynthUI character/graphics scanout / SynthUI 字符图形流水线。
// Eight ROM pages share deduplicated rows. No CPU, DDR or full framebuffer.
module SynthDisplayVideo #(parameter C_TOUCH_ENABLE=0)(
    input [1:0] i_touch_mode,
    input i_clk,input i_rstn,input i_system_clk,input i_calibrating,
    input [2:0] i_page,input [159:0] i_fields,input i_host_live,
    input i_text_write,input [9:0] i_text_address,input [7:0] i_text_data,
    input [7:0] i_wave,input [6:0] i_spectrum,input i_audio_available,input i_publish,
    output [7:0] o_wave_address,output [5:0] o_spectrum_address,
    output o_blank_start,output [23:0] o_rgb,output o_hsync,output o_vsync,output o_de
);
    reg [10:0] cnt_x;
    reg [9:0] cnt_y;
    reg [6:0] cnt_column;
    reg [3:0] cnt_subpixel;
    (* syn_ramstyle="block_ram" *) reg [7:0] mem_rows [0:511];
    // Up to88 live rows retain the 128-cell stride; eleven 1024x18 banks.
    // prepare_assets.mjs rejects page layouts exceeding this capacity.
    localparam C_CELL_DEPTH=11264;
    // Explicit power-of-two arrays prevent synthesis rounding 11264 up to 16384.
    (* syn_ramstyle="block_ram" *) reg [17:0] mem_cells_main [0:8191];
    (* syn_ramstyle="block_ram" *) reg [17:0] mem_cells_middle [0:2047];
    (* syn_ramstyle="block_ram" *) reg [17:0] mem_cells_tail [0:1023];
    (* syn_ramstyle="block_ram" *) reg [4:0] mem_font [0:1023];
    (* syn_ramstyle="block_ram" *) reg [7:0] mem_text [0:1023];
    (* syn_ramstyle="block_ram" *) reg [6:0] mem_history [0:4095];
    reg [7:0] reg_row;
    reg [17:0] reg_cells_main,reg_cells_middle,reg_cells_tail,reg_cell_meta;
    reg flag_cells_main,flag_cells_tail;
    // Selector and all three RAM outputs belong to the same original read stage.
    wire [17:0] wire_cell=flag_cells_main ? reg_cells_main :
        (flag_cells_tail ? reg_cells_tail : reg_cells_middle);
    reg [7:0] reg_text,reg_character;
    reg [1:0] reg_touch_meta,reg_touch_sync;
    always @(posedge i_clk or negedge i_rstn)begin if(!i_rstn)begin reg_touch_meta<=0;reg_touch_sync<=0;end else begin reg_touch_meta<=C_TOUCH_ENABLE ? i_touch_mode : 2'd0;reg_touch_sync<=reg_touch_meta;end end
    reg [4:0] reg_font;
    reg [23:0] mem_palette [0:15];
    reg [3:0] mem_foreground [0:7];
    reg [10:0] reg_x [0:4];
    reg [9:0] reg_y [0:4];
    reg [3:0] reg_sub [0:4];
    reg [6:0] reg_col [0:1];
    reg [3:0] reg_background [0:1];
    reg [2:0] reg_foreground [0:1];
    // Navigation uses background13 as a marker; foreground bits carry tab ID.
    // Both are already aligned with font pixels, so no extra scanout cycle.
    wire flag_navigation=reg_background[1]==4'd13;
    wire flag_selected_tab=reg_foreground[1]==i_page;
    reg [7:0] reg_wave [0:3];
    reg [6:0] reg_spectrum [0:3];
    reg [6:0] reg_history [0:4];
    reg [5:0] reg_origin,reg_history_write;
    reg [1:0] reg_copy_state;
    reg [3:0] cnt_history_divider;
    reg flag_history_valid;
    wire [9:0] wire_history_y=cnt_y-10'd224;
    wire [10:0] wire_history_x=cnt_x-11'd928;
    wire [5:0] wire_history_row=reg_origin+wire_history_y[6:1];
    wire [5:0] wire_spectrum_address=reg_copy_state!=0 ? reg_history_write : cnt_x[7:2];
    reg [23:0] reg_rgb_o;
    reg flag_hsync_o,flag_vsync_o,flag_de_o;
    reg [31:0] dec_field;
    reg [3:0] dec_nibble;
    reg [7:0] dec_character;
    reg [3:0] dec_background;
    reg [2:0] dec_key_column;
    wire [4:0] wire_key_index={(reg_y[4][5:4]-2'd3),dec_key_column};
    integer idx;
    reg [5:0] reg_valid;
    reg [1:0] reg_host_sync,reg_calibration_sync;
    (* syn_ramstyle="block_ram" *) reg mem_calibration [0:8191];
    reg reg_calibration_pixel;
    wire [7:0] wire_calibration_x=reg_x[3]-11'd512;
    wire [4:0] wire_calibration_y=reg_y[3]-10'd344;
    initial $readmemh("hdmi/calibration.hex",mem_calibration);
    always @(posedge i_clk) reg_calibration_pixel<=mem_calibration[{wire_calibration_y,wire_calibration_x}];
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) reg_calibration_sync<=0;
        else reg_calibration_sync<={reg_calibration_sync[0],i_calibrating};
    end
    wire flag_header=wire_cell[10:0]>=192 && wire_cell[10:0]<224;
    wire [9:0] wire_text_address=wire_cell[9:0]-(flag_header && !reg_host_sync[1] ? 10'd96 : 10'd128);
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) reg_host_sync<=0;
        else reg_host_sync<={reg_host_sync[0],i_host_live};
    end
    initial begin
        $readmemh("hdmi/rows.hex",mem_rows);
        $readmemh("hdmi/cells_main.hex",mem_cells_main);
        $readmemh("hdmi/cells_middle.hex",mem_cells_middle);
        $readmemh("hdmi/cells_tail.hex",mem_cells_tail);
        $readmemh("hdmi/font.hex",mem_font);$readmemh("hdmi/text.hex",mem_text);
        mem_palette[0]=24'h101820;mem_palette[1]=24'h19252f;mem_palette[2]=24'h21323f;mem_palette[3]=24'h344c5c;
        mem_palette[4]=24'hdce8ed;mem_palette[5]=24'h829ba9;mem_palette[6]=24'hefad73;mem_palette[7]=24'h9dcdb7;
        mem_palette[8]=24'hb7a4e2;mem_palette[9]=24'h85c9d1;mem_palette[10]=24'hd98888;mem_palette[11]=24'h0b1218;
        mem_palette[12]=24'h172733;mem_palette[13]=24'h302c29;mem_palette[14]=24'h293a38;mem_palette[15]=24'h795b40;
        mem_foreground[0]=4;mem_foreground[1]=5;mem_foreground[2]=6;mem_foreground[3]=7;
        mem_foreground[4]=8;mem_foreground[5]=9;mem_foreground[6]=10;mem_foreground[7]=3;
        $readmemh("hdmi/history.hex",mem_history);
    end
    assign o_wave_address=cnt_x[7:0]-8'd64;
    assign o_spectrum_address=wire_spectrum_address;
    assign o_blank_start=cnt_x==0 && cnt_y==720;
    assign o_rgb=reg_rgb_o;
    assign o_hsync=flag_hsync_o;
    assign o_vsync=flag_vsync_o;
    assign o_de=flag_de_o;
    always @(posedge i_system_clk) if(i_text_write) mem_text[i_text_address]<=i_text_data;
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin cnt_x<=0;cnt_y<=0;cnt_column<=0;cnt_subpixel<=0;end
        else if(cnt_x==1649) begin
            cnt_x<=0;cnt_column<=0;cnt_subpixel<=0;cnt_y<=cnt_y==749 ? 0 : cnt_y+1'b1;
        end else begin
            cnt_x<=cnt_x+1'b1;
            if(cnt_subpixel==11) begin cnt_subpixel<=0;cnt_column<=cnt_column+1'b1;end
            else cnt_subpixel<=cnt_subpixel+1'b1;
        end
    end
    // A 64x64 history ring is updated only in vertical blank, at about 4 Hz.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin reg_origin<=0;reg_history_write<=0;reg_copy_state<=0;cnt_history_divider<=0;flag_history_valid<=0;end
        else begin
            if(i_publish) begin
                cnt_history_divider<=cnt_history_divider+1'b1;
                if(cnt_history_divider==0) begin reg_history_write<=0;reg_copy_state<=1;end
            end
            case(reg_copy_state)
                1: reg_copy_state<=2;
                2: begin
                    if(reg_history_write==63) begin reg_copy_state<=0;reg_origin<=reg_origin+1'b1;flag_history_valid<=1;end
                    else begin reg_history_write<=reg_history_write+1'b1;reg_copy_state<=1;end
                end
                default: begin end
            endcase
        end
    end
    always @(posedge i_clk) begin
        if(reg_copy_state==2) mem_history[{reg_origin,reg_history_write}]<=i_spectrum;
        reg_history[0]<=mem_history[{wire_history_row,wire_history_x[7:2]}];
        reg_row<=mem_rows[{i_page,cnt_y[9:4]}];
        reg_cells_main<=mem_cells_main[{reg_row[5:0],reg_col[0]}];
        reg_cells_middle<=mem_cells_middle[{reg_row[3:0],reg_col[0]}];
        reg_cells_tail<=mem_cells_tail[{reg_row[2:0],reg_col[0]}];
        flag_cells_main<=!reg_row[6];flag_cells_tail<=reg_row[4];
        reg_cell_meta<=wire_cell;
        reg_text<=mem_text[wire_text_address];
        reg_character<=dec_character;
        reg_font<=mem_font[{reg_character[6:0],reg_y[3][3:1]}];
        reg_background[0]<=reg_cell_meta[17:14];reg_background[1]<=reg_background[0];
        reg_foreground[0]<=reg_cell_meta[13:11];reg_foreground[1]<=reg_foreground[0];
        reg_col[0]<=cnt_column;reg_col[1]<=reg_col[0];
        reg_x[0]<=cnt_x;reg_y[0]<=cnt_y;reg_sub[0]<=cnt_subpixel;
        reg_wave[0]<=i_wave;reg_spectrum[0]<=i_spectrum;
        for(idx=1;idx<5;idx=idx+1) begin reg_x[idx]<=reg_x[idx-1];reg_y[idx]<=reg_y[idx-1];reg_sub[idx]<=reg_sub[idx-1];reg_history[idx]<=reg_history[idx-1];end
        for(idx=1;idx<4;idx=idx+1) begin reg_wave[idx]<=reg_wave[idx-1];reg_spectrum[idx]<=reg_spectrum[idx-1];end
    end
    // Dynamic character fields use fixed word and nibble selections. Latency
    // arrives as packed decimal microseconds; counter fields are hexadecimal.
    always @(*) begin
        dec_field=0;
        case(reg_cell_meta[6:4])
            0: dec_field=i_fields[31:0];1: dec_field=i_fields[63:32];2: dec_field=i_fields[95:64];
            3: dec_field=i_fields[127:96];4: dec_field=i_fields[159:128];default: dec_field=0;
        endcase
        dec_nibble=dec_field[(7-reg_cell_meta[2:0])*4+:4];
        dec_character=reg_cell_meta[7:0];
        if(reg_cell_meta[10:0]>=1152) dec_character=dec_nibble<10 ? 8'd48+dec_nibble : 8'd55+dec_nibble;
        else if(reg_cell_meta[10:0]==1120) dec_character=8'd49+{6'd0,reg_touch_sync};
        else if(reg_cell_meta[10:0]>=128) dec_character=reg_text;
    end
    always @(*) begin
        dec_key_column=0;
        if(reg_x[4]>=756) dec_key_column=7;
        else if(reg_x[4]>=672) dec_key_column=6;
        else if(reg_x[4]>=588) dec_key_column=5;
        else if(reg_x[4]>=504) dec_key_column=4;
        else if(reg_x[4]>=420) dec_key_column=3;
        else if(reg_x[4]>=336) dec_key_column=2;
        else if(reg_x[4]>=252) dec_key_column=1;
        dec_background=reg_background[1];
        if(reg_background[1]==15) dec_background=i_fields[wire_key_index] ? 15 : 2;
        else if(flag_navigation) dec_background=flag_selected_tab ? 4'd6 : 4'd2;
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin reg_rgb_o<=0;flag_hsync_o<=0;flag_vsync_o<=0;flag_de_o<=0;reg_valid<=0;end
        else begin
            reg_valid<={reg_valid[4:0],1'b1};
            flag_hsync_o<=reg_x[4]>=1390 && reg_x[4]<1430;
            flag_vsync_o<=reg_y[4]>=725 && reg_y[4]<730;
            flag_de_o<=reg_valid[5] && reg_x[4]<1280 && reg_y[4]<720;
            reg_rgb_o<=mem_palette[dec_background];
            if(i_page==0 && reg_y[4]>=224 && reg_y[4]<352) begin
                if(reg_x[4]>=64 && reg_x[4]<320) begin
                    reg_rgb_o<=24'h0b1218;
                    if(i_audio_available && reg_y[4]==351-{1'b0,reg_wave[3][7:1]}) reg_rgb_o<=24'h9dcdb7;
                    else if(reg_y[4]==288) reg_rgb_o<=24'h344c5c;
                end
                if(reg_x[4]>=512 && reg_x[4]<768) begin
                    reg_rgb_o<=24'h0b1218;
                    if(i_audio_available && reg_x[4][1:0]!=3 && (351-reg_y[4])<reg_spectrum[3]) reg_rgb_o<=24'hb7a4e2;
                end
                if(reg_x[4]>=928 && reg_x[4]<1184) begin
                    reg_rgb_o<=24'h0b1218;
                    if(flag_history_valid && reg_history[4]!=0) reg_rgb_o<={1'b0,reg_history[4],1'b0,reg_history[4],8'h70};
                end
            end
            if(reg_sub[4]<10 && reg_y[4][3:0]<14 && reg_font[4-reg_sub[4][3:1]]) begin
                if(flag_navigation) reg_rgb_o<=flag_selected_tab ? 24'h101820 : 24'hdce8ed;
                else reg_rgb_o<=mem_palette[mem_foreground[reg_foreground[1]]];
            end
            if(reg_calibration_sync[1] && reg_x[4]>=448 && reg_x[4]<832 && reg_y[4]>=312 && reg_y[4]<408) begin
                reg_rgb_o<=24'h21323f;
                if(reg_x[4]>=512 && reg_x[4]<768 && reg_y[4]>=344 && reg_y[4]<376 && reg_calibration_pixel) reg_rgb_o<=24'hdce8ed;
            end
            if(reg_x[4]>=1280 || reg_y[4]>=720) reg_rgb_o<=0;
        end
    end
endmodule
